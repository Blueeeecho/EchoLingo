use crate::model::{validate_url, Provider, TranslationResult, DEFAULT_PROMPT};
use futures_util::StreamExt;
use serde_json::{json, Value};
use std::time::Instant;

pub fn endpoint(p: &Provider) -> Result<String, String> {
    validate_url(&p.base_url)?;
    let base = p.base_url.trim_end_matches('/');
    let parsed = validate_url(base)?;
    if p.kind == "deepl" && (parsed.path().is_empty() || parsed.path() == "/") {
        return Ok(format!("{base}/v2/translate"));
    }
    let suffix = match p.kind.as_str() {
        "openai" => "/chat/completions",
        "deepl" => "/translate",
        "libretranslate" => "/translate",
        _ => return Err("未知服务类型".into()),
    };
    Ok(if base.ends_with(suffix) {
        base.into()
    } else {
        format!("{base}{suffix}")
    })
}

pub fn deepl_language(language: &str, source: bool) -> Option<String> {
    match language {
        "auto" if source => None,
        "zh-Hans" | "zh-Hant" | "zh" => Some("ZH".into()),
        "en" => Some(if source { "EN" } else { "EN-US" }.into()),
        other => Some(other.to_ascii_uppercase()),
    }
}
fn libre_language(language: &str) -> &str {
    match language {
        "zh-Hans" | "zh-Hant" => "zh",
        other => other,
    }
}

pub fn request_body(p: &Provider, text: &str, source: &str, target: &str, key: &str) -> Value {
    match p.kind.as_str() {
        "openai" => {
            let prompt = if p.prompt.trim().is_empty() {
                DEFAULT_PROMPT
            } else {
                &p.prompt
            };
            json!({"model":p.model,"messages":[{"role":"system","content":prompt.replace("{source}",source).replace("{target}",target)},{"role":"user","content":text}],"stream":false})
        }
        "deepl" => {
            let mut v = json!({"text":[text],"target_lang":deepl_language(target,false)});
            if let Some(lang) = deepl_language(source, true) {
                v["source_lang"] = json!(lang);
            }
            v
        }
        _ => {
            json!({"q":text,"source":libre_language(source),"target":libre_language(target),"format":"text","api_key":key})
        }
    }
}

pub fn parse_response(kind: &str, v: &Value) -> Result<String, String> {
    if kind == "openai"
        && matches!(
            v.pointer("/choices/0/finish_reason")
                .and_then(Value::as_str),
            Some("length" | "content_filter")
        )
    {
        return Err("服务返回了截断或过滤的译文，请缩短输入或检查模型限制".into());
    }
    let text = match kind {
        "openai" => v
            .pointer("/choices/0/message/content")
            .and_then(Value::as_str),
        "deepl" => v.pointer("/translations/0/text").and_then(Value::as_str),
        "libretranslate" => v.get("translatedText").and_then(Value::as_str),
        _ => None,
    };
    text.filter(|s| !s.trim().is_empty())
        .map(str::to_owned)
        .ok_or_else(|| "API 返回格式不兼容或译文为空；请检查服务类型和模型".into())
}

pub async fn translate_one(
    client: &reqwest::Client,
    p: &Provider,
    key: Result<String, String>,
    text: &str,
    source: &str,
    target: &str,
) -> TranslationResult {
    let start = Instant::now();
    let result = async {
        let key = key?;
        let url = endpoint(p)?;
        let mut request = client
            .post(url)
            .json(&request_body(p, text, source, target, &key));
        if !key.is_empty() {
            request = if p.kind == "deepl" {
                request.header("Authorization", format!("DeepL-Auth-Key {key}"))
            } else if p.kind == "openai" {
                request.bearer_auth(&key)
            } else {
                request
            };
        }
        let response = request.send().await.map_err(|e| {
            if e.is_timeout() {
                "服务响应超时（45 秒），请检查网络或缩短输入".to_string()
            } else {
                "无法连接服务，请检查网络、HTTPS 证书和 API 地址".to_string()
            }
        })?;
        let status = response.status();
        if !status.is_success() {
            // Do not return raw upstream bodies: gateways may echo credentials or source text.
            return Err(match status.as_u16() {
                401 | 403 => format!(
                    "API 认证失败（HTTP {}），请检查密钥和服务权限",
                    status.as_u16()
                ),
                429 => "服务限流或额度不足（HTTP 429），请稍后重试".into(),
                n => format!("服务返回 HTTP {n}，请检查端点与模型配置"),
            });
        }
        const MAX_RESPONSE: usize = 2 * 1024 * 1024;
        let mut stream = response.bytes_stream();
        let mut bytes = Vec::new();
        while let Some(chunk) = stream.next().await {
            let chunk = chunk.map_err(|_| "接收 API 响应失败")?;
            if bytes.len() + chunk.len() > MAX_RESPONSE {
                return Err("API 响应超过 2 MiB 上限".into());
            }
            bytes.extend_from_slice(&chunk);
        }
        let value = serde_json::from_slice(&bytes).map_err(|_| "服务没有返回有效 JSON")?;
        parse_response(&p.kind, &value)
    }
    .await;
    TranslationResult {
        provider_id: p.id.clone(),
        provider_name: p.name.clone(),
        text: result.as_ref().cloned().unwrap_or_default(),
        error: result.err(),
        elapsed_ms: start.elapsed().as_millis() as u64,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn provider() -> Provider {
        crate::model::Settings::default().providers.remove(0)
    }
    #[test]
    fn endpoint_does_not_duplicate_full_paths() {
        let mut p = provider();
        p.base_url = "https://example.com/v1/".into();
        assert_eq!(
            endpoint(&p).unwrap(),
            "https://example.com/v1/chat/completions"
        );
        p.base_url = "https://example.com/v1/chat/completions".into();
        assert_eq!(endpoint(&p).unwrap(), p.base_url);
    }
    #[test]
    fn keep_text_out_of_system_prompt_and_preserve_paragraphs() {
        let p = provider();
        let v = request_body(&p, "line1\nline2", "auto", "zh-Hans", "secret");
        assert_eq!(v["messages"][1]["content"], "line1\nline2");
        assert!(!v.to_string().contains("secret"));
        assert!(v["messages"][0]["content"]
            .as_str()
            .unwrap()
            .contains("zh-Hans"));
    }
    #[test]
    fn parse_all_three_protocols_and_fail_on_invalid_responses() {
        assert_eq!(
            parse_response(
                "openai",
                &json!({"choices":[{"message":{"content":"你好"}}]})
            )
            .unwrap(),
            "你好"
        );
        assert_eq!(
            parse_response("deepl", &json!({"translations":[{"text":"你好"}]})).unwrap(),
            "你好"
        );
        assert_eq!(
            parse_response("libretranslate", &json!({"translatedText":"你好"})).unwrap(),
            "你好"
        );
        assert!(parse_response("openai", &json!({"error":{"message":"secret"}})).is_err());
        assert!(
            parse_response("openai", &json!({"choices":[{"message":{"content":" "}}]})).is_err()
        );
    }
    #[test]
    fn deepl_auto_source_is_omitted() {
        let mut p = provider();
        p.kind = "deepl".into();
        let v = request_body(&p, "hello", "auto", "en", "");
        assert!(v.get("source_lang").is_none());
        assert_eq!(v["target_lang"], "EN-US");
    }
    #[tokio::test]
    async fn actual_http_request_is_parsed_and_errors_are_redacted() {
        use std::io::{Read, Write};
        use std::net::TcpListener;
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let server = std::thread::spawn(move || {
            for i in 0..2 {
                let (mut s, _) = listener.accept().unwrap();
                let mut b = [0u8; 8192];
                let n = s.read(&mut b).unwrap();
                let request = String::from_utf8_lossy(&b[..n]);
                assert!(request.starts_with("POST /v1/chat/completions"));
                assert!(request
                    .to_ascii_lowercase()
                    .contains("authorization: bearer test-only"));
                let body = if i == 0 {
                    "{\"choices\":[{\"message\":{\"content\":\"你好\"}}]}"
                } else {
                    "secret test-only"
                };
                let status = if i == 0 { "200 OK" } else { "401 Unauthorized" };
                write!(s,"HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",body.len()).unwrap();
            }
        });
        let mut p = provider();
        p.base_url = format!("http://{addr}/v1");
        let client = reqwest::Client::new();
        let r = translate_one(
            &client,
            &p,
            Ok("test-only".into()),
            "Hello",
            "auto",
            "zh-Hans",
        )
        .await;
        assert_eq!(r.text, "你好");
        assert!(r.error.is_none());
        let r = translate_one(
            &client,
            &p,
            Ok("test-only".into()),
            "Hello",
            "auto",
            "zh-Hans",
        )
        .await;
        assert!(r.error.as_ref().unwrap().contains("401"));
        assert!(!r.error.unwrap().contains("test-only"));
        server.join().unwrap();
    }
}
