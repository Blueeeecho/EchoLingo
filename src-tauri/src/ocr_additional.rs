//! Additional official OCR wire protocols. No service lookup, remote image URL,
//! fallback upload, retry or detached task. The caller has already validated
//! canonical Base64 and must use a client with redirects disabled.
//!
//! Sources checked 2026-10-28:
//! https://ai.youdao.com/DOCSIRMA/html/ocr/api/tyocr/index.html
//! https://cloud.google.com/vision/docs/request
//! https://cloud.google.com/vision/docs/ocr
//! https://cloud.google.com/docs/authentication/api-keys-use
//! https://cloud.google.com/vision/quotas

use super::{limited_json, transport_error, valid_id, valid_secret};
use crate::model::validate_url;
use crate::ocr::OcrProvider;
use reqwest::{Client, Url};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const YOUDAO_ENDPOINT: &str = "https://openapi.youdao.com/ocrapi";
const GOOGLE_ENDPOINT: &str = "https://vision.googleapis.com/v1/images:annotate";
const MAX_YOUDAO_FORM: usize = 4_000_000;
const MAX_GOOGLE_JSON: usize = 10_000_000;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(45);

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct YoudaoCredentials {
    app_key: String,
    app_secret: String,
}

pub(super) fn validate_provider(p: &OcrProvider) -> Result<(), String> {
    let expected = match p.kind.as_str() {
        "youdao" => YOUDAO_ENDPOINT,
        "google" => GOOGLE_ENDPOINT,
        _ => return Err("不支持的官方 OCR 类型".into()),
    };
    let actual = validate_url(&p.base_url)?;
    let official = Url::parse(expected).map_err(|_| "官方 OCR 端点不可用")?;
    if actual.scheme() != "https"
        || actual.host_str() != official.host_str()
        || actual.port_or_known_default() != Some(443)
        || actual.path().trim_end_matches('/') != official.path()
    {
        return Err(
            "官方 OCR 凭证只能发送到所选厂商的固定 HTTPS 端点，不支持代理或自定义路径".into(),
        );
    }
    if !p.region.is_empty() {
        return Err("该 OCR 适配器使用固定全球端点，请清空地域字段".into());
    }
    if p.kind == "youdao" && p.model != "general" {
        return Err("有道 OCR 仅支持 general 通用文字识别接口".into());
    }
    if p.kind == "google" {
        google_feature(&p.model)?;
    }
    // Generic auth/template/prompt fields may contain legacy UI defaults, but
    // none participates in either official request protocol below.
    Ok(())
}

fn google_feature(model: &str) -> Result<&str, String> {
    match model {
        "" | "DOCUMENT_TEXT_DETECTION" => Ok("DOCUMENT_TEXT_DETECTION"),
        "TEXT_DETECTION" => Ok("TEXT_DETECTION"),
        _ => Err("Google Vision OCR 仅支持 DOCUMENT_TEXT_DETECTION 或 TEXT_DETECTION".into()),
    }
}

fn youdao_credentials(secret: &str) -> Result<YoudaoCredentials, String> {
    let error = "有道 OCR 凭证需要 JSON 对象 appKey 和 appSecret，请检查完整凭证";
    if secret.len() > 8192 {
        return Err(error.into());
    }
    let credentials: YoudaoCredentials = serde_json::from_str(secret).map_err(|_| error)?;
    if !valid_id(&credentials.app_key) || !valid_secret(&credentials.app_secret) {
        return Err(error.into());
    }
    Ok(credentials)
}

pub(super) fn validate_credentials(kind: &str, secret: &str) -> Result<(), String> {
    match kind {
        "youdao" => youdao_credentials(secret).map(|_| ()),
        // Standard Google API keys are ASCII identifiers, not a JSON service
        // account, Bearer token or arbitrary header value. No real key prefix
        // is required, so dummy-only protocol fixtures remain possible.
        "google" if valid_id(secret) => Ok(()),
        "google" => Err("Google Vision 需要原始 API Key，不能填写 JSON、Bearer 或空白字符".into()),
        _ => Err("不支持的官方 OCR 凭证类型".into()),
    }
}

fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8] = b"0123456789abcdef";
    let mut output = String::with_capacity(bytes.len() * 2);
    for &b in bytes {
        output.push(DIGITS[(b >> 4) as usize] as char);
        output.push(DIGITS[(b & 15) as usize] as char);
    }
    output
}

fn youdao_sign(c: &YoudaoCredentials, image: &str, salt: &str, time: &str) -> String {
    // Canonical Base64 is ASCII. Use character iteration to remain panic-free
    // even in a private fixture; byte length equals its public wire length.
    let input = if image.len() > 20 {
        format!(
            "{}{}{}",
            image.chars().take(10).collect::<String>(),
            image.len(),
            image
                .chars()
                .rev()
                .take(10)
                .collect::<Vec<_>>()
                .into_iter()
                .rev()
                .collect::<String>()
        )
    } else {
        image.to_owned()
    };
    let mut hash = Sha256::new();
    for part in [&c.app_key, &input, salt, time, &c.app_secret] {
        hash.update(part.as_bytes());
    }
    hex(&hash.finalize())
}

fn parse_youdao(value: &Value) -> Result<String, String> {
    let status = value
        .get("errorCode")
        .and_then(Value::as_str)
        .ok_or("有道 OCR 响应缺少状态码")?;
    if status != "0" {
        return Err(match status {
            "108" | "110" | "111" | "202" | "203" | "205" => {
                "有道 OCR 认证或服务权限失败，请检查应用凭证和通用文字识别服务绑定".into()
            }
            "206" | "207" => "有道 OCR 签名时间或随机数被拒绝，请检查系统时间后重试".into(),
            "401" | "411" | "1411" => "有道 OCR 余额、额度或调用频率受限，请检查套餐后重试".into(),
            "1004" | "1412" => "有道 OCR 拒绝了图片大小，请缩小截图".into(),
            _ => "有道 OCR 识别失败，请检查图片尺寸、格式和应用配置".into(),
        });
    }
    let regions = value
        .pointer("/Result/regions")
        .and_then(Value::as_array)
        .ok_or("有道 OCR 响应缺少文字区域")?;
    let mut paragraphs = Vec::new();
    for region in regions {
        let rows = region
            .get("lines")
            .and_then(Value::as_array)
            .ok_or("有道 OCR 的文字区域格式不兼容")?;
        let lines = rows
            .iter()
            .map(|row| {
                row.get("text")
                    .and_then(Value::as_str)
                    .ok_or("有道 OCR 的文字行格式不兼容")
            })
            .collect::<Result<Vec<_>, _>>()?;
        let text = lines.join("\n");
        if !text.trim().is_empty() {
            paragraphs.push(text);
        }
    }
    if paragraphs.is_empty() {
        return Err("有道 OCR 未识别到文字，请选择更清晰的区域".into());
    }
    Ok(paragraphs.join("\n\n"))
}

fn google_error(error: &Value) -> String {
    // Status messages/details may echo image data, keys or arbitrary content.
    // Only classify a fixed known numeric code, and never interpolate it.
    match error.get("code").and_then(Value::as_u64) {
        Some(7 | 16 | 401 | 403) => {
            "Google Vision 认证或权限失败，请检查 API Key、API 限制、服务开通和结算状态".into()
        }
        Some(8 | 429) => "Google Vision 额度或调用频率受限，请稍后重试".into(),
        Some(3 | 400) => "Google Vision 拒绝了图片或请求参数，请检查截图大小和格式".into(),
        _ => "Google Vision OCR 识别失败，请检查服务状态和图片配置".into(),
    }
}

fn parse_google(value: &Value) -> Result<String, String> {
    if let Some(error) = value.get("error") {
        return Err(google_error(error));
    }
    let responses = value
        .get("responses")
        .and_then(Value::as_array)
        .filter(|v| v.len() == 1)
        .ok_or("Google Vision 返回的图片数量不一致")?;
    let response = &responses[0];
    if let Some(error) = response.get("error") {
        return Err(google_error(error));
    }
    if let Some(annotation) = response.get("fullTextAnnotation") {
        let text = annotation
            .get("text")
            .and_then(Value::as_str)
            .ok_or("Google Vision 全文识别格式不兼容")?;
        if !text.trim().is_empty() {
            return Ok(text.to_owned());
        }
    }
    let text = response
        .pointer("/textAnnotations/0/description")
        .and_then(Value::as_str)
        .filter(|v| !v.trim().is_empty())
        .ok_or("Google Vision 未识别到文字，请选择更清晰的区域")?;
    Ok(text.to_owned())
}

fn youdao_form(
    c: &YoudaoCredentials,
    image: &str,
    salt: &str,
    time: &str,
) -> Result<String, String> {
    let signature = youdao_sign(c, image, salt, time);
    let fields = [
        ("img", image),
        ("langType", "auto"),
        ("detectType", "10012"),
        ("imageType", "1"),
        ("docType", "json"),
        ("appKey", c.app_key.as_str()),
        ("salt", salt),
        ("curtime", time),
        ("signType", "v3"),
        ("sign", signature.as_str()),
    ];
    // Reuse the URL form serializer, then send precisely those encoded bytes.
    // Checking the whole form includes escape expansion and all signed fields.
    let mut encoded = Url::parse(YOUDAO_ENDPOINT).map_err(|_| "有道 OCR 内部端点不可用")?;
    encoded.query_pairs_mut().extend_pairs(fields);
    let body = encoded.query().ok_or("有道 OCR 表单编码失败")?;
    if body.len() > MAX_YOUDAO_FORM {
        return Err("有道 OCR 表单超过保守的 4 MB 上限，请缩小截图".into());
    }
    Ok(body.into())
}

async fn youdao_at(
    client: &Client,
    c: &YoudaoCredentials,
    image: &str,
    salt: &str,
    time: &str,
    endpoint: &str,
) -> Result<String, String> {
    let body = youdao_form(c, image, salt, time)?;
    let response = client
        .post(endpoint)
        .timeout(REQUEST_TIMEOUT)
        .header("Content-Type", "application/x-www-form-urlencoded")
        .body(body)
        .send()
        .await
        .map_err(transport_error)?;
    parse_youdao(&limited_json(response, super::MAX_RESPONSE).await?)
}

async fn google_at(
    client: &Client,
    key: &str,
    image: &str,
    feature: &str,
    endpoint: &str,
) -> Result<String, String> {
    let body = serde_json::to_vec(&json!({"requests":[{"image":{"content":image},"features":[{"type":google_feature(feature)?}]}]})).map_err(|_| "Google Vision 请求编码失败")?;
    if body.len() > MAX_GOOGLE_JSON {
        return Err("Google Vision JSON 请求超过 10 MB 上限，请缩小截图".into());
    }
    let response = client
        .post(endpoint)
        .timeout(REQUEST_TIMEOUT)
        .header("x-goog-api-key", key)
        .header("Content-Type", "application/json; charset=utf-8")
        .body(body)
        .send()
        .await
        .map_err(transport_error)?;
    parse_google(&limited_json(response, super::MAX_RESPONSE).await?)
}

pub(super) async fn recognize(
    client: &Client,
    p: &OcrProvider,
    secret: &str,
    image: &str,
) -> Result<String, String> {
    validate_credentials(&p.kind, secret)?;
    match p.kind.as_str() {
        "youdao" => {
            let mut random = [0; 16];
            getrandom::fill(&mut random).map_err(|_| "无法生成有道 OCR 请求随机数")?;
            let time = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map_err(|_| "系统时间异常，无法签名有道 OCR 请求")?
                .as_secs()
                .to_string();
            youdao_at(
                client,
                &youdao_credentials(secret)?,
                image,
                &hex(&random),
                &time,
                YOUDAO_ENDPOINT,
            )
            .await
        }
        "google" => google_at(client, secret, image, &p.model, GOOGLE_ENDPOINT).await,
        _ => Err("不支持的官方 OCR 服务类型".into()),
    }
}

#[cfg(test)]
#[path = "ocr_additional_tests.rs"]
mod tests;
