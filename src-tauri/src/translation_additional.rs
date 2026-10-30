//! Official NiuTrans, Google Cloud Translation Basic and Caiyun protocols.
//! Sources checked 2026-10-30: niutrans.com/documents/contents/trans_detection,
//! docs.cloud.google.com/translate/docs/reference/rest/v2/translate,
//! docs.cloud.google.com/docs/authentication/api-keys-use,
//! docs.caiyunapp.com/lingocloud-api/index.html.
//! No vendor account was used. Never echo vendor errors (they can contain keys
//! and source text), follow redirects, spawn detached work, or retry billable calls.
use super::{limited_json, transport_error, valid_secret, Client, Value, REQUEST_TIMEOUT};
use serde_json::json;

pub const NIU_ENDPOINT: &str = "https://api.niutrans.com/NiuTransServer/translation";
pub const GOOGLE_ENDPOINT: &str = "https://translation.googleapis.com/language/translate/v2";
pub const CAIYUN_ENDPOINT: &str = "https://api.interpreter.caiyunai.com/v1/translator";

pub fn validate_key(secret: &str) -> Result<(), String> {
    if valid_secret(secret) {
        Ok(())
    } else {
        Err("请填写该翻译平台的完整 API Key / Token".into())
    }
}

fn one_text(value: Option<&Value>) -> Result<String, String> {
    let text = value
        .and_then(Value::as_str)
        .filter(|s| !s.trim().is_empty())
        .ok_or("官方翻译响应缺少有效译文")?;
    Ok(text.to_owned())
}

fn parse_niu(value: &Value, target: &str) -> Result<String, String> {
    if let Some(code) = value.get("error_code") {
        let code = code
            .as_str()
            .map(str::to_owned)
            .unwrap_or_else(|| code.to_string());
        return Err(match code.as_str() {
            "13001" => "小牛翻译流量不足或服务权限受限，请检查账户额度和权限",
            "13002" => "小牛翻译密钥缺失或无效，请检查 API Key",
            "10001" => "小牛翻译请求频率受限，请稍后重试",
            "10003" => "小牛翻译拒绝了文本长度，请缩短输入",
            "13007" => "小牛翻译不支持当前语言方向",
            "13008" => "小牛翻译服务响应超时，请稍后重试",
            _ => "小牛翻译请求失败，请检查密钥、服务权限和额度",
        }
        .into());
    }
    if value
        .get("to")
        .and_then(Value::as_str)
        .is_some_and(|to| to != target)
    {
        return Err("小牛翻译响应目标语言与请求不一致".into());
    }
    one_text(value.get("tgt_text"))
}

fn parse_google(value: &Value) -> Result<String, String> {
    if value.get("error").is_some() {
        return Err("Google 翻译请求失败，请检查凭据、服务开通、结算及额度".into());
    }
    let rows = value
        .pointer("/data/translations")
        .and_then(Value::as_array)
        .filter(|rows| rows.len() == 1)
        .ok_or("Google 翻译返回的文本数量不一致")?;
    one_text(rows[0].get("translatedText"))
}

fn parse_caiyun(value: &Value) -> Result<String, String> {
    if value.get("error").is_some() || value.get("rc").is_some_and(|v| v != 0 && v != "0") {
        return Err("彩云翻译请求失败，请检查 Token、额度与语言方向".into());
    }
    match value.get("target") {
        Some(Value::Array(rows)) if rows.len() == 1 => one_text(rows.first()),
        Some(Value::String(_)) => one_text(value.get("target")),
        _ => Err("彩云翻译返回的文本数量或格式不一致".into()),
    }
}

fn caiyun_direction(source: &str, target: &str) -> Result<String, String> {
    let chinese = |s: &str| matches!(s, "zh" | "zh-Hant");
    let allowed = source == "auto" && matches!(target, "zh" | "zh-Hant" | "en" | "ja" | "ko")
        || source != target
            && (chinese(source) && matches!(target, "zh" | "zh-Hant" | "en" | "ja" | "ko")
                || chinese(target)
                    && matches!(
                        source,
                        "en" | "ja" | "ko" | "de" | "es" | "fr" | "it" | "pt" | "ru" | "tr" | "vi"
                    ));
    if !allowed {
        return Err("彩云翻译当前仅适配官方文档列出的中外互译方向，请选择其他服务".into());
    }
    Ok(format!("{source}2{target}"))
}

async fn request_at(
    client: &Client,
    kind: &str,
    secret: &str,
    text: &str,
    source: &str,
    target: &str,
    endpoint: &str,
) -> Result<String, String> {
    validate_key(secret)?;
    let request = client.post(endpoint).timeout(REQUEST_TIMEOUT);
    let request = match kind {
        "niutrans" => request.form(&[("from", source), ("to", target), ("apikey", secret), ("src_text", text)]),
        "google-translate" => {
            let mut body = json!({"q":[text], "target":target, "format":"text", "model":"nmt"});
            if source != "auto" { body["source"] = json!(source); }
            request.header("X-Goog-Api-Key", secret).json(&body)
        }
        "caiyun" => request.header("X-Authorization", format!("token {secret}")).json(&json!({
            "source":[text], "trans_type":caiyun_direction(source,target)?, "detect":source=="auto", "media":"text"
        })),
        _ => return Err("不支持的官方翻译服务类型".into()),
    };
    let response = request.send().await.map_err(transport_error)?;
    // Google uses HTTP 403 for quota exhaustion as well as permission failures.
    if kind == "google-translate" && response.status().as_u16() == 403 {
        return Err("Google 翻译权限或额度受限，请检查 API Key 限制、服务开通、结算与用量".into());
    }
    let value = limited_json(response).await?;
    match kind {
        "niutrans" => parse_niu(&value, target),
        "google-translate" => parse_google(&value),
        "caiyun" => parse_caiyun(&value),
        _ => Err("不支持的官方翻译服务类型".into()),
    }
}

pub async fn translate(
    client: &Client,
    kind: &str,
    secret: &str,
    text: &str,
    source: &str,
    target: &str,
) -> Result<String, String> {
    let endpoint = match kind {
        "niutrans" => NIU_ENDPOINT,
        "google-translate" => GOOGLE_ENDPOINT,
        "caiyun" => CAIYUN_ENDPOINT,
        _ => return Err("不支持的官方翻译服务类型".into()),
    };
    request_at(client, kind, secret, text, source, target, endpoint).await
}

#[cfg(test)]
#[path = "translation_additional_tests.rs"]
mod tests;
