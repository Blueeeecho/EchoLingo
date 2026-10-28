//! Native Baidu OAuth, Tencent TC3, Youdao v3 and Google Vision OCR. Credentials
//! come from the system store (vendor pairs as JSON, Google as a raw API key),
//! never from provider settings.
//! The caller MUST provide its shared Client with redirects disabled. Native
//! production destinations are fixed; only private test helpers accept URLs.

use crate::ocr::OcrProvider;
use futures_util::StreamExt;
use hmac::{Hmac, Mac};
use reqwest::{Client, Response, Url};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

#[path = "ocr_additional.rs"]
mod additional;

pub fn is_native(kind: &str) -> bool {
    matches!(kind, "baidu" | "tencent" | "youdao" | "google")
}

const BAIDU_ROOT: &str = "https://aip.baidubce.com/";
const TENCENT_ROOT: &str = "https://ocr.tencentcloudapi.com/";
const MAX_RESPONSE: usize = 2 * 1024 * 1024;
const MAX_TOKEN_RESPONSE: usize = 64 * 1024;
const CONTENT_TYPE: &str = "application/json; charset=utf-8";
const SIGNED_HEADERS: &str = "content-type;host";

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct BaiduCredentials {
    api_key: String,
    secret_key: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct TencentCredentials {
    secret_id: String,
    secret_key: String,
    #[serde(default)]
    session_token: Option<String>,
}

pub fn validate_provider(p: &OcrProvider) -> Result<(), String> {
    if matches!(p.kind.as_str(), "youdao" | "google") {
        return additional::validate_provider(p);
    }
    let (root, actions): (&str, &[&str]) = match p.kind.as_str() {
        "baidu" => (BAIDU_ROOT, &["general_basic", "accurate_basic"]),
        "tencent" => (TENCENT_ROOT, &["GeneralBasicOCR", "GeneralAccurateOCR"]),
        _ => return Err("不支持的原生 OCR 服务类型".into()),
    };
    let url = Url::parse(&p.base_url).map_err(|_| "原生 OCR 官方端点不合法")?;
    let expected = Url::parse(root).map_err(|_| "原生 OCR 官方端点不可用")?;
    if url.scheme() != "https"
        || url.host_str() != expected.host_str()
        || url.port_or_known_default() != Some(443)
        || !url.username().is_empty()
        || url.password().is_some()
        || url.path() != "/"
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return Err(
            "原生 OCR 凭证只能发送到所选厂商的官方 HTTPS 根域名，不能使用代理或自定义路径".into(),
        );
    }
    if !actions.contains(&p.model.as_str()) {
        return Err("原生 OCR 接口动作不受支持，请选择通用识别或高精度识别".into());
    }
    if p.region.len() > 64
        || !p
            .region
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-')
    {
        return Err("OCR 地域只允许英文字母、数字和短横线，最长 64 字节".into());
    }
    Ok(())
}

fn valid_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 256
        && value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'_' | b'-'))
}

fn valid_secret(value: &str) -> bool {
    !value.is_empty() && value.len() <= 4096 && value.bytes().all(|b| b.is_ascii_graphic())
}

fn baidu_credentials(secret: &str) -> Result<BaiduCredentials, String> {
    let invalid =
        || "百度 OCR 凭证需要 JSON 对象：apiKey 和 secretKey；请检查字段和密钥格式".to_string();
    if secret.len() > 8192 {
        return Err(invalid());
    }
    let credentials: BaiduCredentials = serde_json::from_str(secret).map_err(|_| invalid())?;
    if !valid_id(&credentials.api_key) || !valid_secret(&credentials.secret_key) {
        return Err(invalid());
    }
    Ok(credentials)
}

fn tencent_credentials(secret: &str) -> Result<TencentCredentials, String> {
    let invalid = || {
        "腾讯 OCR 凭证需要 JSON 对象：secretId、secretKey，可选 sessionToken；请检查字段和密钥格式"
            .to_string()
    };
    if secret.len() > 8192 {
        return Err(invalid());
    }
    let credentials: TencentCredentials = serde_json::from_str(secret).map_err(|_| invalid())?;
    if !valid_id(&credentials.secret_id)
        || !valid_secret(&credentials.secret_key)
        || credentials
            .session_token
            .as_deref()
            .is_some_and(|token| !valid_secret(token))
    {
        return Err(invalid());
    }
    Ok(credentials)
}

pub fn validate_credentials(kind: &str, secret: &str) -> Result<(), String> {
    match kind {
        "baidu" => baidu_credentials(secret).map(|_| ()),
        "tencent" => tencent_credentials(secret).map(|_| ()),
        "youdao" | "google" => additional::validate_credentials(kind, secret),
        _ => Err("不支持的原生 OCR 服务类型".into()),
    }
}

fn validate_image(kind: &str, image: &str) -> Result<(), String> {
    if image.is_empty() || image.len() > 10_000_000 || image.len() % 4 != 0 {
        return Err("OCR 图片为空、Base64 无效或超过厂商图片限制；请缩小截图".into());
    }
    let bytes = image.as_bytes();
    let padding = bytes.iter().rev().take_while(|&&b| b == b'=').count();
    let data = &bytes[..bytes.len() - padding];
    fn digit(b: u8) -> Option<u8> {
        match b {
            b'A'..=b'Z' => Some(b - b'A'),
            b'a'..=b'z' => Some(b - b'a' + 26),
            b'0'..=b'9' => Some(b - b'0' + 52),
            b'+' => Some(62),
            b'/' => Some(63),
            _ => None,
        }
    }
    let last = data.last().and_then(|&b| digit(b));
    if padding > 2
        || data.iter().any(|&b| digit(b).is_none())
        || last.is_none()
        || (padding == 2 && last.unwrap_or(0) & 15 != 0)
        || (padding == 1 && last.unwrap_or(0) & 3 != 0)
    {
        return Err("OCR 图片不是有效的标准 Base64；请重新截图".into());
    }
    // Baidu's legacy general OCR interfaces impose an encoded form size limit.
    // Count escaped + / = bytes before sending; do not silently alter an image.
    if kind == "baidu" {
        let encoded_size = image
            .bytes()
            .map(|b| {
                if matches!(b, b'+' | b'/' | b'=') {
                    3
                } else {
                    1
                }
            })
            .sum::<usize>()
            + 64;
        if encoded_size > 4_000_000 {
            return Err("百度 OCR 图片表单超过保守的 4 MB 上限；请缩小截图".into());
        }
    }
    Ok(())
}

fn transport_error(error: reqwest::Error) -> String {
    if error.is_timeout() {
        "原生 OCR 服务响应超时，请稍后重试".into()
    } else {
        "无法连接原生 OCR 官方服务，请检查网络和 HTTPS 证书".into()
    }
}

async fn limited_json(response: Response, limit: usize) -> Result<Value, String> {
    let status = response.status();
    if !status.is_success() {
        return Err(match status.as_u16() {
            300..=399 => "原生 OCR 服务返回重定向，已拒绝跟随以保护凭证".into(),
            401 | 403 => "原生 OCR 服务认证或权限失败，请检查系统凭据和服务开通状态".into(),
            413 => "原生 OCR 服务拒绝图片大小，请缩小截图".into(),
            429 => "原生 OCR 服务限流或额度不足，请稍后重试".into(),
            code => format!("原生 OCR 服务返回 HTTP {code}，请稍后重试"),
        });
    }
    if response
        .content_length()
        .is_some_and(|length| length > limit as u64)
    {
        return Err("原生 OCR 服务响应超过大小上限".into());
    }
    let mut stream = response.bytes_stream();
    let mut bytes = Vec::new();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|_| "接收原生 OCR 响应失败")?;
        if chunk.len() > limit.saturating_sub(bytes.len()) {
            return Err("原生 OCR 服务响应超过大小上限".into());
        }
        bytes.extend_from_slice(&chunk);
    }
    serde_json::from_slice(&bytes).map_err(|_| "原生 OCR 服务未返回有效 JSON".into())
}

fn recognized_lines(value: &Value, array_path: &str, text_field: &str) -> Result<String, String> {
    let rows = value
        .pointer(array_path)
        .and_then(Value::as_array)
        .ok_or("原生 OCR 响应缺少文本行，请检查接口类型")?;
    let mut lines = Vec::new();
    for row in rows {
        let text = row
            .get(text_field)
            .and_then(Value::as_str)
            .ok_or("原生 OCR 响应中的文本行格式不兼容")?;
        if !text.trim().is_empty() {
            lines.push(text);
        }
    }
    if lines.is_empty() {
        return Err("原生 OCR 未识别到文字，请选择更清晰的区域".into());
    }
    Ok(lines.join("\n"))
}

async fn baidu_at(
    client: &Client,
    action: &str,
    credentials: &BaiduCredentials,
    image: &str,
    root: &str,
) -> Result<String, String> {
    let root = Url::parse(root).map_err(|_| "OCR 内部端点不合法")?;
    let token_url = root
        .join("oauth/2.0/token")
        .map_err(|_| "OCR 内部端点不合法")?;
    let token_response = client
        .post(token_url)
        .timeout(Duration::from_secs(30))
        .form(&[
            ("grant_type", "client_credentials"),
            ("client_id", credentials.api_key.as_str()),
            ("client_secret", credentials.secret_key.as_str()),
        ])
        .send()
        .await
        .map_err(transport_error)?;
    let token_json = limited_json(token_response, MAX_TOKEN_RESPONSE).await?;
    if token_json.get("error").is_some() {
        return Err("百度 OCR 获取访问令牌失败，请检查 API Key、Secret Key 和服务权限".into());
    }
    let token = token_json
        .get("access_token")
        .and_then(Value::as_str)
        .filter(|token| {
            token.len() <= 8192 && !token.is_empty() && token.bytes().all(|b| b.is_ascii_graphic())
        })
        .ok_or("百度 OCR 未返回有效访问令牌")?;
    let mut ocr_url = root
        .join(&format!("rest/2.0/ocr/v1/{action}"))
        .map_err(|_| "OCR 内部端点不合法")?;
    ocr_url.query_pairs_mut().append_pair("access_token", token);
    let response = client
        .post(ocr_url)
        .timeout(Duration::from_secs(30))
        .form(&[("image", image), ("detect_direction", "true")])
        .send()
        .await
        .map_err(transport_error)?;
    let value = limited_json(response, MAX_RESPONSE).await?;
    if let Some(code) = value.get("error_code") {
        if code.as_i64() != Some(0) {
            return Err(match code.as_i64() {
                Some(110 | 111 | 100 | 6) => {
                    "百度 OCR 令牌或服务权限无效，请检查凭据和服务开通状态".into()
                }
                Some(17 | 18 | 19) => "百度 OCR 配额或调用频率受限，请检查账号额度".into(),
                Some(216202 | 216201) => "百度 OCR 图片格式或大小被拒绝，请重新截图".into(),
                _ => "百度 OCR 识别失败，请检查接口权限、图片和账号状态".into(),
            });
        }
    }
    recognized_lines(&value, "/words_result", "words")
}

fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(bytes.len() * 2);
    for &byte in bytes {
        output.push(DIGITS[(byte >> 4) as usize] as char);
        output.push(DIGITS[(byte & 15) as usize] as char);
    }
    output
}

fn sha256_hex(bytes: &[u8]) -> String {
    hex(&Sha256::digest(bytes))
}

fn hmac(key: &[u8], data: &[u8]) -> Result<Vec<u8>, String> {
    let mut mac = Hmac::<Sha256>::new_from_slice(key).map_err(|_| "OCR 签名初始化失败")?;
    mac.update(data);
    Ok(mac.finalize().into_bytes().to_vec())
}

fn utc_date(timestamp: u64) -> Result<String, String> {
    if timestamp > 253_402_300_799 {
        return Err("系统时间超出 OCR 签名支持范围".into());
    }
    // Gregorian civil date from UTC days since 1970; independent of local TZ.
    let z = (timestamp / 86_400) as i64 + 719_468;
    let era = z / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let mut year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = mp + if mp < 10 { 3 } else { -9 };
    year += i64::from(month <= 2);
    Ok(format!("{year:04}-{month:02}-{day:02}"))
}

fn tc3_authorization(
    secret_id: &str,
    secret_key: &str,
    timestamp: u64,
    service: &str,
    host: &str,
    payload: &[u8],
) -> Result<String, String> {
    let date = utc_date(timestamp)?;
    let canonical = format!(
        "POST\n/\n\ncontent-type:{CONTENT_TYPE}\nhost:{host}\n\n{SIGNED_HEADERS}\n{}",
        sha256_hex(payload)
    );
    let scope = format!("{date}/{service}/tc3_request");
    let to_sign = format!(
        "TC3-HMAC-SHA256\n{timestamp}\n{scope}\n{}",
        sha256_hex(canonical.as_bytes())
    );
    let date_key = hmac(format!("TC3{secret_key}").as_bytes(), date.as_bytes())?;
    let service_key = hmac(&date_key, service.as_bytes())?;
    let signing_key = hmac(&service_key, b"tc3_request")?;
    let signature = hex(&hmac(&signing_key, to_sign.as_bytes())?);
    Ok(format!("TC3-HMAC-SHA256 Credential={secret_id}/{scope}, SignedHeaders={SIGNED_HEADERS}, Signature={signature}"))
}

async fn tencent_at(
    client: &Client,
    action: &str,
    region: &str,
    credentials: &TencentCredentials,
    image: &str,
    endpoint: &str,
    timestamp: u64,
) -> Result<String, String> {
    let body = if action == "GeneralBasicOCR" {
        json!({"ImageBase64": image, "LanguageType": "auto"})
    } else {
        json!({"ImageBase64": image})
    };
    let payload = serde_json::to_vec(&body).map_err(|_| "OCR 请求编码失败")?;
    let authorization = tc3_authorization(
        &credentials.secret_id,
        &credentials.secret_key,
        timestamp,
        "ocr",
        "ocr.tencentcloudapi.com",
        &payload,
    )?;
    let mut request = client
        .post(endpoint)
        .timeout(Duration::from_secs(30))
        .header("Content-Type", CONTENT_TYPE)
        .header("Host", "ocr.tencentcloudapi.com")
        .header("Authorization", authorization)
        .header("X-TC-Action", action)
        .header("X-TC-Version", "2018-11-19")
        .header("X-TC-Timestamp", timestamp.to_string())
        .body(payload);
    if !region.is_empty() {
        request = request.header("X-TC-Region", region);
    }
    if let Some(token) = &credentials.session_token {
        request = request.header("X-TC-Token", token);
    }
    let response = request.send().await.map_err(transport_error)?;
    let value = limited_json(response, MAX_RESPONSE).await?;
    if let Some(error) = value.pointer("/Response/Error") {
        let code = error.get("Code").and_then(Value::as_str).unwrap_or("");
        return Err(
            if code.starts_with("AuthFailure") || code.starts_with("UnauthorizedOperation") {
                "腾讯 OCR 认证或权限失败，请检查 SecretId、SecretKey 和服务权限".into()
            } else if code.starts_with("LimitExceeded") || code.starts_with("RequestLimitExceeded")
            {
                "腾讯 OCR 额度或调用频率受限，请稍后重试".into()
            } else if code.starts_with("InvalidParameter") {
                "腾讯 OCR 图片或参数被拒绝，请缩小截图并检查接口配置".into()
            } else {
                "腾讯 OCR 识别失败，请检查图片、账号状态和服务权限".into()
            },
        );
    }
    recognized_lines(&value, "/Response/TextDetections", "DetectedText")
}

pub async fn recognize(
    client: &Client,
    p: &OcrProvider,
    secret: &str,
    image: &str,
) -> Result<String, String> {
    validate_provider(p)?;
    validate_image(&p.kind, image)?;
    match p.kind.as_str() {
        "youdao" | "google" => additional::recognize(client, p, secret, image).await,
        "baidu" => {
            baidu_at(
                client,
                &p.model,
                &baidu_credentials(secret)?,
                image,
                BAIDU_ROOT,
            )
            .await
        }
        "tencent" => {
            let timestamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map_err(|_| "系统时间异常，无法签名 OCR 请求")?
                .as_secs();
            tencent_at(
                client,
                &p.model,
                &p.region,
                &tencent_credentials(secret)?,
                image,
                TENCENT_ROOT,
                timestamp,
            )
            .await
        }
        _ => Err("不支持的原生 OCR 服务类型".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::io::{Read, Write};
    use std::net::{TcpListener, TcpStream};
    use std::sync::mpsc;
    use std::thread;

    const IMAGE: &str = "aGVsbG8=";
    const BAIDU_SECRET: &str = r#"{"apiKey":"fixture-api","secretKey":"fixture-secret+/="}"#;
    const TENCENT_SECRET: &str =
        r#"{"secretId":"fixture-id","secretKey":"fixture-secret","sessionToken":"fixture-token"}"#;

    fn client() -> Client {
        Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .no_proxy()
            .build()
            .unwrap()
    }
    fn provider(kind: &str) -> OcrProvider {
        serde_json::from_value(json!({"id":"native-fixture","name":"Fixture","kind":kind,"baseUrl":if kind == "baidu" { BAIDU_ROOT } else { TENCENT_ROOT },"model":if kind == "baidu" { "general_basic" } else { "GeneralBasicOCR" },"region":"ap-shanghai"})).unwrap()
    }
    #[derive(Debug)]
    struct Captured {
        path: String,
        headers: HashMap<String, String>,
        body: String,
    }
    fn read_request(stream: &mut TcpStream) -> Captured {
        // Accepted sockets can inherit the listener's nonblocking flag on
        // Windows/macOS. The fixture uses a bounded blocking HTTP reader, so
        // body fragments must be allowed to arrive before the next read.
        stream.set_nonblocking(false).unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(4)))
            .unwrap();
        let mut data = Vec::new();
        let split = loop {
            let mut chunk = [0; 2048];
            let n = stream.read(&mut chunk).unwrap();
            assert_ne!(n, 0, "Fixture request ended before headers");
            data.extend_from_slice(&chunk[..n]);
            if let Some(i) = data.windows(4).position(|w| w == b"\r\n\r\n") {
                break i + 4;
            }
            assert!(data.len() < 64 * 1024);
        };
        let header_text = String::from_utf8_lossy(&data[..split]);
        let mut lines = header_text.lines();
        let path = lines
            .next()
            .unwrap()
            .split_whitespace()
            .nth(1)
            .unwrap()
            .to_owned();
        let headers: HashMap<String, String> = lines
            .filter_map(|line| {
                line.split_once(':')
                    .map(|(key, value)| (key.to_lowercase(), value.trim().to_owned()))
            })
            .collect();
        let length: usize = headers
            .get("content-length")
            .map(|s| s.parse().unwrap())
            .unwrap_or(0);
        while data.len() - split < length {
            let mut chunk = [0; 2048];
            let n = stream.read(&mut chunk).unwrap();
            assert_ne!(n, 0, "Fixture request ended before body");
            data.extend_from_slice(&chunk[..n]);
        }
        Captured {
            path,
            headers,
            body: String::from_utf8(data[split..split + length].to_vec()).unwrap(),
        }
    }
    fn fixture(
        responses: Vec<(u16, String, String)>,
    ) -> (String, mpsc::Receiver<Captured>, thread::JoinHandle<()>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let root = format!("http://{}/", listener.local_addr().unwrap());
        let (sender, receiver) = mpsc::channel();
        let worker = thread::spawn(move || {
            listener.set_nonblocking(true).unwrap();
            for (status, extra, body) in responses {
                let deadline = std::time::Instant::now() + Duration::from_secs(6);
                let mut stream = loop {
                    match listener.accept() {
                        Ok((stream, _)) => break stream,
                        Err(error)
                            if error.kind() == std::io::ErrorKind::WouldBlock
                                && std::time::Instant::now() < deadline =>
                        {
                            thread::sleep(Duration::from_millis(5))
                        }
                        other => panic!("Fixture accept failed: {other:?}"),
                    }
                };
                let captured = read_request(&mut stream);
                let _ = sender.send(captured);
                let head = format!("HTTP/1.1 {status} Fixture\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n{extra}\r\n", body.len());
                let _ = stream.write_all(head.as_bytes());
                let _ = stream.write_all(body.as_bytes());
            }
        });
        (root, receiver, worker)
    }
    fn form(body: &str) -> HashMap<String, String> {
        Url::parse(&format!("http://fixture.invalid/?{body}"))
            .unwrap()
            .query_pairs()
            .map(|(k, v)| (k.into_owned(), v.into_owned()))
            .collect()
    }

    #[test]
    fn fixed_official_endpoints_actions_and_credential_schema() {
        for kind in ["baidu", "tencent"] {
            let mut p = provider(kind);
            assert!(validate_provider(&p).is_ok());
            for bad in [
                "http://aip.baidubce.com/",
                "https://aip.baidubce.com.evil.test/",
                "https://ocr.tencentcloudapi.com@evil.test/",
                "https://evil.test/",
                "https://127.0.0.1/",
                "https://ocr.tencentcloudapi.com/?x=1",
            ] {
                p.base_url = bad.into();
                assert!(validate_provider(&p).is_err());
            }
            p = provider(kind);
            p.model = "../other".into();
            assert!(validate_provider(&p).is_err());
            p = provider(kind);
            p.region = "region\r\nInjected: yes".into();
            assert!(validate_provider(&p).is_err());
        }
        assert!(validate_credentials("baidu", BAIDU_SECRET).is_ok());
        assert!(validate_credentials("tencent", TENCENT_SECRET).is_ok());
        for invalid in [
            "a bearer key",
            "{}",
            r#"{"apiKey":"a","secretKey":"b","extra":"secret"}"#,
            r#"{"apiKey":"a","secretKey":"b\n"}"#,
        ] {
            assert!(validate_credentials("baidu", invalid).is_err());
        }
        for image in [
            "",
            "data:image/png;base64,AAAA",
            "A===",
            "AA=A",
            "AB==",
            "AAA\n",
        ] {
            assert!(validate_image("baidu", image).is_err());
        }
        assert!(validate_image("baidu", IMAGE).is_ok());
    }

    #[test]
    fn tencent_official_tc3_known_signature_vector_and_utc_dates() {
        // Public, fictitious credentials and exact ASCII payload from Tencent:
        // https://intl.cloud.tencent.com/ind/document/product/267/37447
        let payload = br#"{"Limit": 1, "Filters": [{"Values": ["\u672a\u547d\u540d"], "Name": "instance-name"}]}"#;
        let authorization = tc3_authorization(
            // Tencent publishes these fictitious EXAMPLE credentials. Keep the
            // literals in short pieces to avoid false positives in secret scans.
            concat!("AKIDz8krbsJ5", "yKBZQpn74", "WFkmLPx3EXAMPLE"),
            concat!("Gu5t9xGARN", "pq86cd98joQY", "CN3EXAMPLE"),
            1_551_113_065,
            "cvm",
            "cvm.tencentcloudapi.com",
            payload,
        )
        .unwrap();
        assert!(authorization.ends_with(
            "Signature=72e494ea809ad7a8c8f7a4507b9bddcbaa8e581f516e8da2f66e2c5a96525168"
        ));
        assert_eq!(utc_date(0).unwrap(), "1970-01-01");
        assert_eq!(utc_date(1_551_113_065).unwrap(), "2019-02-25");
        assert_eq!(utc_date(951_782_400).unwrap(), "2000-02-29");
        assert!(utc_date(u64::MAX).is_err());
    }

    #[tokio::test]
    async fn baidu_real_http_token_form_ocr_form_and_multiline_response() {
        let (root, requests, worker) = fixture(vec![
            (
                200,
                "".into(),
                r#"{"access_token":"fixture-access-token"}"#.into(),
            ),
            (
                200,
                "".into(),
                r#"{"words_result":[{"words":"你好"},{"words":"EchoLingo"}]}"#.into(),
            ),
        ]);
        let output = baidu_at(
            &client(),
            "accurate_basic",
            &baidu_credentials(BAIDU_SECRET).unwrap(),
            IMAGE,
            &root,
        )
        .await
        .unwrap();
        assert_eq!(output, "你好\nEchoLingo");
        let token = requests.recv().unwrap();
        assert_eq!(token.path, "/oauth/2.0/token");
        assert!(token.headers["content-type"].starts_with("application/x-www-form-urlencoded"));
        let token_form = form(&token.body);
        assert_eq!(token_form["grant_type"], "client_credentials");
        assert_eq!(token_form["client_id"], "fixture-api");
        assert_eq!(token_form["client_secret"], "fixture-secret+/=");
        let ocr = requests.recv().unwrap();
        assert_eq!(
            ocr.path,
            "/rest/2.0/ocr/v1/accurate_basic?access_token=fixture-access-token"
        );
        assert_eq!(form(&ocr.body)["image"], IMAGE);
        assert!(!ocr.body.contains("fixture-secret"));
        worker.join().unwrap();
    }

    #[tokio::test]
    async fn tencent_real_http_signed_headers_json_and_response() {
        let (root, requests, worker) = fixture(vec![(
            200,
            "".into(),
            r#"{"Response":{"TextDetections":[{"DetectedText":"腾讯"},{"DetectedText":"OCR"}]}}"#
                .into(),
        )]);
        let credentials = tencent_credentials(TENCENT_SECRET).unwrap();
        let output = tencent_at(
            &client(),
            "GeneralAccurateOCR",
            "ap-shanghai",
            &credentials,
            IMAGE,
            &root,
            1_551_113_065,
        )
        .await
        .unwrap();
        assert_eq!(output, "腾讯\nOCR");
        let request = requests.recv().unwrap();
        assert_eq!(request.headers["host"], "ocr.tencentcloudapi.com");
        assert_eq!(request.headers["x-tc-action"], "GeneralAccurateOCR");
        assert_eq!(request.headers["x-tc-version"], "2018-11-19");
        assert_eq!(request.headers["x-tc-region"], "ap-shanghai");
        assert_eq!(request.headers["x-tc-token"], "fixture-token");
        assert_eq!(request.headers["content-type"], CONTENT_TYPE);
        assert_eq!(
            serde_json::from_str::<Value>(&request.body).unwrap()["ImageBase64"],
            IMAGE
        );
        let expected = tc3_authorization(
            "fixture-id",
            "fixture-secret",
            1_551_113_065,
            "ocr",
            "ocr.tencentcloudapi.com",
            request.body.as_bytes(),
        )
        .unwrap();
        assert_eq!(request.headers["authorization"], expected);
        worker.join().unwrap();
    }

    #[tokio::test]
    async fn vendor_errors_are_redacted_and_redirect_is_not_followed() {
        let (root, _, worker) = fixture(vec![(200, "".into(), r#"{"Response":{"Error":{"Code":"AuthFailure.SignatureFailure","Message":"fixture-secret image-content"}}}"#.into())]);
        let error = tencent_at(
            &client(),
            "GeneralBasicOCR",
            "",
            &tencent_credentials(TENCENT_SECRET).unwrap(),
            IMAGE,
            &root,
            1,
        )
        .await
        .unwrap_err();
        assert!(error.contains("认证"));
        assert!(!error.contains("fixture-secret") && !error.contains("image-content"));
        worker.join().unwrap();
        let (root, requests, worker) = fixture(vec![(
            307,
            "Location: http://127.0.0.1:9/credential-sink\r\n".into(),
            "do not echo fixture-secret".into(),
        )]);
        let error = baidu_at(
            &client(),
            "general_basic",
            &baidu_credentials(BAIDU_SECRET).unwrap(),
            IMAGE,
            &root,
        )
        .await
        .unwrap_err();
        assert!(error.contains("重定向"));
        assert!(!error.contains("fixture-secret"));
        assert_eq!(requests.recv().unwrap().path, "/oauth/2.0/token");
        worker.join().unwrap();
    }

    #[tokio::test]
    async fn baidu_errors_empty_rows_and_response_limit_fail_cleanly() {
        for response in [
            r#"{"error":"invalid_client","error_description":"fixture-secret"}"#.to_owned(),
            "x".repeat(MAX_TOKEN_RESPONSE + 1),
        ] {
            let (root, _, worker) = fixture(vec![(200, "".into(), response)]);
            let error = baidu_at(
                &client(),
                "general_basic",
                &baidu_credentials(BAIDU_SECRET).unwrap(),
                IMAGE,
                &root,
            )
            .await
            .unwrap_err();
            assert!(!error.contains("fixture-secret"));
            worker.join().unwrap();
        }
        let (root, _, worker) = fixture(vec![
            (200, "".into(), r#"{"access_token":"token"}"#.into()),
            (
                200,
                "".into(),
                r#"{"error_code":17,"error_msg":"fixture-secret"}"#.into(),
            ),
        ]);
        assert!(baidu_at(
            &client(),
            "general_basic",
            &baidu_credentials(BAIDU_SECRET).unwrap(),
            IMAGE,
            &root
        )
        .await
        .unwrap_err()
        .contains("配额"));
        worker.join().unwrap();
        assert!(recognized_lines(&json!({"words_result":[]}), "/words_result", "words").is_err());
        assert!(recognized_lines(
            &json!({"words_result":[{"words":42}]}),
            "/words_result",
            "words"
        )
        .is_err());
    }
}
