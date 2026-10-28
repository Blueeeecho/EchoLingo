//! Real HTTP to loopback only; synthetic Base64 and dummy account strings.
use super::*;
use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::mpsc;
use std::thread;
use std::time::Instant;

const IMAGE: &str = "aGVsbG8=";
const LONG_IMAGE: &str = "aGVsbG8gd29ybGQgc3ludGhldGljIG9jciBmaXh0dXJlLg==";
const SECRET: &str = r#"{"appKey":"fixture-app","appSecret":"fixture-secret"}"#;
const GOOGLE_KEY: &str = "fixture-google-key";

fn client() -> Client {
    Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .no_proxy()
        .build()
        .unwrap()
}
fn provider(kind: &str) -> OcrProvider {
    serde_json::from_value(json!({"id":"additional-ocr-fixture","name":"Fixture","kind":kind,"baseUrl":if kind=="youdao" {YOUDAO_ENDPOINT} else {GOOGLE_ENDPOINT},"model":if kind=="youdao" {"general"} else {"DOCUMENT_TEXT_DETECTION"}})).unwrap()
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
        if let Some(i) = bytes.windows(4).position(|w| w == b"\r\n\r\n") {
            break i + 4;
        }
        assert!(bytes.len() < 65536);
    };
    let head = String::from_utf8(bytes[..end].to_vec()).unwrap();
    let mut lines = head.lines();
    let first = lines.next().unwrap();
    assert!(first.starts_with("POST "));
    let path = first.split_whitespace().nth(1).unwrap().into();
    let headers: HashMap<String, String> = lines
        .filter_map(|l| {
            l.split_once(':')
                .map(|(k, v)| (k.to_ascii_lowercase(), v.trim().into()))
        })
        .collect();
    let length: usize = headers.get("content-length").unwrap().parse().unwrap();
    assert!(length < 65536);
    while bytes.len() < end + length {
        let mut chunk = [0; 4096];
        let n = stream.read(&mut chunk).unwrap();
        assert!(n > 0);
        bytes.extend_from_slice(&chunk[..n]);
    }
    Request {
        path,
        headers,
        body: String::from_utf8(bytes[end..end + length].to_vec()).unwrap(),
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
    let url = format!("http://{}/", listener.local_addr().unwrap());
    let (tx, rx) = mpsc::channel();
    let extra = extra.to_owned();
    let worker = thread::spawn(move || {
        let end = Instant::now() + Duration::from_secs(4);
        let mut stream = loop {
            match listener.accept() {
                Ok((s, _)) => break s,
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock && Instant::now() < end => {
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
            for part in body.as_bytes().chunks(16384) {
                if write!(stream, "{:x}\r\n", part.len())
                    .and_then(|_| stream.write_all(part))
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
        let end = Instant::now() + Duration::from_millis(50);
        while Instant::now() < end {
            assert_eq!(
                listener.accept().unwrap_err().kind(),
                std::io::ErrorKind::WouldBlock,
                "unexpected automatic OCR retry"
            );
            thread::sleep(Duration::from_millis(2));
        }
    });
    (url, rx, worker)
}
fn form(body: &str) -> HashMap<String, String> {
    Url::parse(&format!("http://fixture.invalid/?{body}"))
        .unwrap()
        .query_pairs()
        .map(|(k, v)| (k.into_owned(), v.into_owned()))
        .collect()
}

#[test]
fn unified_native_classification_preserves_local_default_and_old_kinds() {
    for kind in ["baidu", "tencent", "youdao", "google"] {
        assert!(super::super::is_native(kind));
    }
    for kind in ["local", "openai-vision", "http-json", "unknown"] {
        assert!(!super::super::is_native(kind));
    }
    let defaults = crate::model::Settings::default();
    assert!(defaults.ocr_providers.is_empty());
    assert!(defaults.active_ocr_provider_id.is_none());
    for kind in ["youdao", "google"] {
        assert!(crate::ocr::validate_provider(&provider(kind)).is_ok());
    }
}

#[test]
fn endpoints_features_and_empty_region_are_verified_independent_of_generic_auth() {
    for kind in ["youdao", "google"] {
        let mut p = provider(kind);
        assert_eq!(p.auth_header, "Authorization");
        assert_eq!(p.auth_prefix, "Bearer ");
        assert!(validate_provider(&p).is_ok());
        for url in [
            "http://127.0.0.1:9/",
            "https://openapi.youdao.com.evil.invalid/ocrapi",
            "https://vision.googleapis.com@evil.invalid/v1/images:annotate",
            "https://vision.googleapis.com:8443/v1/images:annotate",
            "https://vision.googleapis.com/v1/images:annotate?key=dummy",
            "https://openapi.youdao.com/api",
            "https://vision.googleapis.com/v1/images:annotate#x",
        ] {
            p.base_url = url.into();
            assert!(validate_provider(&p).is_err(), "{kind} {url}");
        }
        p = provider(kind);
        p.region = "region".into();
        assert!(validate_provider(&p).is_err());
        p = provider(kind);
        p.model = "FACE_DETECTION".into();
        assert!(validate_provider(&p).is_err());
    }
    let mut p = provider("google");
    for feature in ["", "DOCUMENT_TEXT_DETECTION", "TEXT_DETECTION"] {
        p.model = feature.into();
        assert!(validate_provider(&p).is_ok());
    }
}

#[test]
fn credential_schemas_reject_mixed_protocol_and_injected_fields() {
    assert!(super::super::validate_credentials("youdao", SECRET).is_ok());
    assert!(super::super::validate_credentials("google", GOOGLE_KEY).is_ok());
    for secret in [
        "",
        GOOGLE_KEY,
        r#"{"appKey":"fixture-app"}"#,
        r#"{"appKey":"fixture-app","appSecret":"dummy","extra":"dummy"}"#,
        r#"{"appKey":"fixture-app","appSecret":"dummy\n"}"#,
    ] {
        assert!(validate_credentials("youdao", secret).is_err());
    }
    for secret in [
        "",
        "Bearer dummy",
        r#"{"apiKey":"dummy"}"#,
        "dummy\r\nHeader:value",
        &"x".repeat(257),
    ] {
        assert!(validate_credentials("google", secret).is_err());
    }
}

#[test]
fn youdao_v3_signs_canonical_base64_not_form_encoded_bytes() {
    let c = youdao_credentials(SECRET).unwrap();
    // Independent Python hashlib calculation; synthetic app/secret/input.
    assert_eq!(
        youdao_sign(&c, LONG_IMAGE, "fixture-salt", "1700000000"),
        "42ebbbb2407fb1db029c1722b26d155fdaf07dd4d69a403a67f973897e9cc905"
    );
    let raw = "+/8=";
    let encoded = "%2B%2F8%3D";
    assert_ne!(
        youdao_sign(&c, raw, "salt", "1"),
        youdao_sign(&c, encoded, "salt", "1")
    );
}

#[test]
fn exact_encoded_form_counts_escape_expansion_and_whole_request() {
    let c = youdao_credentials(SECRET).unwrap();
    let body = youdao_form(&c, "+/8=", "salt", "1700000000").unwrap();
    assert!(body.contains("img=%2B%2F8%3D"));
    assert_eq!(form(&body)["img"], "+/8=");
    // All A's do not expand, whereas + and / require three encoded bytes.
    assert!(youdao_form(&c, &"A".repeat(3_999_000), "salt", "1700000000").is_ok());
    assert!(youdao_form(&c, &"A".repeat(4_000_000), "salt", "1700000000").is_err());
    assert!(youdao_form(&c, &"+/8=".repeat(500_000), "salt", "1700000000").is_err());
}

#[tokio::test]
async fn invalid_base64_is_rejected_by_the_public_native_route_before_network() {
    for (kind, key) in [("youdao", SECRET), ("google", GOOGLE_KEY)] {
        for image in [
            "",
            "data:image/png;base64,AAAA",
            "AB==",
            "AA=A",
            "A===",
            "AA!A",
            "AAA\n",
        ] {
            let error = crate::ocr::recognize(&client(), &provider(kind), Ok(key.into()), image)
                .await
                .unwrap_err();
            assert!(error.contains("图片") || error.contains("Base64"));
        }
    }
}

#[test]
fn youdao_paragraphs_keep_line_text_and_skip_only_empty_regions() {
    let response = json!({"errorCode":"0","Result":{"regions":[{"lines":[{"text":"第一行 - quiet_pin:"},{"text":"第二行 _/+"}]},{"lines":[]},{"lines":[{"text":"Third paragraph."}]}]}});
    assert_eq!(
        parse_youdao(&response).unwrap(),
        "第一行 - quiet_pin:\n第二行 _/+\n\nThird paragraph."
    );
}

#[test]
fn youdao_nonzero_missing_status_malformed_and_empty_results_are_errors() {
    for status in [
        "108",
        "110",
        "202",
        "206",
        "401",
        "1411",
        "1004",
        "source-content",
    ] {
        let error=parse_youdao(&json!({"errorCode":status,"errorMsg":"fixture-secret image-content","Result":{"regions":[{"lines":[{"text":"must-not-pass"}]}]}})).unwrap_err();
        assert!(
            !error.contains("fixture-secret")
                && !error.contains("image-content")
                && !error.contains("source-content")
        );
    }
    for response in [
        json!({"Result":{}}),
        json!({"errorCode":0}),
        json!({"errorCode":"0","Result":{"regions":[]}}),
        json!({"errorCode":"0","Result":{"regions":[{"lines":[{"text":42}]}]}}),
        json!({"errorCode":"0","Result":{"regions":[{"lines":[{"text":"  "}]}]}}),
    ] {
        assert!(parse_youdao(&response).is_err());
    }
}

#[test]
fn google_prefers_full_text_then_uses_only_aggregate_first_annotation() {
    assert_eq!(parse_google(&json!({"responses":[{"fullTextAnnotation":{"text":"Full\n\nText"},"textAnnotations":[{"description":"other"},{"description":"duplicate-word"}]}]})).unwrap(),"Full\n\nText");
    assert_eq!(parse_google(&json!({"responses":[{"textAnnotations":[{"description":"Aggregate\nText"},{"description":"word-not-appended"}]}]})).unwrap(),"Aggregate\nText");
    assert_eq!(parse_google(&json!({"responses":[{"fullTextAnnotation":{"text":""},"textAnnotations":[{"description":"Fallback"}]}]})).unwrap(),"Fallback");
}

#[test]
fn google_never_accepts_partial_text_with_an_error_or_arbitrary_annotations() {
    for code in [3, 7, 8, 16, 400, 403, 429, 500] {
        let error = json!({"code":code,"message":"fixture-google-key image-content","details":["source-content"]});
        for value in [
            json!({"error":error,"responses":[{"fullTextAnnotation":{"text":"partial"}}]}),
            json!({"responses":[{"error":error,"fullTextAnnotation":{"text":"partial"}}]}),
        ] {
            let result = parse_google(&value).unwrap_err();
            assert!(
                !result.contains("fixture-google-key")
                    && !result.contains("image-content")
                    && !result.contains("source-content")
            );
        }
    }
    for value in [
        json!({"responses":[]}),
        json!({"responses":[{},{}]}),
        json!({"responses":[{"labelAnnotations":[{"description":"never OCR"}]}]}),
        json!({"responses":[{"fullTextAnnotation":{"text":" "}}]}),
        json!({"responses":[{"fullTextAnnotation":{"text":42}}]}),
    ] {
        assert!(parse_google(&value).is_err());
    }
}

#[tokio::test]
async fn actual_youdao_form_uses_the_official_fields_and_no_generic_auth() {
    let (url,requests,worker)=fixture(200,r#"{"errorCode":"0","Result":{"regions":[{"lines":[{"text":"你好"},{"text":"- quiet_pin:"}]},{"lines":[{"text":"Paragraph 2"}]}]}}"#.into(),"",false);
    let c = youdao_credentials(SECRET).unwrap();
    let output = youdao_at(&client(), &c, "+/8=", "fixture-salt", "1700000000", &url)
        .await
        .unwrap();
    worker.join().unwrap();
    assert_eq!(output, "你好\n- quiet_pin:\n\nParagraph 2");
    let request = requests.recv().unwrap();
    let f = form(&request.body);
    assert_eq!(request.path, "/");
    assert_eq!(f.len(), 10);
    for (k, v) in [
        ("img", "+/8="),
        ("langType", "auto"),
        ("detectType", "10012"),
        ("imageType", "1"),
        ("docType", "json"),
        ("signType", "v3"),
        ("appKey", "fixture-app"),
        ("salt", "fixture-salt"),
        ("curtime", "1700000000"),
    ] {
        assert_eq!(f[k], v);
    }
    assert_eq!(
        f["sign"],
        youdao_sign(&c, "+/8=", "fixture-salt", "1700000000")
    );
    assert!(!request.body.contains("fixture-secret"));
    assert!(!request.headers.contains_key("authorization"));
    assert!(request.headers["content-type"].starts_with("application/x-www-form-urlencoded"));
}

#[tokio::test]
async fn actual_google_json_and_key_header_are_not_query_bearer_or_remote_urls() {
    for feature in ["", "DOCUMENT_TEXT_DETECTION", "TEXT_DETECTION"] {
        let (url, requests, worker) = fixture(
            200,
            r#"{"responses":[{"fullTextAnnotation":{"text":"Synthetic OCR\n中文"}}]}"#.into(),
            "",
            false,
        );
        assert_eq!(
            google_at(&client(), GOOGLE_KEY, IMAGE, feature, &url)
                .await
                .unwrap(),
            "Synthetic OCR\n中文"
        );
        worker.join().unwrap();
        let request = requests.recv().unwrap();
        assert_eq!(request.path, "/");
        assert_eq!(request.headers["x-goog-api-key"], GOOGLE_KEY);
        assert!(!request.headers.contains_key("authorization"));
        assert!(!request.path.contains(GOOGLE_KEY));
        assert!(!request.body.contains(GOOGLE_KEY));
        let expected = if feature.is_empty() {
            "DOCUMENT_TEXT_DETECTION"
        } else {
            feature
        };
        assert_eq!(
            serde_json::from_str::<Value>(&request.body).unwrap(),
            json!({"requests":[{"image":{"content":IMAGE},"features":[{"type":expected}]}]})
        );
    }
}

#[tokio::test]
async fn http_errors_and_redirects_are_not_followed_retried_or_echoed() {
    let sink = TcpListener::bind("127.0.0.1:0").unwrap();
    sink.set_nonblocking(true).unwrap();
    for status in [302, 307, 400, 401, 403, 413, 429, 500] {
        let extra = format!(
            "Location: http://{}/key-sink\r\n",
            sink.local_addr().unwrap()
        );
        let (url, _, worker) = fixture(
            status,
            "fixture-google-key image-content".into(),
            &extra,
            false,
        );
        let error = google_at(&client(), GOOGLE_KEY, IMAGE, "TEXT_DETECTION", &url)
            .await
            .unwrap_err();
        worker.join().unwrap();
        assert!(!error.contains("fixture-google-key") && !error.contains("image-content"));
        assert_eq!(
            sink.accept().unwrap_err().kind(),
            std::io::ErrorKind::WouldBlock
        );
    }
}

#[tokio::test]
async fn google_whole_json_size_includes_inline_image_and_protocol_overhead() {
    let error = google_at(
        &client(),
        GOOGLE_KEY,
        &"A".repeat(10_000_000),
        "TEXT_DETECTION",
        "http://127.0.0.1:9/",
    )
    .await
    .unwrap_err();
    assert!(error.contains("10 MB"));
}

#[tokio::test]
async fn declared_and_streamed_response_size_limits_cover_both_new_protocols() {
    for chunked in [false, true] {
        let body = format!(
            r#"{{"responses":[{{"fullTextAnnotation":{{"text":"{}"}}}}]}}"#,
            "x".repeat(super::super::MAX_RESPONSE)
        );
        let (url, _, worker) = fixture(200, body, "", chunked);
        let error = google_at(&client(), GOOGLE_KEY, IMAGE, "TEXT_DETECTION", &url)
            .await
            .unwrap_err();
        worker.join().unwrap();
        assert!(error.contains("上限"));
        let body = format!(
            r#"{{"errorCode":"0","Result":{{"regions":[{{"lines":[{{"text":"{}"}}]}}]}}}}"#,
            "x".repeat(super::super::MAX_RESPONSE)
        );
        let (url, _, worker) = fixture(200, body, "", chunked);
        let error = youdao_at(
            &client(),
            &youdao_credentials(SECRET).unwrap(),
            IMAGE,
            "salt",
            "1700000000",
            &url,
        )
        .await
        .unwrap_err();
        worker.join().unwrap();
        assert!(error.contains("上限"));
    }
}

#[tokio::test]
async fn cancelling_each_new_protocol_closes_pending_http_and_never_retries() {
    for google in [false, true] {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let url = format!("http://{}/", listener.local_addr().unwrap());
        let (started, observed) = tokio::sync::oneshot::channel();
        let worker = thread::spawn(move || {
            let end = Instant::now() + Duration::from_secs(3);
            let mut stream = loop {
                match listener.accept() {
                    Ok((s, _)) => break s,
                    Err(e)
                        if e.kind() == std::io::ErrorKind::WouldBlock && Instant::now() < end =>
                    {
                        thread::sleep(Duration::from_millis(2))
                    }
                    Err(e) => panic!("fixture request missing: {e}"),
                }
            };
            read_request(&mut stream);
            stream.write_all(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n1\r\n{\r\n").unwrap();
            stream.flush().unwrap();
            started.send(()).unwrap();
            let mut byte = [0; 1];
            assert!(match stream.read(&mut byte) {
                Ok(0) => true,
                Err(e)
                    if matches!(
                        e.kind(),
                        std::io::ErrorKind::ConnectionReset | std::io::ErrorKind::ConnectionAborted
                    ) =>
                    true,
                _ => false,
            });
            assert_eq!(
                listener.accept().unwrap_err().kind(),
                std::io::ErrorKind::WouldBlock
            );
        });
        let request = tokio::spawn(async move {
            if google {
                google_at(&client(), GOOGLE_KEY, IMAGE, "TEXT_DETECTION", &url).await
            } else {
                youdao_at(
                    &client(),
                    &youdao_credentials(SECRET).unwrap(),
                    IMAGE,
                    "salt",
                    "1700000000",
                    &url,
                )
                .await
            }
        });
        tokio::time::timeout(Duration::from_secs(3), observed)
            .await
            .unwrap()
            .unwrap();
        request.abort();
        assert!(request.await.unwrap_err().is_cancelled());
        worker.join().unwrap();
    }
}
