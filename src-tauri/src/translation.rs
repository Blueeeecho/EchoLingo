use crate::model::{validate_url, Provider, TranslationResult, DEFAULT_PROMPT};
use futures_util::StreamExt;
use serde_json::{json, Value};
use std::time::{Duration, Instant};

#[path = "translation_stream.rs"]
mod streaming;
use streaming::{OpenAiStream, MAX_RESPONSE};

#[cfg(test)]
#[path = "translation_stream_tests.rs"]
mod stream_tests;

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
        // DeepL accepts Chinese sources as ZH, but its target variants are
        // distinct. Never turn a Traditional Chinese target into legacy ZH.
        // https://github.com/DeepL/deepl-api-prompts/blob/main/mcp.md
        "zh-Hans" | "zh-Hant" if source => Some("ZH".into()),
        "zh-Hans" => Some("ZH-HANS".into()),
        "zh-Hant" => Some("ZH-HANT".into()),
        "zh" => Some("ZH".into()),
        "en" => Some(if source { "EN" } else { "EN-US" }.into()),
        other => Some(other.to_ascii_uppercase()),
    }
}
fn libre_language(language: &str) -> &str {
    match language {
        // LibreTranslate/Argos uses zt for Traditional Chinese in either
        // direction. A self-hosted instance must have that language installed;
        // an upstream rejection must remain an error, with no zh fallback.
        // https://docs.libretranslate.com/guides/supported_languages/
        "zh-Hans" => "zh",
        "zh-Hant" => "zt",
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
    translate_one_inner(client, p, key, text, source, target, false, |_| {}).await
}

/// Incremental pure answer snapshots for compatible SSE providers. The caller
/// owns request/epoch validation when publishing them. Dropping this future
/// cancels HTTP reading; no detached task can publish later progress.
pub async fn translate_one_streaming(
    client: &reqwest::Client,
    p: &Provider,
    key: Result<String, String>,
    text: &str,
    source: &str,
    target: &str,
    on_progress: impl Fn(&str) + Send + Sync,
) -> TranslationResult {
    translate_one_inner(client, p, key, text, source, target, true, on_progress).await
}

fn minimax_provider(p: &Provider) -> bool {
    p.kind == "openai"
        && reqwest::Url::parse(&p.base_url)
            .ok()
            .and_then(|url| url.host_str().map(str::to_ascii_lowercase))
            .is_some_and(|host| matches!(host.as_str(), "api.minimax.cn" | "api.minimax.io"))
}

fn streaming_request_body(
    p: &Provider,
    text: &str,
    source: &str,
    target: &str,
    key: &str,
) -> Value {
    let mut body = request_body(p, text, source, target, key);
    if p.kind == "openai" {
        body["stream"] = json!(true);
        // Official MiniMax-only extension; unknown gateways must not receive
        // provider-private parameters or be retried with a different body.
        if minimax_provider(p) {
            body["reasoning_split"] = json!(true);
        }
    }
    body
}

async fn translate_one_inner(
    client: &reqwest::Client,
    p: &Provider,
    key: Result<String, String>,
    text: &str,
    source: &str,
    target: &str,
    want_stream: bool,
    on_progress: impl Fn(&str) + Send + Sync,
) -> TranslationResult {
    let start = Instant::now();
    let result = async {
        if p.kind == "system" {
            // Never consult a credential, build an HTTP request, download a
            // model or activate a UI from this path. Preparation is explicit.
            return crate::platform::system_translate(text, source, target).await;
        }
        if p.kind == "offline" {
            return Err("请使用包含离线模型的 EchoLingo 安装包执行本机翻译".into());
        }
        let key = key?;
        let url = endpoint(p)?;
        let body = if want_stream {
            streaming_request_body(p, text, source, target, &key)
        } else {
            request_body(p, text, source, target, &key)
        };
        let mut request = client.post(url).json(&body);
        let stream_answer = want_stream && p.kind == "openai";
        if stream_answer {
            request = request.header(reqwest::header::ACCEPT, "text/event-stream, application/json");
        }
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
                400 if matches!(p.kind.as_str(), "deepl" | "libretranslate") =>
                    "服务不接受当前语言或请求参数（HTTP 400）；请确认服务已支持所选语言，目标语言不会自动替换".into(),
                401 | 403 => format!(
                    "API 认证失败（HTTP {}），请检查密钥和服务权限",
                    status.as_u16()
                ),
                429 => "服务限流或额度不足（HTTP 429），请稍后重试".into(),
                n => format!("服务返回 HTTP {n}，请检查端点与模型配置"),
            });
        }
        let mut stream = response.bytes_stream();
        let mut bytes = Vec::new();
        let mut sse: Option<OpenAiStream> = None;
        let mut json_response = !stream_answer;
        let mut received = 0_usize;
        let last_progress = std::cell::Cell::new(None::<Instant>);
        let publish = move |answer: &str| {
            let now = Instant::now();
            if last_progress.get().is_none_or(|last| now.duration_since(last) >= Duration::from_millis(35)) {
                on_progress(answer);
                last_progress.set(Some(now));
            }
        };
        while let Some(chunk) = stream.next().await {
            let chunk = chunk.map_err(|e| if e.is_timeout() {
                "服务响应超时（45 秒），请检查网络或缩短输入"
            } else { "接收 API 响应失败，译文可能尚未完成" })?;
            received = received.saturating_add(chunk.len());
            if received > MAX_RESPONSE {
                return Err("API 响应超过 2 MiB 上限".into());
            }
            if let Some(parser) = &mut sse {
                parser.push(&chunk, &publish)?;
                if parser.done() { break; }
            } else {
                bytes.extend_from_slice(&chunk);
                if !json_response {
                    // Some compatible servers ignore stream:true and naturally
                    // return JSON. Sniff this same response, never resend it.
                    // Buffer the UTF-8 BOM if it is split across TCP chunks.
                    let prefix = if bytes.starts_with(&[0xef, 0xbb, 0xbf]) {
                        &bytes[3..]
                    } else if [0xef, 0xbb, 0xbf].starts_with(&bytes) {
                        continue;
                    } else { &bytes[..] };
                    let first = prefix.iter().copied().find(|byte| !byte.is_ascii_whitespace());
                    if let Some(first) = first {
                        if matches!(first, b'{' | b'[') {
                            json_response = true;
                        } else {
                            let mut parser = OpenAiStream::new(minimax_provider(p));
                            parser.push(&bytes, &publish)?;
                            bytes.clear();
                            let done = parser.done();
                            sse = Some(parser);
                            if done { break; }
                        }
                    }
                }
            }
        }
        if let Some(parser) = sse {
            return parser.finish(&publish);
        }
        let bytes = bytes.strip_prefix(&[0xef, 0xbb, 0xbf]).unwrap_or(&bytes);
        let value = serde_json::from_slice(&bytes).map_err(|_| "服务没有返回有效 JSON")?;
        let answer = parse_response(&p.kind, &value)?;
        if stream_answer && minimax_provider(p) {
            streaming::split_minimax_answer(&answer)
        } else { Ok(answer) }
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
    #[tokio::test]
    async fn system_route_does_not_require_a_key_or_use_http() {
        let mut p = crate::model::system_translation_provider(true);
        // Invalid language stops before a native model is used. Even a bogus
        // endpoint and failed credential cannot turn this into an HTTP request.
        p.base_url = "http://127.0.0.1:1/never".into();
        let result = translate_one(
            &reqwest::Client::new(),
            &p,
            Err("credential must not be read".into()),
            "fixture",
            "invalid language",
            "zh-Hans",
        )
        .await;
        assert_eq!(result.error.as_deref(), Some("系统翻译的语言参数无效"));
        assert!(result.text.is_empty());
    }
    fn provider() -> Provider {
        crate::model::Settings::default()
            .providers
            .into_iter()
            .find(|p| p.kind == "openai")
            .unwrap()
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
    fn openai_reasoning_never_becomes_a_translation_or_hides_truncation() {
        // Reasoning-capable compatible models (including MiniMax-M3.1-Flash)
        // return separate reasoning_content. Only the final content is a result.
        let reasoning = "PRIVATE-REASONING-FIXTURE: draft translation";
        assert_eq!(
            parse_response(
                "openai",
                &json!({"choices":[{"finish_reason":"stop","message":{
                    "reasoning_content":reasoning,"content":"第一段。\n\n第二段。"
                }}]})
            )
            .unwrap(),
            "第一段。\n\n第二段。"
        );
        for final_content in [Value::Null, json!(""), json!(" \n ")] {
            let error = parse_response(
                "openai",
                &json!({"choices":[{"finish_reason":"stop","message":{
                    "reasoning_content":reasoning,"content":final_content
                }}]}),
            )
            .unwrap_err();
            assert!(!error.contains(reasoning));
        }
        for reason in ["length", "content_filter"] {
            let error = parse_response(
                "openai",
                &json!({"choices":[{"finish_reason":reason,"message":{
                    "reasoning_content":reasoning,"content":"partial translation"
                }}]}),
            )
            .unwrap_err();
            assert!(!error.contains(reasoning));
            assert!(!error.contains("partial translation"));
        }
    }
    #[test]
    fn deepl_auto_source_is_omitted() {
        let mut p = provider();
        p.kind = "deepl".into();
        let v = request_body(&p, "hello", "auto", "en", "");
        assert!(v.get("source_lang").is_none());
        assert_eq!(v["target_lang"], "EN-US");
    }

    #[test]
    fn chinese_scripts_remain_distinct_for_each_protocol() {
        let mut p = provider();
        for (language, deepl_target, libre_code) in
            [("zh-Hans", "ZH-HANS", "zh"), ("zh-Hant", "ZH-HANT", "zt")]
        {
            p.kind = "deepl".into();
            let v = request_body(&p, "paragraph 1\n\nparagraph 2", language, language, "");
            assert_eq!(v["target_lang"], deepl_target);
            assert_eq!(v["source_lang"], "ZH");
            assert_eq!(v["text"][0], "paragraph 1\n\nparagraph 2");
            p.kind = "libretranslate".into();
            let v = request_body(&p, "paragraph 1\n\nparagraph 2", language, language, "");
            assert_eq!(v["source"], libre_code);
            assert_eq!(v["target"], libre_code);
            assert_eq!(v["q"], "paragraph 1\n\nparagraph 2");
            assert_eq!(
                request_body(&p, "hello", "auto", language, "")["source"],
                "auto"
            );
        }
    }

    #[tokio::test]
    async fn chinese_script_http_requests_never_fall_back_after_rejection() {
        use std::io::{Read, Write};
        use std::net::TcpListener;
        use std::time::Duration;

        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let address = listener.local_addr().unwrap();
        let worker = std::thread::spawn(move || {
            let mut received = Vec::new();
            // Each target succeeds once and is rejected once. Count every
            // request so a hidden retry using a different script cannot pass.
            for kind in ["deepl", "libretranslate"] {
                for (language, translated) in [("zh-Hans", "软件"), ("zh-Hant", "軟體")] {
                    for reject in [false, true] {
                        let deadline = Instant::now() + Duration::from_secs(8);
                        let mut stream = loop {
                            match listener.accept() {
                                Ok((stream, _)) => break stream,
                                Err(e)
                                    if e.kind() == std::io::ErrorKind::WouldBlock
                                        && Instant::now() < deadline =>
                                {
                                    std::thread::sleep(Duration::from_millis(5))
                                }
                                Err(e) => panic!("Fixture accept failed or timed out: {e}"),
                            }
                        };
                        stream.set_nonblocking(false).unwrap();
                        stream
                            .set_read_timeout(Some(Duration::from_secs(5)))
                            .unwrap();
                        let mut bytes = Vec::new();
                        let header_end = loop {
                            let mut chunk = [0_u8; 4096];
                            let n = stream.read(&mut chunk).unwrap();
                            assert!(n > 0);
                            bytes.extend_from_slice(&chunk[..n]);
                            if let Some(i) = bytes.windows(4).position(|w| w == b"\r\n\r\n") {
                                break i + 4;
                            }
                            assert!(bytes.len() < 64 * 1024);
                        };
                        let headers = String::from_utf8(bytes[..header_end].to_vec()).unwrap();
                        let length: usize = headers
                            .lines()
                            .find_map(|line| {
                                let (name, value) = line.split_once(':')?;
                                name.eq_ignore_ascii_case("content-length")
                                    .then(|| value.trim().parse().unwrap())
                            })
                            .unwrap();
                        assert!(length < 64 * 1024);
                        while bytes.len() < header_end + length {
                            let mut chunk = [0_u8; 4096];
                            let n = stream.read(&mut chunk).unwrap();
                            assert!(n > 0);
                            bytes.extend_from_slice(&chunk[..n]);
                        }
                        let body: Value =
                            serde_json::from_slice(&bytes[header_end..header_end + length])
                                .unwrap();
                        let response = if reject {
                            json!({"error":"NEVER-ECHO-KEY software source text"})
                        } else if kind == "deepl" {
                            json!({"translations":[{"text":translated}]})
                        } else {
                            json!({"translatedText":translated})
                        }
                        .to_string();
                        let status = if reject { "400 Bad Request" } else { "200 OK" };
                        write!(stream, "HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{response}", response.len()).unwrap();
                        received.push((kind, language, headers.to_ascii_lowercase(), body));
                    }
                }
            }
            // The client must not open a ninth connection for a fallback.
            assert_eq!(
                listener.accept().unwrap_err().kind(),
                std::io::ErrorKind::WouldBlock
            );
            received
        });
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .unwrap();
        let mut p = provider();
        for kind in ["deepl", "libretranslate"] {
            p.kind = kind.into();
            p.base_url = format!("http://{address}");
            for (language, translated) in [("zh-Hans", "软件"), ("zh-Hant", "軟體")] {
                for reject in [false, true] {
                    let result = translate_one(
                        &client,
                        &p,
                        Ok("NEVER-ECHO-KEY".into()),
                        "software\n\nsource text",
                        "auto",
                        language,
                    )
                    .await;
                    if reject {
                        assert!(result.text.is_empty());
                        let error = result.error.unwrap();
                        assert!(error.contains("HTTP 400"));
                        assert!(error.contains("目标语言不会自动替换"));
                        assert!(!error.contains("NEVER-ECHO-KEY"));
                        assert!(!error.contains("source text"));
                    } else {
                        assert!(result.error.is_none(), "{:?}", result.error);
                        assert_eq!(result.text, translated);
                    }
                }
            }
        }
        let received = worker.join().unwrap();
        assert_eq!(received.len(), 8);
        for (kind, language, headers, body) in received {
            if kind == "deepl" {
                assert!(headers.starts_with("post /v2/translate "));
                assert!(headers.contains("authorization: deepl-auth-key never-echo-key"));
                assert!(body.get("source_lang").is_none());
                assert_eq!(
                    body["target_lang"],
                    if language == "zh-Hans" {
                        "ZH-HANS"
                    } else {
                        "ZH-HANT"
                    }
                );
                assert_eq!(body["text"][0], "software\n\nsource text");
                assert!(!body.to_string().contains("NEVER-ECHO-KEY"));
            } else {
                assert!(headers.starts_with("post /translate "));
                assert!(!headers.contains("authorization:"));
                assert_eq!(body["source"], "auto");
                assert_eq!(
                    body["target"],
                    if language == "zh-Hans" { "zh" } else { "zt" }
                );
                assert_eq!(body["q"], "software\n\nsource text");
                assert_eq!(body["api_key"], "NEVER-ECHO-KEY");
            }
        }
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
                    "{\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"reasoning_content\":\"PRIVATE-REASONING-FIXTURE\",\"content\":\"你好\"}}]}"
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
