//! Volcengine and Aliyun machine-translation request signing.
//! Secrets stay in the caller-supplied credential JSON. Tests lock the
//! canonical request with fixed dates so a signature change is visible.

use futures_util::StreamExt;
use hmac::{Hmac, Mac};
use reqwest::Client;
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const VOLC_HOST: &str = "translate.volcengineapi.com";
const ALIYUN_HOST: &str = "mt.aliyuncs.com";
pub const VOLC_ENDPOINT: &str = "https://translate.volcengineapi.com/";
pub const ALIYUN_ENDPOINT: &str = "https://mt.aliyuncs.com/";
const TIMEOUT: Duration = Duration::from_secs(45);
const MAX_RESPONSE: usize = 2 * 1024 * 1024;

type HmacSha256 = Hmac<Sha256>;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct AccessKey {
    access_key_id: String,
    access_key_secret: String,
}

pub struct SignedRequest {
    pub url: String,
    pub body: String,
    pub content_type: &'static str,
    pub authorization: String,
    pub extra: Vec<(&'static str, String)>,
}

fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8] = b"0123456789abcdef";
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

fn hmac_raw(key: &[u8], message: &str) -> Vec<u8> {
    let mut mac = HmacSha256::new_from_slice(key).expect("HMAC-SHA256 accepts any key length");
    mac.update(message.as_bytes());
    mac.finalize().into_bytes().to_vec()
}

fn hmac_hex(key: &[u8], message: &str) -> String {
    hex(&hmac_raw(key, message))
}

fn percent_encode(value: &str) -> String {
    let mut output = String::new();
    for byte in value.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~') {
            output.push(byte as char);
        } else {
            output.push('%');
            output.push(
                hex(&[byte])
                    .chars()
                    .next()
                    .unwrap_or('0')
                    .to_ascii_uppercase(),
            );
            output.push(
                hex(&[byte])
                    .chars()
                    .nth(1)
                    .unwrap_or('0')
                    .to_ascii_uppercase(),
            );
        }
    }
    output
}

fn valid_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 256
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-'))
}

fn valid_secret(value: &str) -> bool {
    !value.is_empty() && value.len() <= 4096 && value.bytes().all(|byte| byte.is_ascii_graphic())
}

pub fn validate_access_key(secret: &str, label: &str) -> Result<(), String> {
    access_key(secret, label).map(|_| ())
}

fn access_key(secret: &str, label: &str) -> Result<AccessKey, String> {
    let error = format!("{label}需要 accessKeyId 和 accessKeySecret，请检查完整凭证和格式");
    if secret.len() > 8192 {
        return Err(error);
    }
    let parsed: AccessKey = serde_json::from_str(secret).map_err(|_| error.clone())?;
    if !valid_id(&parsed.access_key_id) || !valid_secret(&parsed.access_key_secret) {
        return Err(error);
    }
    Ok(parsed)
}

pub fn volcengine_request(
    access_key_id: &str,
    secret: &str,
    x_date: &str,
    body: &str,
) -> SignedRequest {
    let body_hash = sha256_hex(body.as_bytes());
    let short = &x_date[..8];
    let signed = "content-type;host;x-content-sha256;x-date";
    let canonical = format!(
        "POST\n/\nAction=TranslateText&Version=2020-06-01\ncontent-type:application/json\nhost:{VOLC_HOST}\nx-content-sha256:{body_hash}\nx-date:{x_date}\n\n{signed}\n{body_hash}"
    );
    let scope = format!("{short}/cn-north-1/translate/request");
    let string_to_sign = format!(
        "HMAC-SHA256\n{x_date}\n{scope}\n{}",
        sha256_hex(canonical.as_bytes())
    );
    let mut key = hmac_raw(secret.as_bytes(), short);
    key = hmac_raw(&key, "cn-north-1");
    key = hmac_raw(&key, "translate");
    key = hmac_raw(&key, "request");
    let signature = hmac_hex(&key, &string_to_sign);
    SignedRequest {
        url: format!("https://{VOLC_HOST}/?Action=TranslateText&Version=2020-06-01"),
        body: body.to_owned(),
        content_type: "application/json",
        authorization: format!(
            "HMAC-SHA256 Credential={access_key_id}/{scope}, SignedHeaders={signed}, Signature={signature}"
        ),
        extra: vec![
            ("X-Date", x_date.to_owned()),
            ("X-Content-Sha256", body_hash),
        ],
    }
}

pub fn aliyun_request(
    access_key_id: &str,
    secret: &str,
    x_date: &str,
    nonce: &str,
    fields: &[(&str, &str)],
) -> SignedRequest {
    let mut pairs: Vec<(&str, &str)> = fields.to_vec();
    pairs.sort_by(|left, right| left.0.cmp(right.0));
    let body = pairs
        .iter()
        .map(|(key, value)| format!("{}={}", percent_encode(key), percent_encode(value)))
        .collect::<Vec<_>>()
        .join("&");
    let body_hash = sha256_hex(body.as_bytes());
    let headers = [
        ("content-type", "application/x-www-form-urlencoded"),
        ("host", ALIYUN_HOST),
        ("x-acs-action", "TranslateGeneral"),
        ("x-acs-content-sha256", body_hash.as_str()),
        ("x-acs-date", x_date),
        ("x-acs-signature-nonce", nonce),
        ("x-acs-version", "2018-10-12"),
    ];
    let signed = headers
        .iter()
        .map(|(name, _)| *name)
        .collect::<Vec<_>>()
        .join(";");
    let canonical_headers = headers
        .iter()
        .map(|(name, value)| format!("{name}:{value}\n"))
        .collect::<String>();
    let canonical = format!("POST\n/\n\n{canonical_headers}\n{signed}\n{body_hash}");
    let string_to_sign = format!("ACS3-HMAC-SHA256\n{}", sha256_hex(canonical.as_bytes()));
    let signature = hmac_hex(secret.as_bytes(), &string_to_sign);
    SignedRequest {
        url: format!("https://{ALIYUN_HOST}/"),
        body,
        content_type: "application/x-www-form-urlencoded",
        authorization: format!(
            "ACS3-HMAC-SHA256 Credential={access_key_id},SignedHeaders={signed},Signature={signature}"
        ),
        extra: vec![
            ("x-acs-action", "TranslateGeneral".into()),
            ("x-acs-version", "2018-10-12".into()),
            ("x-acs-date", x_date.to_owned()),
            ("x-acs-signature-nonce", nonce.to_owned()),
            ("x-acs-content-sha256", body_hash),
        ],
    }
}

fn x_date() -> Result<String, String> {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| "系统时间异常，无法签名翻译请求")?
        .as_secs();
    let days = seconds / 86_400;
    let mut year = 1970i32;
    let mut remaining = days;
    loop {
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
        let year_days = if leap { 366 } else { 365 };
        if remaining < year_days {
            break;
        }
        remaining -= year_days;
        year += 1;
    }
    let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    let months = [
        31,
        if leap { 29 } else { 28 },
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    ];
    let mut month = 1;
    for days_in_month in months {
        if remaining < days_in_month {
            break;
        }
        remaining -= days_in_month;
        month += 1;
    }
    let day = remaining + 1;
    let time = seconds % 86_400;
    Ok(format!(
        "{year:04}{month:02}{day:02}T{:02}{:02}{:02}Z",
        time / 3600,
        (time % 3600) / 60,
        time % 60
    ))
}

fn iso_date() -> Result<String, String> {
    let compact = x_date()?;
    Ok(format!(
        "{}-{}-{}T{}:{}:{}Z",
        &compact[0..4],
        &compact[4..6],
        &compact[6..8],
        &compact[9..11],
        &compact[11..13],
        &compact[13..15]
    ))
}

fn nonce() -> Result<String, String> {
    let mut bytes = [0u8; 16];
    getrandom::fill(&mut bytes).map_err(|_| "无法生成翻译请求随机签名，请重试")?;
    Ok(hex(&bytes))
}

async fn limited_json(response: reqwest::Response) -> Result<Value, String> {
    let status = response.status();
    let mut stream = response.bytes_stream();
    let mut bytes = Vec::new();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|_| "读取翻译响应失败".to_string())?;
        if bytes.len().saturating_add(chunk.len()) > MAX_RESPONSE {
            return Err("翻译响应超过大小限制".into());
        }
        bytes.extend_from_slice(&chunk);
    }
    if !status.is_success() {
        return Err(match status.as_u16() {
            401 | 403 => "API 认证失败，请检查 AccessKey 和服务权限".into(),
            429 => "服务限流或额度不足，请稍后重试。免费额度用完后服务商可能改为按量计费。".into(),
            code => format!("翻译服务返回 HTTP {code}，请检查账号是否已开通机器翻译"),
        });
    }
    serde_json::from_slice(&bytes).map_err(|_| "翻译服务返回了无法识别的响应".into())
}

pub async fn translate_volcengine(
    client: &Client,
    secret: &str,
    text: &str,
    source: &str,
    target: &str,
) -> Result<String, String> {
    let key = access_key(secret, "火山引擎机器翻译")?;
    let mut body = json!({ "TargetLanguage": target, "TextList": [text] });
    if source != "auto" {
        body["SourceLanguage"] = json!(source);
    }
    let payload = body.to_string();
    let signed = volcengine_request(
        &key.access_key_id,
        &key.access_key_secret,
        &x_date()?,
        &payload,
    );
    let mut request = client
        .post(&signed.url)
        .timeout(TIMEOUT)
        .header("Content-Type", signed.content_type)
        .header("Authorization", signed.authorization)
        .body(signed.body);
    for (name, value) in signed.extra {
        request = request.header(name, value);
    }
    let value = limited_json(
        request
            .send()
            .await
            .map_err(|_| "无法连接火山引擎机器翻译".to_string())?,
    )
    .await?;
    if value.pointer("/ResponseMetadata/Error").is_some() {
        return Err("火山引擎机器翻译拒绝了请求，请检查语言、额度或是否已开通服务".into());
    }
    value
        .pointer("/TranslationList/0/Translation")
        .and_then(Value::as_str)
        .filter(|text| !text.trim().is_empty())
        .map(str::to_owned)
        .ok_or_else(|| "火山引擎机器翻译没有返回译文".into())
}

pub async fn translate_aliyun(
    client: &Client,
    secret: &str,
    text: &str,
    source: &str,
    target: &str,
) -> Result<String, String> {
    if source == "auto" {
        return Err("阿里云机器翻译需要明确的源语言，请先选择源语言".into());
    }
    let key = access_key(secret, "阿里云机器翻译")?;
    let signed = aliyun_request(
        &key.access_key_id,
        &key.access_key_secret,
        &iso_date()?,
        &nonce()?,
        &[
            ("FormatType", "text"),
            ("Scene", "general"),
            ("SourceLanguage", source),
            ("SourceText", text),
            ("TargetLanguage", target),
        ],
    );
    let mut request = client
        .post(&signed.url)
        .timeout(TIMEOUT)
        .header("Content-Type", signed.content_type)
        .header("Authorization", signed.authorization)
        .body(signed.body);
    for (name, value) in signed.extra {
        request = request.header(name, value);
    }
    let value = limited_json(
        request
            .send()
            .await
            .map_err(|_| "无法连接阿里云机器翻译".to_string())?,
    )
    .await?;
    let code = value.get("Code").map(|item| match item {
        Value::String(text) => text.clone(),
        Value::Number(number) => number.to_string(),
        _ => String::new(),
    });
    if code.as_deref().is_some_and(|code| code != "200") {
        return Err("阿里云机器翻译拒绝了请求，请检查语言、额度或是否已开通通用版。免费额度用完后可能转为按量计费。".into());
    }
    value
        .pointer("/Data/Translated")
        .and_then(Value::as_str)
        .filter(|text| !text.trim().is_empty())
        .map(str::to_owned)
        .ok_or_else(|| "阿里云机器翻译没有返回译文".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn volcengine_signature_matches_the_fixed_canonical_request() {
        let signed = volcengine_request(
            "AKIDEXAMPLE",
            "SKEXAMPLE",
            "20201010T000000Z",
            r#"{"TargetLanguage":"zh","TextList":["Hello"]}"#,
        );
        assert!(signed.authorization.contains(
            "Signature=850b36fcae276100034a2aa506d3a6e4fa6ca0508921a0496ebb267cade9c88b"
        ));
        assert!(signed.extra.iter().any(|(_, value)| value
            == "d7f64ec059e4895d729573e22e47c9c2164a3aa38a809453ff314533935103ea"));
        assert!(signed.url.contains("Action=TranslateText"));
    }

    #[test]
    fn aliyun_signature_matches_the_fixed_form_request() {
        let signed = aliyun_request(
            "AKIDEXAMPLE",
            "SKEXAMPLE",
            "2023-10-26T10:22:32Z",
            "3156853299f313e23d1673dc12e1703d",
            &[
                ("FormatType", "text"),
                ("Scene", "general"),
                ("SourceLanguage", "en"),
                ("SourceText", "Hello"),
                ("TargetLanguage", "zh"),
            ],
        );
        assert_eq!(
            signed.body,
            "FormatType=text&Scene=general&SourceLanguage=en&SourceText=Hello&TargetLanguage=zh"
        );
        assert!(signed.authorization.contains(
            "Signature=8c9a4999adc294da43d288fc0115cffb6db78afe6491d0da2553754a604e992e"
        ));
        assert!(signed.authorization.starts_with("ACS3-HMAC-SHA256 "));
    }

    #[test]
    fn percent_encoding_and_rejected_keys_do_not_invent_credentials() {
        assert_eq!(percent_encode("a b+"), "a%20b%2B");
        assert!(access_key(r#"{"accessKeyId":"AK","accessKeySecret":"secret"}"#, "测试").is_ok());
        assert!(access_key("helloworld", "测试").is_err());
        assert!(access_key(r#"{"accessKeyId":"AK","extra":"no"}"#, "测试").is_err());
    }
}
