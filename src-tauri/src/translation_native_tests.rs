//! Synthetic loopback HTTP and published signature examples only. No vendor
//! account, real text, API key, paid API call or automatic retry is used.
use super::*;
use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::mpsc;
use std::thread;
use std::time::Instant;

const BAIDU_SECRET: &str = r#"{"appId":"fixture-app","secretKey":"fixture-secret+/="}"#;
const YOUDAO_SECRET: &str = r#"{"appKey":"fixture-app","appSecret":"fixture-secret"}"#;
const MICROSOFT_SECRET: &str = r#"{"subscriptionKey":"fixture-subscription"}"#;

fn client() -> Client {
    Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .no_proxy()
        .build()
        .unwrap()
}

fn provider(kind: &str) -> Provider {
    serde_json::from_value(json!({"id":"native-mt-fixture","name":"Fixture","kind":kind,"enabled":true,"baseUrl":match kind { "baidu"=>BAIDU_ENDPOINT,"youdao"=>YOUDAO_ENDPOINT,_=>MICROSOFT_ROOT },"model":"","prompt":""})).unwrap()
}

#[derive(Debug)]
struct Request {
    path: String,
    headers: HashMap<String, String>,
    body: String,
}

fn read_request(stream: &mut TcpStream) -> Request {
    stream.set_nonblocking(false).unwrap();
    stream
        .set_read_timeout(Some(Duration::from_secs(3)))
        .unwrap();
    stream
        .set_write_timeout(Some(Duration::from_secs(3)))
        .unwrap();
    let mut bytes = Vec::new();
    let end = loop {
        let mut chunk = [0; 4096];
        let n = stream.read(&mut chunk).unwrap();
        assert!(n > 0);
        bytes.extend_from_slice(&chunk[..n]);
        assert!(bytes.len() < 65536);
        if let Some(i) = bytes.windows(4).position(|s| s == b"\r\n\r\n") {
            break i + 4;
        }
    };
    let header = String::from_utf8(bytes[..end].to_vec()).unwrap();
    let mut lines = header.lines();
    let first = lines.next().unwrap();
    assert!(first.starts_with("POST "));
    let path = first.split_whitespace().nth(1).unwrap().to_owned();
    let headers: HashMap<String, String> = lines
        .filter_map(|l| {
            l.split_once(':')
                .map(|(k, v)| (k.to_ascii_lowercase(), v.trim().to_owned()))
        })
        .collect();
    let size: usize = headers.get("content-length").unwrap().parse().unwrap();
    assert!(size < 65536);
    while bytes.len() < end + size {
        let mut chunk = [0; 4096];
        let n = stream.read(&mut chunk).unwrap();
        assert!(n > 0);
        bytes.extend_from_slice(&chunk[..n]);
    }
    Request {
        path,
        headers,
        body: String::from_utf8(bytes[end..end + size].to_vec()).unwrap(),
    }
}

fn fixture(
    status: u16,
    body: String,
    extra: &str,
    chunked: bool,
) -> (String, mpsc::Receiver<Request>, thread::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let root = format!("http://{}/", listener.local_addr().unwrap());
    let (tx, rx) = mpsc::channel();
    let extra = extra.to_owned();
    let worker = thread::spawn(move || {
        let deadline = Instant::now() + Duration::from_secs(4);
        let mut stream = loop {
            match listener.accept() {
                Ok((s, _)) => break s,
                Err(e)
                    if e.kind() == std::io::ErrorKind::WouldBlock && Instant::now() < deadline =>
                {
                    thread::sleep(Duration::from_millis(2))
                }
                Err(e) => panic!("fixture request missing: {e}"),
            }
        };
        let _ = tx.send(read_request(&mut stream));
        let framing = if chunked {
            "Transfer-Encoding: chunked".into()
        } else {
            format!("Content-Length: {}", body.len())
        };
        let head=format!("HTTP/1.1 {status} Fixture\r\nContent-Type: application/json\r\n{framing}\r\nConnection: close\r\n{extra}\r\n");
        let _ = stream.write_all(head.as_bytes());
        if chunked {
            for bytes in body.as_bytes().chunks(16384) {
                if write!(stream, "{:x}\r\n", bytes.len())
                    .and_then(|_| stream.write_all(bytes))
                    .and_then(|_| stream.write_all(b"\r\n"))
                    .is_err()
                {
                    break;
                }
            }
            let _ = stream.write_all(b"0\r\n\r\n");
        } else {
            let _ = stream.write_all(body.as_bytes());
        }
        drop(stream);
        // Observe the same listener to detect a hidden retry after any result.
        let end = Instant::now() + Duration::from_millis(50);
        while Instant::now() < end {
            assert_eq!(
                listener.accept().unwrap_err().kind(),
                std::io::ErrorKind::WouldBlock,
                "unexpected automatic retry"
            );
            thread::sleep(Duration::from_millis(2));
        }
    });
    (root, rx, worker)
}

fn form(body: &str) -> HashMap<String, String> {
    Url::parse(&format!("http://fixture.invalid/?{body}"))
        .unwrap()
        .query_pairs()
        .map(|(k, v)| (k.into_owned(), v.into_owned()))
        .collect()
}

#[test]
fn only_exact_official_endpoints_and_non_secret_region_are_accepted() {
    for kind in ["baidu", "youdao", "microsoft"] {
        let mut p = provider(kind);
        assert!(validate_provider(&p).is_ok());
        assert!(
            p.region.is_empty(),
            "legacy setting default must remain loadable"
        );
        for url in [
            "http://127.0.0.1:9/",
            "https://fanyi-api.baidu.com.evil.invalid/api/trans/vip/translate",
            "https://openapi.youdao.com@evil.invalid/api",
            "https://api.cognitive.microsofttranslator.com/other",
            "https://openapi.youdao.com/api?key=dummy",
            "https://openapi.youdao.com:8443/api",
            "https://openapi.youdao.com/api#fragment",
        ] {
            p.base_url = url.into();
            assert!(validate_provider(&p).is_err(), "{kind} {url}");
        }
        p = provider(kind);
        p.model = "chat-model".into();
        assert!(validate_provider(&p).is_err());
        p = provider(kind);
        p.region = "eastasia".into();
        assert_eq!(validate_provider(&p).is_ok(), kind == "microsoft");
    }
    let mut p = provider("microsoft");
    p.region = "eastasia\r\nX-Fake: dummy".into();
    assert!(validate_provider(&p).is_err());
}

#[test]
fn credentials_are_complete_typed_pairs_not_bearer_or_settings() {
    for (kind, valid) in [
        ("baidu", BAIDU_SECRET),
        ("youdao", YOUDAO_SECRET),
        ("microsoft", MICROSOFT_SECRET),
    ] {
        assert!(validate_credentials(kind, valid).is_ok());
        for invalid in [
            "",
            "plain-dummy",
            r#"{"apiKey":"dummy"}"#,
            r#"{"appId":"fixture-app","secretKey":"dummy","unexpected":"dummy"}"#,
            r#"{"subscriptionKey":"dummy\r\nHeader"}"#,
        ] {
            assert!(validate_credentials(kind, invalid).is_err());
        }
    }
    assert!(
        validate_credentials(
            "microsoft",
            r#"{"subscriptionKey":"dummy","region":"eastasia"}"#
        )
        .is_err(),
        "region belongs in non-secret settings"
    );
    assert!(validate_credentials("youdao", &"x".repeat(8193)).is_err());
}

#[test]
fn baidu_published_signature_and_unicode_input_before_form_encoding() {
    let c = BaiduCredentials {
        app_id: "2015063000000001".into(),
        secret_key: "12345678".into(),
    };
    // Public Baidu example: appid + apple + 1435660288 + 12345678.
    assert_eq!(
        baidu_sign(&c, "apple", "1435660288"),
        "f89f9594663708c1605f3d736d01d2d4"
    );
    assert_ne!(
        baidu_sign(&c, "中文+ /_?", "salt"),
        baidu_sign(&c, "%E4%B8%AD%E6%96%87%2B+%2F_%3F", "salt")
    );
}

#[test]
fn youdao_v3_truncates_unicode_scalars_not_utf8_bytes_or_percent_encoding() {
    let c = YoudaoCredentials {
        app_key: "fixture-app".into(),
        app_secret: "fixture-secret".into(),
    };
    for text in ["", "中文😀", "abcdefghijklmnopqrst"] {
        assert_eq!(youdao_input(text), text);
    }
    let q = "😀中文abc_+-/。1234567890末尾测试你好";
    assert_eq!(youdao_input(q), "😀中文abc_+-/277890末尾测试你好");
    // Independently calculated with Python hashlib and the provider's Python
    // Unicode slicing definition; synthetic credentials, not an account key.
    assert_eq!(
        youdao_sign(&c, q, "fixture-salt", "1700000000"),
        "ea378cf12c5be85ad7797d6a9a9f0c52da5c9107ff0f6f0f8275ccc56561062d"
    );
}

#[test]
fn language_variants_and_provider_limits_fail_without_fallback_or_chunking() {
    for (kind, zh, trad, ja, ko) in [
        ("baidu", "zh", "cht", "jp", "kor"),
        ("youdao", "zh-CHS", "zh-CHT", "ja", "ko"),
        ("microsoft", "zh-Hans", "zh-Hant", "ja", "ko"),
    ] {
        assert_eq!(language(kind, "zh-Hans", false).unwrap(), zh);
        assert_eq!(language(kind, "zh-Hant", false).unwrap(), trad);
        assert_eq!(language(kind, "ja", true).unwrap(), ja);
        assert_eq!(language(kind, "ko", true).unwrap(), ko);
        assert!(language(kind, "auto", false).is_err());
        assert_eq!(language(kind, "auto", true).unwrap(), "auto");
        assert!(language(kind, "unsupported", true).is_err());
        assert!(validate_text(kind, "  \n").is_err());
    }
    assert!(validate_text("baidu", &"中".repeat(2000)).is_ok());
    assert!(validate_text("baidu", &"中".repeat(2001)).is_err());
    assert!(validate_text("youdao", &"😀".repeat(5000)).is_ok());
    assert!(validate_text("youdao", &"中".repeat(5001)).is_err());
    assert!(validate_text("microsoft", &"😀".repeat(25000)).is_ok());
    assert!(validate_text("microsoft", &"😀".repeat(25001)).is_err());
}

#[test]
fn per_request_salts_use_os_randomness_and_are_not_recorded() {
    let a = nonce().unwrap();
    let b = nonce().unwrap();
    assert_eq!(a.len(), 32);
    assert!(a.bytes().all(|c| c.is_ascii_hexdigit()));
    assert_ne!(a, b);
}

#[tokio::test]
async fn baidu_real_form_preserves_symbols_and_multiline_translation() {
    let (url,requests,worker)=fixture(200,r#"{"from":"en","to":"zh","trans_result":[{"dst":"第一段。"},{"dst":""},{"dst":"第二段 - quiet_pin:"}]}"#.into(),"",false);
    let c = baidu_credentials(BAIDU_SECRET).unwrap();
    let text = "- quiet_pin: a+b / path?\n\nSecond paragraph.😀";
    let output = baidu_at(&client(), &c, text, "en", "zh", "fixture-salt", &url)
        .await
        .unwrap();
    worker.join().unwrap();
    assert_eq!(output, "第一段。\n\n第二段 - quiet_pin:");
    let r = requests.recv().unwrap();
    let f = form(&r.body);
    assert_eq!(f["q"], text);
    assert_eq!(f["appid"], "fixture-app");
    assert_eq!(f["from"], "en");
    assert_eq!(f["to"], "zh");
    assert_eq!(f["sign"], baidu_sign(&c, text, "fixture-salt"));
    assert!(!r.body.contains("fixture-secret"));
    assert!(!r.path.contains("quiet_pin"));
    assert!(!r.headers.contains_key("authorization"));
    assert!(r.headers["content-type"].starts_with("application/x-www-form-urlencoded"));
}

#[tokio::test]
async fn youdao_real_v3_form_uses_strict_languages_without_speech_request() {
    let (url, requests, worker) = fixture(
        200,
        r#"{"errorCode":"0","translation":["Hello, world."]}"#.into(),
        "",
        false,
    );
    let c = youdao_credentials(YOUDAO_SECRET).unwrap();
    let text = "你好，世界。😀";
    assert_eq!(
        youdao_at(
            &client(),
            &c,
            text,
            "zh-CHT",
            "en",
            "fixture-salt",
            "1700000000",
            &url
        )
        .await
        .unwrap(),
        "Hello, world."
    );
    worker.join().unwrap();
    let r = requests.recv().unwrap();
    let f = form(&r.body);
    assert_eq!(f["q"], text);
    assert_eq!(f["signType"], "v3");
    assert_eq!(f["strict"], "true");
    assert_eq!(f["curtime"], "1700000000");
    assert_eq!(f["from"], "zh-CHT");
    assert_eq!(f["to"], "en");
    assert_eq!(
        f["sign"],
        youdao_sign(&c, text, "fixture-salt", "1700000000")
    );
    assert!(!r.body.contains("fixture-secret"));
    assert!(!f.contains_key("voice"));
    assert!(!f.contains_key("ext"));
}

#[tokio::test]
async fn microsoft_real_headers_and_json_preserve_traditional_chinese_and_region() {
    let (url, requests, worker) = fixture(
        200,
        r#"[{"translations":[{"text":"繁體譯文。","to":"zh-Hant"}]}]"#.into(),
        "",
        false,
    );
    let text = "First\n\n- quiet_pin: a_b & 😀";
    assert_eq!(
        microsoft_at(
            &client(),
            &microsoft_credentials(MICROSOFT_SECRET).unwrap(),
            "eastasia",
            text,
            "en",
            "zh-Hant",
            &url
        )
        .await
        .unwrap(),
        "繁體譯文。"
    );
    worker.join().unwrap();
    let r = requests.recv().unwrap();
    let u = Url::parse(&format!("http://fixture.invalid{}", r.path)).unwrap();
    let query: HashMap<_, _> = u
        .query_pairs()
        .map(|(k, v)| (k.into_owned(), v.into_owned()))
        .collect();
    assert_eq!(u.path(), "/translate");
    assert_eq!(query["api-version"], "3.0");
    assert_eq!(query["to"], "zh-Hant");
    assert_eq!(query["from"], "en");
    assert_eq!(query["textType"], "plain");
    assert_eq!(
        r.headers["ocp-apim-subscription-key"],
        "fixture-subscription"
    );
    assert_eq!(r.headers["ocp-apim-subscription-region"], "eastasia");
    assert!(!r.path.contains("fixture-subscription"));
    assert_eq!(
        serde_json::from_str::<Value>(&r.body).unwrap(),
        json!([{"Text":text}])
    );
}

#[tokio::test]
async fn microsoft_global_resource_omits_region_and_auto_source() {
    let (url, requests, worker) = fixture(
        200,
        r#"[{"translations":[{"text":"Hello","to":"en"}]}]"#.into(),
        "",
        false,
    );
    microsoft_at(
        &client(),
        &microsoft_credentials(MICROSOFT_SECRET).unwrap(),
        "",
        "你好",
        "auto",
        "en",
        &url,
    )
    .await
    .unwrap();
    worker.join().unwrap();
    let r = requests.recv().unwrap();
    assert!(!r.path.contains("from="));
    assert!(!r.headers.contains_key("ocp-apim-subscription-region"));
}

#[test]
fn upstream_messages_cannot_leak_secrets_source_or_fake_success() {
    for value in [
        json!({"error_code":"54001","error_msg":"fixture-secret / source-content"}),
        json!({"error_code":54003,"trans_result":[{"dst":"fake"}]}),
        json!({"error_code":"source-content","error_msg":"fixture-secret"}),
    ] {
        let error = parse_baidu(&value, "zh").unwrap_err();
        assert!(!error.contains("fixture-secret") && !error.contains("source-content"));
    }
    for code in ["108", "202", "206", "401", "411", "103", "source-content"] {
        let error = parse_youdao(
            &json!({"errorCode":code,"errorMsg":"fixture-secret","translation":["fake"]}),
        )
        .unwrap_err();
        assert!(!error.contains("fixture-secret") && !error.contains("source-content"));
    }
    for value in [
        json!({"error":{"message":"fixture-secret source-content"}}),
        json!([]),
        json!([{"translations":[{"text":"wrong","to":"zh-Hans"}]}]),
    ] {
        assert!(parse_microsoft(&value, "zh-Hant").is_err());
    }
}

#[test]
fn malformed_empty_rows_wrong_targets_and_status_are_rejected() {
    for v in [
        json!({"to":"zh","trans_result":[]}),
        json!({"to":"zh","trans_result":[{"dst":42}]}),
        json!({"to":"zh","trans_result":[{"dst":"  "}]}),
        json!({"to":"en","trans_result":[{"dst":"fake"}]}),
    ] {
        assert!(parse_baidu(&v, "zh").is_err());
    }
    for v in [
        json!({"translation":["fake"]}),
        json!({"errorCode":0,"translation":["fake"]}),
        json!({"errorCode":"0","translation":[]}),
        json!({"errorCode":"0","translation":[{}]}),
    ] {
        assert!(parse_youdao(&v).is_err());
    }
    assert!(parse_microsoft(&json!([{"translations":[{"text":" ","to":"en"}]}]), "en").is_err());
}

#[tokio::test]
async fn redirects_and_http_errors_do_not_follow_retry_or_echo_bodies() {
    let sink = TcpListener::bind("127.0.0.1:0").unwrap();
    sink.set_nonblocking(true).unwrap();
    for status in [302, 400, 401, 403, 413, 429, 500] {
        let extra = format!(
            "Location: http://{}/credential-sink\r\n",
            sink.local_addr().unwrap()
        );
        let (url, requests, worker) = fixture(
            status,
            "fixture-secret source-content".into(),
            &extra,
            false,
        );
        let error = baidu_at(
            &client(),
            &baidu_credentials(BAIDU_SECRET).unwrap(),
            "synthetic",
            "en",
            "zh",
            "salt",
            &url,
        )
        .await
        .unwrap_err();
        worker.join().unwrap();
        assert!(requests.recv().is_ok());
        assert!(!error.contains("fixture-secret") && !error.contains("source-content"));
        assert_eq!(
            sink.accept().unwrap_err().kind(),
            std::io::ErrorKind::WouldBlock
        );
    }
}

#[tokio::test]
async fn declared_and_chunked_response_limits_are_enforced() {
    for chunked in [false, true] {
        let body = format!(
            r#"{{"errorCode":"0","translation":["{}"]}}"#,
            "x".repeat(MAX_RESPONSE)
        );
        let (url, _, worker) = fixture(200, body, "", chunked);
        let error = youdao_at(
            &client(),
            &youdao_credentials(YOUDAO_SECRET).unwrap(),
            "synthetic",
            "en",
            "zh-CHS",
            "salt",
            "1700000000",
            &url,
        )
        .await
        .unwrap_err();
        assert!(error.contains("2 MiB"));
        worker.join().unwrap();
    }
}

#[tokio::test]
async fn production_wrapper_rejects_wrong_origin_and_bad_credentials_without_http() {
    let mut p = provider("baidu");
    p.base_url = "http://127.0.0.1:9/".into();
    let result = super::super::translate_one(
        &client(),
        &p,
        Ok(BAIDU_SECRET.into()),
        "synthetic",
        "en",
        "zh-Hans",
    )
    .await;
    assert!(result.error.is_some());
    assert!(result.text.is_empty());
    assert_eq!(result.provider_id, p.id);
    let result = super::super::translate_one(
        &client(),
        &provider("youdao"),
        Ok("not-json-dummy".into()),
        "synthetic",
        "en",
        "zh-Hans",
    )
    .await;
    assert!(result.error.unwrap().contains("appKey"));
    assert!(result.text.is_empty());
}

#[tokio::test]
async fn dropping_in_flight_native_translation_closes_http_without_late_result() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let url = format!("http://{}/", listener.local_addr().unwrap());
    let (started, observed) = tokio::sync::oneshot::channel();
    let worker = thread::spawn(move || {
        let deadline = Instant::now() + Duration::from_secs(3);
        let mut stream = loop {
            match listener.accept() {
                Ok((s, _)) => break s,
                Err(e)
                    if e.kind() == std::io::ErrorKind::WouldBlock && Instant::now() < deadline =>
                {
                    thread::sleep(Duration::from_millis(2))
                }
                Err(e) => panic!("request missing: {e}"),
            }
        };
        read_request(&mut stream);
        stream.write_all(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Type: application/json\r\n\r\n1\r\n{\r\n").unwrap();
        stream.flush().unwrap();
        started.send(()).unwrap();
        let mut one = [0; 1];
        let closed = match stream.read(&mut one) {
            Ok(0) => true,
            Err(e)
                if matches!(
                    e.kind(),
                    std::io::ErrorKind::ConnectionReset | std::io::ErrorKind::ConnectionAborted
                ) =>
            {
                true
            }
            _ => false,
        };
        assert!(closed, "cancelled caller must close pending HTTP");
        assert_eq!(
            listener.accept().unwrap_err().kind(),
            std::io::ErrorKind::WouldBlock
        );
    });
    let client = client();
    let c = baidu_credentials(BAIDU_SECRET).unwrap();
    let request =
        tokio::spawn(
            async move { baidu_at(&client, &c, "synthetic", "en", "zh", "salt", &url).await },
        );
    tokio::time::timeout(Duration::from_secs(3), observed)
        .await
        .unwrap()
        .unwrap();
    request.abort();
    assert!(request.await.unwrap_err().is_cancelled());
    worker.join().unwrap();
}
