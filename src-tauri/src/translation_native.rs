//! Official, non-LLM text-translation protocols. Secrets arrive only from the
//! caller's OS-credential cache. Production endpoints are fixed; private `_at`
//! transports exist only so tests can use synthetic local HTTP responses.
//!
//! The shared HTTP client MUST disable redirects (as the application does).
//! All HTTP work stays in the caller's future: cancellation drops that future;
//! there are no detached tasks, retries or billable automatic chunking.
//!
//! Protocol sources, checked 2026-10-28:
//! https://fanyi-api.baidu.com/doc/21
//! https://ai.youdao.com/DOCSIRMA/html/trans/api/wbfy/index.html
//! https://learn.microsoft.com/azure/ai-services/translator/text-translation/reference/v3/translate
//! https://learn.microsoft.com/azure/ai-services/translator/text-translation/reference/authentication

use crate::model::{validate_url, Provider};
use futures_util::StreamExt;
use md5::Md5;
use reqwest::{Client, Response, Url};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

#[path = "translation_additional.rs"]
mod additional;
#[path = "translation_cloud.rs"]
mod cloud;

const BAIDU_ENDPOINT: &str = "https://fanyi-api.baidu.com/api/trans/vip/translate";
const YOUDAO_ENDPOINT: &str = "https://openapi.youdao.com/api";
const MICROSOFT_ROOT: &str = "https://api.cognitive.microsofttranslator.com/";
const MAX_RESPONSE: usize = 2 * 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(45);

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct BaiduCredentials {
    app_id: String,
    secret_key: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct YoudaoCredentials {
    app_key: String,
    app_secret: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct MicrosoftCredentials {
    subscription_key: String,
}

pub fn is_native(kind: &str) -> bool {
    matches!(
        kind,
        "baidu"
            | "youdao"
            | "microsoft"
            | "volcengine"
            | "aliyun"
            | "niutrans"
            | "google-translate"
            | "caiyun"
    )
}

pub fn endpoint(p: &Provider) -> Result<&'static str, String> {
    let expected = match p.kind.as_str() {
        "baidu" => BAIDU_ENDPOINT,
        "youdao" => YOUDAO_ENDPOINT,
        "microsoft" => MICROSOFT_ROOT,
        "volcengine" => cloud::VOLC_ENDPOINT,
        "aliyun" => cloud::ALIYUN_ENDPOINT,
        "niutrans" => additional::NIU_ENDPOINT,
        "google-translate" => additional::GOOGLE_ENDPOINT,
        "caiyun" => additional::CAIYUN_ENDPOINT,
        _ => return Err("不支持的官方翻译服务类型".into()),
    };
    let url = validate_url(&p.base_url)?;
    let official = Url::parse(expected).map_err(|_| "官方翻译端点不可用")?;
    if url.scheme() != "https"
        || url.host_str() != official.host_str()
        || url.port_or_known_default() != Some(443)
        || url.path().trim_end_matches('/') != official.path().trim_end_matches('/')
    {
        return Err("官方翻译凭证只能发送到该服务的固定 HTTPS 端点；不支持代理或自定义路径".into());
    }
    Ok(expected)
}

pub fn validate_provider(p: &Provider) -> Result<(), String> {
    endpoint(p)?;
    if !p.model.is_empty() {
        return Err("官方机器翻译无需模型名称，请清空模型字段".into());
    }
    if p.kind == "microsoft" {
        if p.region.len() > 64
            || !p
                .region
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'-')
        {
            return Err("Microsoft 地域只允许英文字母、数字和短横线，最长 64 字节".into());
        }
    } else if !p.region.is_empty() {
        return Err("该官方翻译服务不使用地域字段，请清空地域".into());
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

fn credentials<T: for<'a> Deserialize<'a>>(secret: &str, error: &str) -> Result<T, String> {
    if secret.len() > 8192 {
        return Err(error.into());
    }
    serde_json::from_str(secret).map_err(|_| error.into())
}

fn baidu_credentials(secret: &str) -> Result<BaiduCredentials, String> {
    let error = "百度翻译凭证需要 appId 和 secretKey，请检查完整凭证和格式";
    let c: BaiduCredentials = credentials(secret, error)?;
    if !valid_id(&c.app_id) || !valid_secret(&c.secret_key) {
        return Err(error.into());
    }
    Ok(c)
}

fn youdao_credentials(secret: &str) -> Result<YoudaoCredentials, String> {
    let error = "有道翻译凭证需要 appKey 和 appSecret，请检查完整凭证和格式";
    let c: YoudaoCredentials = credentials(secret, error)?;
    if !valid_id(&c.app_key) || !valid_secret(&c.app_secret) {
        return Err(error.into());
    }
    Ok(c)
}

fn microsoft_credentials(secret: &str) -> Result<MicrosoftCredentials, String> {
    let error = "Microsoft 翻译凭证需要 subscriptionKey，请检查密钥格式";
    let c: MicrosoftCredentials = credentials(secret, error)?;
    if !valid_secret(&c.subscription_key) {
        return Err(error.into());
    }
    Ok(c)
}

pub fn validate_credentials(kind: &str, secret: &str) -> Result<(), String> {
    match kind {
        "baidu" => baidu_credentials(secret).map(|_| ()),
        "youdao" => youdao_credentials(secret).map(|_| ()),
        "microsoft" => microsoft_credentials(secret).map(|_| ()),
        "volcengine" => cloud::validate_access_key(secret, "火山引擎机器翻译"),
        "aliyun" => cloud::validate_access_key(secret, "阿里云机器翻译"),
        "niutrans" | "google-translate" | "caiyun" => additional::validate_key(secret),
        _ => Err("不支持的官方翻译凭证类型".into()),
    }
}

fn language(kind: &str, value: &str, source: bool) -> Result<String, String> {
    if value == "auto" {
        return if source {
            Ok("auto".into())
        } else {
            Err("请先确定翻译目标语言".into())
        };
    }
    let mapped = match (kind, value) {
        ("baidu", "zh" | "zh-Hans") => "zh",
        ("baidu", "zh-Hant") => "cht",
        ("baidu", "ja") => "jp",
        ("baidu", "ko") => "kor",
        ("baidu", "fr") => "fra",
        ("baidu", "es") => "spa",
        ("youdao", "zh" | "zh-Hans") => "zh-CHS",
        ("youdao", "zh-Hant") => "zh-CHT",
        ("microsoft", "zh") => "zh-Hans",
        ("volcengine" | "aliyun", "zh" | "zh-Hans") => "zh",
        ("volcengine", "zh-Hant") => "zh-Hant",
        ("aliyun", "zh-Hant") => "zh-tw",
        ("niutrans" | "caiyun", "zh" | "zh-Hans") => "zh",
        ("caiyun", "zh-Hant") => "zh-Hant",
        ("google-translate", "zh" | "zh-Hans") => "zh-CN",
        ("google-translate", "zh-Hant") => "zh-TW",
        (_, "en" | "fr" | "de" | "es" | "ru" | "pt" | "it" | "ja" | "ko") => value,
        ("microsoft", "zh-Hans" | "zh-Hant") => value,
        _ => return Err("该官方翻译适配器尚未配置所选语言；请选择受支持语言或其他服务".into()),
    };
    Ok(mapped.into())
}

fn validate_text(kind: &str, text: &str) -> Result<(), String> {
    if text.trim().is_empty() {
        return Err("请输入需要翻译的文本".into());
    }
    // Baidu documents differ by product/tier. Enforce the older conservative
    // UTF-8 byte ceiling; the user's actual plan may impose a smaller limit.
    let exceeds = match kind {
        "baidu" => text.len() > 6000,
        "youdao" | "volcengine" | "aliyun" => text.chars().count() > 5000,
        "microsoft" => text.encode_utf16().count() > 50_000,
        // Conservative application limits, not promises about vendor tier maxima.
        "niutrans" => text.len() > 5000,
        "google-translate" | "caiyun" => text.chars().count() > 5000,
        _ => true,
    };
    if exceeds {
        return Err(match kind {
            "baidu" => {
                "百度通用翻译单次保守限制为 6,000 UTF-8 字节，请缩短输入；实际套餐还可能更小".into()
            }
            "youdao" => "有道文本翻译单次最多 5,000 字符，请缩短输入".into(),
            "volcengine" => "火山引擎机器翻译单次最多 5,000 字符，请缩短输入".into(),
            "aliyun" => "阿里云机器翻译单次最多 5,000 字符，请缩短输入".into(),
            "niutrans" => "小牛翻译单次应用保守上限为 5,000 UTF-8 字节，请缩短输入".into(),
            "google-translate" | "caiyun" => {
                "此翻译接口单次应用保守上限为 5,000 字符，请缩短输入".into()
            }
            _ => "Microsoft 翻译单次最多 50,000 字符，请缩短输入".into(),
        });
    }
    Ok(())
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

fn nonce() -> Result<String, String> {
    let mut bytes = [0u8; 16];
    getrandom::fill(&mut bytes).map_err(|_| "无法生成翻译请求随机签名，请重试")?;
    Ok(hex(&bytes))
}

fn baidu_sign(c: &BaiduCredentials, text: &str, salt: &str) -> String {
    let mut hash = Md5::new();
    // MD5 is the provider's wire signature, never encryption of saved secrets.
    for part in [&c.app_id, text, salt, &c.secret_key] {
        hash.update(part.as_bytes());
    }
    hex(&hash.finalize())
}

fn youdao_input(text: &str) -> String {
    let chars: Vec<char> = text.chars().collect();
    if chars.len() <= 20 {
        return text.into();
    }
    format!(
        "{}{}{}",
        chars[..10].iter().collect::<String>(),
        chars.len(),
        chars[chars.len() - 10..].iter().collect::<String>()
    )
}

fn youdao_sign(c: &YoudaoCredentials, text: &str, salt: &str, time: &str) -> String {
    let mut hash = Sha256::new();
    for part in [&c.app_key, &youdao_input(text), salt, time, &c.app_secret] {
        hash.update(part.as_bytes());
    }
    hex(&hash.finalize())
}

fn transport_error(error: reqwest::Error) -> String {
    if error.is_timeout() {
        "官方翻译服务响应超时，请稍后重试".into()
    } else {
        "无法连接官方翻译服务，请检查网络和 HTTPS 证书".into()
    }
}

async fn limited_json(response: Response) -> Result<Value, String> {
    let status = response.status();
    if !status.is_success() {
        return Err(match status.as_u16() {
            300..=399 => "官方翻译返回重定向，已拒绝跟随以保护凭证".into(),
            401 | 403 => "官方翻译认证或权限失败，请检查完整凭证、地域和服务开通状态".into(),
            400 | 413 => "官方翻译拒绝了文本或语言参数，请检查语言和单次长度限制".into(),
            429 => "官方翻译额度或调用频率受限，请稍后重试".into(),
            code => format!("官方翻译服务返回 HTTP {code}，请稍后重试"),
        });
    }
    if response
        .content_length()
        .is_some_and(|n| n > MAX_RESPONSE as u64)
    {
        return Err("官方翻译响应超过 2 MiB 上限".into());
    }
    let mut bytes = Vec::new();
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(transport_error)?;
        if chunk.len() > MAX_RESPONSE.saturating_sub(bytes.len()) {
            return Err("官方翻译响应超过 2 MiB 上限".into());
        }
        bytes.extend_from_slice(&chunk);
    }
    serde_json::from_slice(&bytes).map_err(|_| "官方翻译未返回有效 JSON".into())
}

fn translated_rows(rows: Option<&Vec<Value>>, field: Option<&str>) -> Result<String, String> {
    let rows = rows.ok_or("官方翻译响应缺少译文列表")?;
    if rows.is_empty() {
        return Err("官方翻译返回的译文为空".into());
    }
    let text = rows
        .iter()
        .map(|row| {
            field
                .map_or(Some(row), |key| row.get(key))
                .and_then(Value::as_str)
                .ok_or("官方翻译的译文格式不兼容")
        })
        .collect::<Result<Vec<_>, _>>()?
        .join("\n");
    if text.trim().is_empty() {
        return Err("官方翻译返回的译文为空".into());
    }
    Ok(text)
}

fn parse_baidu(value: &Value, target: &str) -> Result<String, String> {
    if let Some(code) = value.get("error_code") {
        let code = code
            .as_str()
            .map(str::to_owned)
            .or_else(|| code.as_u64().map(|n| n.to_string()));
        return Err(match code.as_deref() {
            Some("52003" | "54001" | "58000" | "58002") => {
                "百度翻译认证或服务权限失败，请检查 APP ID、密钥和服务开通状态".into()
            }
            Some("54003" | "54004" | "54005") => {
                "百度翻译额度、余额或调用频率受限，请检查套餐后重试".into()
            }
            Some("58001") => "百度翻译不支持当前语言方向，请选择其他语言或服务".into(),
            _ => "百度翻译请求失败，请检查账号、文本长度和服务状态".into(),
        });
    }
    if value.get("to").and_then(Value::as_str) != Some(target) {
        return Err("百度翻译响应的目标语言与请求不一致".into());
    }
    translated_rows(
        value.get("trans_result").and_then(Value::as_array),
        Some("dst"),
    )
}

fn parse_youdao(value: &Value) -> Result<String, String> {
    let code = value
        .get("errorCode")
        .and_then(Value::as_str)
        .ok_or("有道翻译响应缺少状态码")?;
    if code != "0" {
        return Err(match code {
            "108" | "110" | "111" | "202" | "203" | "205" => {
                "有道翻译认证或服务权限失败，请检查应用 ID、应用密钥及文本翻译服务绑定".into()
            }
            "206" | "207" => "有道翻译签名时间或随机数被拒绝，请检查系统时间后重新操作".into(),
            "401" | "411" | "412" => "有道翻译余额或调用频率受限，请检查套餐后重试".into(),
            "102" => "有道翻译不支持当前语言方向，请选择其他语言或服务".into(),
            "103" => "有道翻译拒绝了文本长度，请缩短输入".into(),
            _ => "有道翻译请求失败，请检查应用配置和服务状态".into(),
        });
    }
    translated_rows(value.get("translation").and_then(Value::as_array), None)
}

fn parse_microsoft(value: &Value, target: &str) -> Result<String, String> {
    let rows = value
        .as_array()
        .filter(|r| r.len() == 1)
        .ok_or("Microsoft 翻译返回的文本数量不一致")?;
    let translations = rows[0]
        .get("translations")
        .and_then(Value::as_array)
        .filter(|r| r.len() == 1)
        .ok_or("Microsoft 翻译返回的目标数量不一致")?;
    if !translations[0]
        .get("to")
        .and_then(Value::as_str)
        .is_some_and(|to| to.eq_ignore_ascii_case(target))
    {
        return Err("Microsoft 翻译响应的目标语言与请求不一致".into());
    }
    translated_rows(Some(translations), Some("text"))
}

async fn baidu_at(
    client: &Client,
    c: &BaiduCredentials,
    text: &str,
    source: &str,
    target: &str,
    salt: &str,
    endpoint: &str,
) -> Result<String, String> {
    let response = client
        .post(endpoint)
        .timeout(REQUEST_TIMEOUT)
        .form(&[
            ("q", text),
            ("from", source),
            ("to", target),
            ("appid", &c.app_id),
            ("salt", salt),
            ("sign", &baidu_sign(c, text, salt)),
        ])
        .send()
        .await
        .map_err(transport_error)?;
    parse_baidu(&limited_json(response).await?, target)
}

async fn youdao_at(
    client: &Client,
    c: &YoudaoCredentials,
    text: &str,
    source: &str,
    target: &str,
    salt: &str,
    time: &str,
    endpoint: &str,
) -> Result<String, String> {
    let response = client
        .post(endpoint)
        .timeout(REQUEST_TIMEOUT)
        .form(&[
            ("q", text),
            ("from", source),
            ("to", target),
            ("appKey", &c.app_key),
            ("salt", salt),
            ("curtime", time),
            ("signType", "v3"),
            ("sign", &youdao_sign(c, text, salt, time)),
            ("strict", "true"),
        ])
        .send()
        .await
        .map_err(transport_error)?;
    parse_youdao(&limited_json(response).await?)
}

async fn microsoft_at(
    client: &Client,
    c: &MicrosoftCredentials,
    region: &str,
    text: &str,
    source: &str,
    target: &str,
    root: &str,
) -> Result<String, String> {
    let mut url = Url::parse(root)
        .map_err(|_| "Microsoft 翻译内部端点无效")?
        .join("translate")
        .map_err(|_| "Microsoft 翻译内部端点无效")?;
    url.query_pairs_mut()
        .append_pair("api-version", "3.0")
        .append_pair("to", target)
        .append_pair("textType", "plain");
    if source != "auto" {
        url.query_pairs_mut().append_pair("from", source);
    }
    let mut request = client
        .post(url)
        .timeout(REQUEST_TIMEOUT)
        .header("Ocp-Apim-Subscription-Key", &c.subscription_key)
        .json(&json!([{"Text":text}]));
    if !region.is_empty() {
        request = request.header("Ocp-Apim-Subscription-Region", region);
    }
    parse_microsoft(
        &limited_json(request.send().await.map_err(transport_error)?).await?,
        target,
    )
}

pub async fn translate(
    client: &Client,
    p: &Provider,
    secret: &str,
    text: &str,
    source: &str,
    target: &str,
) -> Result<String, String> {
    validate_provider(p)?;
    validate_text(&p.kind, text)?;
    let source = language(&p.kind, source, true)?;
    let target = language(&p.kind, target, false)?;
    match p.kind.as_str() {
        "baidu" => {
            baidu_at(
                client,
                &baidu_credentials(secret)?,
                text,
                &source,
                &target,
                &nonce()?,
                BAIDU_ENDPOINT,
            )
            .await
        }
        "youdao" => {
            let time = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map_err(|_| "系统时间异常，无法签名有道翻译请求")?
                .as_secs()
                .to_string();
            youdao_at(
                client,
                &youdao_credentials(secret)?,
                text,
                &source,
                &target,
                &nonce()?,
                &time,
                YOUDAO_ENDPOINT,
            )
            .await
        }
        "microsoft" => {
            microsoft_at(
                client,
                &microsoft_credentials(secret)?,
                &p.region,
                text,
                &source,
                &target,
                MICROSOFT_ROOT,
            )
            .await
        }
        "volcengine" => cloud::translate_volcengine(client, secret, text, &source, &target).await,
        "aliyun" => cloud::translate_aliyun(client, secret, text, &source, &target).await,
        "niutrans" | "google-translate" | "caiyun" => {
            additional::translate(client, &p.kind, secret, text, &source, &target).await
        }
        _ => Err("不支持的官方翻译服务类型".into()),
    }
}

#[cfg(test)]
#[path = "translation_native_tests.rs"]
mod tests;
