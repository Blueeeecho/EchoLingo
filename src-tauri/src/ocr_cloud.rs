//! Azure AI Vision Read and OCR.space. The OCR.space key must be the user's
//! own key; the vendor's public demo key is rejected.

use crate::ocr::OcrProvider;
use futures_util::StreamExt;
use reqwest::Client;
use serde_json::Value;
use std::time::Duration;

const TIMEOUT: Duration = Duration::from_secs(45);
const MAX_RESPONSE: usize = 2 * 1024 * 1024;
pub fn reject_shared_ocrspace_key(secret: &str) -> Result<(), String> {
    let key = secret.trim();
    if key.is_empty() || key.len() > 256 || !key.bytes().all(|byte| byte.is_ascii_graphic()) {
        return Err("OCR.space 需要你自己的 API Key".into());
    }
    if key.eq_ignore_ascii_case("helloworld") {
        return Err(
            "不能使用 OCR.space 的公共示例密钥，请在 ocr.space 注册后填写你自己的 Key".into(),
        );
    }
    Ok(())
}

pub fn ocrspace_form(image: &str) -> Result<Vec<(&'static str, String)>, String> {
    if image.len() > 1_400_000 {
        return Err("OCR.space 免费层图片大约限制为 1 MB，请缩小截图".into());
    }
    Ok(vec![
        ("base64Image", format!("data:image/png;base64,{image}")),
        ("language", "auto".into()),
        ("OCREngine", "2".into()),
        ("isOverlayRequired", "false".into()),
        ("scale", "true".into()),
    ])
}

pub fn azure_analyze_url(base: &str) -> Result<String, String> {
    let url = reqwest::Url::parse(base).map_err(|_| "Azure AI Vision 地址不是有效的 URL")?;
    let host = url.host_str().unwrap_or("");
    let suffix = ".cognitiveservices.azure.com";
    let name = host.strip_suffix(suffix).unwrap_or("");
    if url.scheme() != "https"
        || url.port_or_known_default() != Some(443)
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
        || name.is_empty()
        || name.contains('.')
        || !name
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
        || url.path() != "/"
    {
        return Err(
            "Azure AI Vision 只能使用你自己的 https://资源名.cognitiveservices.azure.com 终结点"
                .into(),
        );
    }
    Ok(format!(
        "https://{host}/computervision/imageanalysis:analyze?features=read&api-version=2024-02-01"
    ))
}

pub fn validate_provider(provider: &OcrProvider) -> Result<(), String> {
    match provider.kind.as_str() {
        "ocrspace" => {
            let url =
                reqwest::Url::parse(&provider.base_url).map_err(|_| "OCR.space 地址不合法")?;
            if url.scheme() != "https"
                || url.host_str() != Some("api.ocr.space")
                || url.path() != "/"
                || url.query().is_some()
            {
                return Err("OCR.space 只能使用官方地址 https://api.ocr.space/".into());
            }
            if provider.model != "2" && provider.model != "1" {
                return Err("OCR.space 引擎请选择 1 或 2".into());
            }
            Ok(())
        }
        "azure-vision" => {
            azure_analyze_url(&provider.base_url)?;
            if provider.model != "read" {
                return Err("Azure AI Vision 目前只支持 Read".into());
            }
            Ok(())
        }
        _ => Err("不支持的 OCR 服务类型".into()),
    }
}

fn decode_base64(image: &str) -> Result<Vec<u8>, String> {
    fn value(byte: u8) -> Option<u8> {
        match byte {
            b'A'..=b'Z' => Some(byte - b'A'),
            b'a'..=b'z' => Some(byte - b'a' + 26),
            b'0'..=b'9' => Some(byte - b'0' + 52),
            b'+' => Some(62),
            b'/' => Some(63),
            _ => None,
        }
    }
    let bytes = image.as_bytes();
    if bytes.is_empty() || bytes.len() % 4 != 0 {
        return Err("截图不是有效的 Base64".into());
    }
    let mut output = Vec::with_capacity(bytes.len() / 4 * 3);
    for chunk in bytes.chunks(4) {
        let padding = chunk.iter().filter(|&&byte| byte == b'=').count();
        if padding > 2
            || chunk[..4 - padding]
                .iter()
                .any(|&byte| value(byte).is_none())
        {
            return Err("截图不是有效的 Base64".into());
        }
        let mut buffer = [0u8; 4];
        for (index, &byte) in chunk.iter().take(4 - padding).enumerate() {
            buffer[index] = value(byte).unwrap_or(0);
        }
        output.push((buffer[0] << 2) | (buffer[1] >> 4));
        if padding < 2 {
            output.push((buffer[1] << 4) | (buffer[2] >> 2));
        }
        if padding < 1 {
            output.push((buffer[2] << 6) | buffer[3]);
        }
    }
    Ok(output)
}

async fn read_limited(response: reqwest::Response) -> Result<(u16, Vec<u8>), String> {
    let status = response.status().as_u16();
    let mut stream = response.bytes_stream();
    let mut bytes = Vec::new();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|_| "读取 OCR 响应失败".to_string())?;
        if bytes.len().saturating_add(chunk.len()) > MAX_RESPONSE {
            return Err("OCR 响应超过大小限制".into());
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok((status, bytes))
}

pub async fn recognize_azure(
    client: &Client,
    provider: &OcrProvider,
    secret: &str,
    image: &str,
) -> Result<String, String> {
    let key = secret.trim();
    if key.is_empty() || key.len() > 256 || !key.bytes().all(|byte| byte.is_ascii_graphic()) {
        return Err("Azure AI Vision 需要资源密钥".into());
    }
    let bytes = decode_base64(image)?;
    let response = client
        .post(azure_analyze_url(&provider.base_url)?)
        .timeout(TIMEOUT)
        .header("Ocp-Apim-Subscription-Key", key)
        .header("Content-Type", "application/octet-stream")
        .body(bytes)
        .send()
        .await
        .map_err(|_| "无法连接 Azure AI Vision".to_string())?;
    let (status, body) = read_limited(response).await?;
    if status == 401 || status == 403 {
        return Err("Azure AI Vision 认证失败，请检查资源密钥和终结点".into());
    }
    if status == 429 {
        return Err("Azure AI Vision 免费层额度或频率已用完。F0 用完后不会自动升级，请检查资源是否仍是免费层。".into());
    }
    if !(200..300).contains(&status) {
        return Err(format!(
            "Azure AI Vision 返回 HTTP {status}，请检查资源区域和 Read 功能"
        ));
    }
    let value: Value =
        serde_json::from_slice(&body).map_err(|_| "Azure AI Vision 返回了无法识别的响应")?;
    let mut lines = Vec::new();
    if let Some(blocks) = value
        .pointer("/readResult/blocks")
        .and_then(Value::as_array)
    {
        for block in blocks {
            if let Some(items) = block.get("lines").and_then(Value::as_array) {
                for line in items {
                    if let Some(text) = line.get("text").and_then(Value::as_str) {
                        if !text.trim().is_empty() {
                            lines.push(text.to_owned());
                        }
                    }
                }
            }
        }
    }
    if lines.is_empty() {
        return Err("Azure AI Vision 没有识别到文字".into());
    }
    Ok(lines.join("\n"))
}

pub async fn recognize_ocrspace(
    client: &Client,
    provider: &OcrProvider,
    secret: &str,
    image: &str,
) -> Result<String, String> {
    reject_shared_ocrspace_key(secret)?;
    let mut form = ocrspace_form(image)?;
    if let Some(engine) = form.iter_mut().find(|(name, _)| *name == "OCREngine") {
        engine.1 = if provider.model == "1" {
            "1".into()
        } else {
            "2".into()
        };
    }
    let response = client
        .post("https://api.ocr.space/parse/image")
        .timeout(TIMEOUT)
        .header("apikey", secret.trim())
        .form(&form)
        .send()
        .await
        .map_err(|_| "无法连接 OCR.space".to_string())?;
    let (status, body) = read_limited(response).await?;
    if status == 401 || status == 403 {
        return Err("OCR.space 认证失败，请检查你自己的 API Key".into());
    }
    if status == 429 {
        return Err("OCR.space 免费层调用频率已用完，请稍后再试".into());
    }
    let value: Value =
        serde_json::from_slice(&body).map_err(|_| "OCR.space 返回了无法识别的响应")?;
    if value.get("IsErroredOnProcessing").and_then(Value::as_bool) == Some(true)
        || !(200..300).contains(&status)
    {
        return Err("OCR.space 没有完成识别，请检查图片大小、引擎和账号额度".into());
    }
    let text = value
        .pointer("/ParsedResults/0/ParsedText")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim()
        .to_owned();
    if text.is_empty() {
        return Err("OCR.space 没有识别到文字".into());
    }
    Ok(text)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ocrspace_never_accepts_the_public_demo_key() {
        assert!(reject_shared_ocrspace_key("helloworld").is_err());
        assert!(reject_shared_ocrspace_key("HelloWorld").is_err());
        assert!(reject_shared_ocrspace_key("  helloworld  ").is_err());
        assert!(reject_shared_ocrspace_key("user-owned-key").is_ok());
        let form = ocrspace_form("abcd").unwrap();
        assert!(form
            .iter()
            .all(|(_, value)| !value.to_ascii_lowercase().contains("helloworld")));
        assert_eq!(
            form.iter()
                .find(|(name, _)| *name == "OCREngine")
                .unwrap()
                .1,
            "2"
        );
    }

    #[test]
    fn azure_endpoint_stays_on_the_user_resource_host() {
        assert_eq!(
            azure_analyze_url("https://demo.cognitiveservices.azure.com/").unwrap(),
            "https://demo.cognitiveservices.azure.com/computervision/imageanalysis:analyze?features=read&api-version=2024-02-01"
        );
        for rejected in [
            "https://evil.com/",
            "https://cognitiveservices.azure.com.evil.com/",
            "https://demo.cognitiveservices.azure.com.evil.com/",
            "http://demo.cognitiveservices.azure.com/",
            "https://user:secret@demo.cognitiveservices.azure.com/",
            "https://demo.eastus.cognitiveservices.azure.com/",
        ] {
            assert!(azure_analyze_url(rejected).is_err(), "{rejected}");
        }
    }
}
