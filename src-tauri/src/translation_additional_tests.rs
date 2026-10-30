//! Synthetic protocol fixtures only; no live account, credentials or quota use.
use super::*;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::mpsc;
use std::time::Duration;

fn client() -> Client {
    Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .no_proxy()
        .build()
        .unwrap()
}
fn server(
    status: u16,
    body: String,
) -> (String, mpsc::Receiver<String>, std::thread::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/translate", listener.local_addr().unwrap());
    let (send, receive) = mpsc::channel();
    let task = std::thread::spawn(move || {
        let (mut socket, _) = listener.accept().unwrap();
        socket
            .set_read_timeout(Some(Duration::from_secs(3)))
            .unwrap();
        socket
            .set_write_timeout(Some(Duration::from_secs(3)))
            .unwrap();
        let mut data = Vec::new();
        loop {
            let mut buffer = [0; 4096];
            let count = socket.read(&mut buffer).unwrap();
            if count == 0 {
                break;
            }
            data.extend_from_slice(&buffer[..count]);
            if let Some(offset) = data.windows(4).position(|v| v == b"\r\n\r\n") {
                let head = String::from_utf8_lossy(&data[..offset]).to_ascii_lowercase();
                let length: usize = head
                    .lines()
                    .find_map(|line| {
                        line.strip_prefix("content-length:")
                            .and_then(|n| n.trim().parse().ok())
                    })
                    .unwrap_or(0);
                if data.len() >= offset + 4 + length {
                    break;
                }
            }
        }
        send.send(String::from_utf8(data).unwrap()).unwrap();
        let reply = format!("HTTP/1.1 {status} Fixture\r\nContent-Type: application/json\r\nContent-Length: {}\r\nLocation: http://127.0.0.1:1/forbidden\r\nConnection: close\r\n\r\n{body}", body.len());
        let _ = socket.write_all(reply.as_bytes());
    });
    (url, receive, task)
}
fn body(request: &str) -> Value {
    serde_json::from_str(request.split_once("\r\n\r\n").unwrap().1).unwrap()
}

#[tokio::test]
async fn niu_posts_form_key_and_source_without_query_secrets() {
    let (url, got, task) = server(200, json!({"to":"en","tgt_text":"Hello"}).to_string());
    assert_eq!(
        request_at(
            &client(),
            "niutrans",
            "FIXTURE-KEY",
            "你好 + &",
            "auto",
            "en",
            &url
        )
        .await
        .unwrap(),
        "Hello"
    );
    let request = got.recv().unwrap();
    tokio::task::spawn_blocking(move || task.join().unwrap())
        .await
        .unwrap();
    assert!(request.starts_with("POST /translate HTTP/1.1"));
    let form = reqwest::Url::parse(&format!(
        "http://fixture/?{}",
        request.split_once("\r\n\r\n").unwrap().1
    ))
    .unwrap();
    let values: std::collections::HashMap<_, _> = form.query_pairs().into_owned().collect();
    assert_eq!(values["apikey"], "FIXTURE-KEY");
    assert_eq!(values["src_text"], "你好 + &");
    assert_eq!(values["from"], "auto");
    assert_eq!(values["to"], "en");
}

#[tokio::test]
async fn google_uses_header_key_plain_nmt_and_omits_auto_source() {
    for source in ["auto", "en"] {
        let (url, got, task) = server(
            200,
            json!({"data":{"translations":[{"translatedText":"你好"}]}}).to_string(),
        );
        assert_eq!(
            request_at(
                &client(),
                "google-translate",
                "FIXTURE-KEY",
                "Hello",
                source,
                "zh-CN",
                &url
            )
            .await
            .unwrap(),
            "你好"
        );
        let request = got.recv().unwrap();
        tokio::task::spawn_blocking(move || task.join().unwrap())
            .await
            .unwrap();
        assert!(request.starts_with("POST /translate HTTP/1.1"));
        assert!(request
            .to_ascii_lowercase()
            .contains("x-goog-api-key: fixture-key"));
        let payload = body(&request);
        assert_eq!(payload["format"], "text");
        assert_eq!(payload["model"], "nmt");
        assert_eq!(payload["q"], json!(["Hello"]));
        assert_eq!(
            payload.get("source").and_then(Value::as_str),
            if source == "auto" { None } else { Some("en") }
        );
        assert!(!payload.to_string().contains("FIXTURE-KEY"));
    }
}

#[tokio::test]
async fn caiyun_sends_own_token_and_one_text_with_auto_detection() {
    let (url, got, task) = server(200, json!({"target":["你好"]}).to_string());
    assert_eq!(
        request_at(
            &client(),
            "caiyun",
            "FIXTURE-KEY",
            "Hello",
            "auto",
            "zh",
            &url
        )
        .await
        .unwrap(),
        "你好"
    );
    let request = got.recv().unwrap();
    tokio::task::spawn_blocking(move || task.join().unwrap())
        .await
        .unwrap();
    assert!(request
        .to_ascii_lowercase()
        .contains("x-authorization: token fixture-key"));
    assert_eq!(
        body(&request),
        json!({"source":["Hello"],"trans_type":"auto2zh","detect":true,"media":"text"})
    );
}

#[test]
fn parsers_reject_malformed_empty_counts_and_never_echo_errors() {
    for value in [
        json!({}),
        json!({"tgt_text":""}),
        json!({"tgt_text":42}),
        json!({"tgt_text":"wrong","to":"ja"}),
    ] {
        assert!(parse_niu(&value, "en").is_err());
    }
    for value in [
        json!({}),
        json!({"data":{"translations":[]}}),
        json!({"data":{"translations":[{"translatedText":"a"},{"translatedText":"b"}]}}),
    ] {
        assert!(parse_google(&value).is_err());
    }
    for value in [
        json!({}),
        json!({"target":[]}),
        json!({"target":["a","b"]}),
        json!({"target":42}),
        json!({"target":" "}),
        json!({"target":"bad","rc":1}),
    ] {
        assert!(parse_caiyun(&value).is_err());
    }
    assert_eq!(
        parse_caiyun(&json!({"target":"你好","rc":0})).unwrap(),
        "你好"
    );
    for code in [
        "13001", "13002", "10001", "10003", "13007", "13008", "unknown",
    ] {
        let message = parse_niu(
            &json!({"error_code":code,"error_msg":"SECRET-SOURCE","apikey":"SECRET-KEY"}),
            "en",
        )
        .unwrap_err();
        assert!(!message.contains("SECRET"));
    }
    assert!(!parse_google(&json!({"error":{"message":"SECRET"}}))
        .unwrap_err()
        .contains("SECRET"));
    assert!(!parse_caiyun(&json!({"rc":1,"error":"SECRET"}))
        .unwrap_err()
        .contains("SECRET"));
}

#[test]
fn language_matrix_and_keys_are_conservative() {
    for pair in [("en", "ja"), ("de", "en"), ("zh", "ru"), ("auto", "ru")] {
        assert!(caiyun_direction(pair.0, pair.1).is_err());
    }
    for pair in [
        ("auto", "zh"),
        ("zh", "en"),
        ("en", "zh-Hant"),
        ("zh-Hant", "zh"),
    ] {
        assert!(caiyun_direction(pair.0, pair.1).is_ok());
    }
    for key in ["", "with space", "newline\nkey", "中文"] {
        assert!(validate_key(key).is_err());
    }
}

#[tokio::test]
async fn http_errors_redirects_and_invalid_json_stay_sanitized() {
    for kind in ["niutrans", "google-translate", "caiyun"] {
        for status in [302, 400, 401, 403, 429, 500, 200] {
            let (url, _got, task) = server(status, "SECRET-KEY AND PRIVATE SOURCE".into());
            let error = request_at(&client(), kind, "FIXTURE-KEY", "test", "auto", "en", &url)
                .await
                .unwrap_err();
            assert!(!error.contains("SECRET"));
            if kind == "google-translate" && status == 403 {
                assert!(error.contains("额度"));
            }
            tokio::task::spawn_blocking(move || task.join().unwrap())
                .await
                .unwrap();
        }
    }
}

#[tokio::test]
async fn bounded_response_and_dropped_future_do_not_retry() {
    let (url, _got, task) = server(200, "x".repeat(super::super::MAX_RESPONSE + 1));
    assert!(request_at(
        &client(),
        "google-translate",
        "FIXTURE",
        "test",
        "auto",
        "en",
        &url
    )
    .await
    .unwrap_err()
    .contains("上限"));
    tokio::task::spawn_blocking(move || task.join().unwrap())
        .await
        .unwrap();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}/translate", listener.local_addr().unwrap());
    let c = client();
    let mut pending = Box::pin(request_at(
        &c,
        "google-translate",
        "FIXTURE",
        "test",
        "auto",
        "en",
        &url,
    ));
    tokio::select! {
        _ = &mut pending => panic!("server has not replied"),
        accepted = listener.accept() => {assert!(accepted.is_ok());}
    }
    // No detached tasks: dropping the future cancels the in-flight request.
    drop(pending);
    assert!(
        tokio::time::timeout(Duration::from_millis(30), listener.accept())
            .await
            .is_err()
    );
}

#[test]
fn new_adapters_pin_endpoints_languages_lengths_and_credentials() {
    use super::super::{
        endpoint, language, validate_credentials, validate_provider, validate_text,
    };
    for (kind, url) in [
        ("niutrans", NIU_ENDPOINT),
        ("google-translate", GOOGLE_ENDPOINT),
        ("caiyun", CAIYUN_ENDPOINT),
    ] {
        let mut p: crate::model::Provider=serde_json::from_value(json!({"id":"fixture","name":"Fixture","kind":kind,"baseUrl":url,"model":"","prompt":"","enabled":false})).unwrap();
        assert_eq!(endpoint(&p).unwrap(), url);
        assert!(validate_provider(&p).is_ok());
        assert!(validate_credentials(kind, "FIXTURE-KEY").is_ok());
        assert!(validate_credentials(kind, "").is_err());
        for bad in [
            url.replace("https:", "http:"),
            format!("{url}?apikey=secret"),
            url.replace(".com/", ".com.attacker.invalid/"),
            format!("{url}/other"),
            "https://localhost/".into(),
        ] {
            p.base_url = bad;
            assert!(endpoint(&p).is_err());
        }
        assert!(validate_text(kind, "").is_err());
        assert!(validate_text(kind, &"x".repeat(5001)).is_err());
    }
    assert_eq!(
        language("google-translate", "zh-Hans", false).unwrap(),
        "zh-CN"
    );
    assert_eq!(
        language("google-translate", "zh-Hant", false).unwrap(),
        "zh-TW"
    );
    assert_eq!(language("niutrans", "zh-Hans", false).unwrap(), "zh");
    assert!(language("niutrans", "zh-Hant", false).is_err());
    assert!(language("caiyun", "auto", false).is_err());
}
