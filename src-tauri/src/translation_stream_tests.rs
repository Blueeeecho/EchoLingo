//! Real loopback HTTP fixtures; synthetic text and dummy credentials only.
use super::*;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::{mpsc, Arc, Mutex};

struct Fixture {
    url: String,
    release: mpsc::Sender<()>,
    worker: std::thread::JoinHandle<Value>,
}

fn frame(text: &str, finish: Option<&str>) -> Vec<u8> {
    format!(
        "data: {}\n\n",
        json!({"choices":[{"index":0,"delta":{"content":text},"finish_reason":finish}]})
    )
    .into_bytes()
}

fn fixture(chunks: Vec<Vec<u8>>, gated: bool, status: &str, content_type: &str) -> Fixture {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let url = format!("http://{}/v1", listener.local_addr().unwrap());
    let (release, gate) = mpsc::channel();
    let status = status.to_owned();
    let content_type = content_type.to_owned();
    let worker = std::thread::spawn(move || {
        let deadline = Instant::now() + Duration::from_secs(5);
        let mut socket = loop {
            match listener.accept() {
                Ok((socket, _)) => break socket,
                Err(e)
                    if e.kind() == std::io::ErrorKind::WouldBlock && Instant::now() < deadline =>
                {
                    std::thread::sleep(Duration::from_millis(2));
                }
                Err(e) => panic!("fixture request missing: {e}"),
            }
        };
        socket.set_nonblocking(false).unwrap();
        socket
            .set_read_timeout(Some(Duration::from_secs(3)))
            .unwrap();
        socket
            .set_write_timeout(Some(Duration::from_secs(3)))
            .unwrap();
        let mut bytes = Vec::new();
        let header_end = loop {
            let mut buffer = [0_u8; 4096];
            let count = socket.read(&mut buffer).unwrap();
            assert!(count > 0);
            bytes.extend_from_slice(&buffer[..count]);
            assert!(bytes.len() < 65536);
            if let Some(index) = bytes.windows(4).position(|part| part == b"\r\n\r\n") {
                break index + 4;
            }
        };
        let headers = std::str::from_utf8(&bytes[..header_end]).unwrap();
        assert!(headers.starts_with("POST /v1/chat/completions "));
        assert!(headers
            .to_ascii_lowercase()
            .contains("authorization: bearer fixture-only"));
        let length: usize = headers
            .lines()
            .find_map(|line| {
                let (key, value) = line.split_once(':')?;
                key.eq_ignore_ascii_case("content-length")
                    .then(|| value.trim().parse().unwrap())
            })
            .unwrap();
        while bytes.len() < header_end + length {
            let mut buffer = [0_u8; 4096];
            let count = socket.read(&mut buffer).unwrap();
            assert!(count > 0);
            bytes.extend_from_slice(&buffer[..count]);
        }
        let request: Value =
            serde_json::from_slice(&bytes[header_end..header_end + length]).unwrap();
        write!(socket, "HTTP/1.1 {status}\r\nContent-Type: {content_type}\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n").unwrap();
        for (index, chunk) in chunks.iter().enumerate() {
            let sent = write!(socket, "{:x}\r\n", chunk.len())
                .and_then(|_| socket.write_all(chunk))
                .and_then(|_| socket.write_all(b"\r\n"))
                .and_then(|_| socket.flush());
            if sent.is_err() {
                break;
            } // Cancellation intentionally closes it.
            if gated && index == 0 {
                gate.recv_timeout(Duration::from_secs(3)).unwrap();
            }
        }
        let _ = socket.write_all(b"0\r\n\r\n");
        drop(socket);
        // Observe the live listener long enough to catch a hidden retry, even
        // when the previous response was an HTTP or streaming protocol error.
        let retry_deadline = Instant::now() + Duration::from_millis(80);
        while Instant::now() < retry_deadline {
            assert_eq!(
                listener.accept().unwrap_err().kind(),
                std::io::ErrorKind::WouldBlock
            );
            std::thread::sleep(Duration::from_millis(2));
        }
        request
    });
    Fixture {
        url,
        release,
        worker,
    }
}

fn provider(url: &str) -> Provider {
    let mut provider = crate::model::Settings::default()
        .providers
        .into_iter()
        .find(|provider| provider.kind == "openai")
        .unwrap();
    provider.base_url = url.into();
    provider
}

fn client() -> reqwest::Client {
    reqwest::Client::builder()
        .timeout(Duration::from_secs(5))
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .unwrap()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn streaming_http_publishes_before_completion_and_preserves_unicode() {
    let mut first =
        b"data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"PRIVATE-REASONING\"}}]}\n\n"
            .to_vec();
    first.extend(frame("第一段 🪞", None));
    let mut tail = frame("\n\n第二段。", Some("stop"));
    tail.extend_from_slice(b"data: [DONE]\n\n");
    let server = fixture(vec![first, tail], true, "200 OK", "text/event-stream");
    let updates = Arc::new(Mutex::new(Vec::new()));
    let callback_updates = updates.clone();
    let notify = Arc::new(tokio::sync::Notify::new());
    let callback_notify = notify.clone();
    let p = provider(&server.url);
    let task = tokio::spawn(async move {
        translate_one_streaming(
            &client(),
            &p,
            Ok("fixture-only".into()),
            "synthetic source",
            "en",
            "zh-Hans",
            move |text| {
                callback_updates.lock().unwrap().push(text.to_owned());
                callback_notify.notify_one();
            },
        )
        .await
    });
    tokio::time::timeout(Duration::from_secs(3), notify.notified())
        .await
        .unwrap();
    assert!(
        !task.is_finished(),
        "first answer must be visible while the server is still waiting"
    );
    assert_eq!(*updates.lock().unwrap(), ["第一段 🪞"]);
    server.release.send(()).unwrap();
    let result = task.await.unwrap();
    assert_eq!(result.text, "第一段 🪞\n\n第二段。");
    assert!(result.error.is_none());
    assert!(updates
        .lock()
        .unwrap()
        .iter()
        .all(|text| !text.contains("REASONING")));
    let request = server.worker.join().unwrap();
    assert_eq!(request["stream"], true);
    assert_eq!(request["messages"][1]["content"], "synthetic source");
    assert!(request.get("reasoning_split").is_none());
}

#[tokio::test]
async fn streaming_http_accepts_a_natural_json_response_without_resending() {
    let body = json!({"choices":[{"finish_reason":"stop","message":{
        "content":"literal <think>translated XML</think>","reasoning_content":"PRIVATE-REASONING"
    }}]})
    .to_string()
    .into_bytes();
    let server = fixture(
        body.chunks(3).map(<[u8]>::to_vec).collect(),
        false,
        "200 OK",
        "application/json",
    );
    let result = translate_one_streaming(
        &client(),
        &provider(&server.url),
        Ok("fixture-only".into()),
        "fixture",
        "en",
        "zh-Hans",
        |_| {},
    )
    .await;
    assert_eq!(result.text, "literal <think>translated XML</think>");
    assert!(result.error.is_none());
    assert_eq!(server.worker.join().unwrap()["stream"], true);
}

#[tokio::test]
async fn streaming_http_failure_never_accepts_partial_or_exposes_raw_errors_or_retries() {
    let cases = [
        ("200 OK", vec![frame("partial answer", None)], "中断"),
        (
            "200 OK",
            vec![frame("partial answer", None), frame("", Some("length"))],
            "截断",
        ),
        (
            "200 OK",
            vec![
                frame("partial answer", None),
                frame("", Some("content_filter")),
            ],
            "过滤",
        ),
        (
            "200 OK",
            vec![
                frame("partial answer", None),
                b"event: error\ndata: PRIVATE-KEY-AND-SOURCE\n\n".to_vec(),
            ],
            "错误",
        ),
        (
            "200 OK",
            vec![
                frame("partial answer", None),
                b"data: {not valid JSON}\n\n".to_vec(),
            ],
            "不兼容",
        ),
        (
            "400 Bad Request",
            vec![b"PRIVATE-KEY-AND-SOURCE".to_vec()],
            "400",
        ),
        (
            "401 Unauthorized",
            vec![b"PRIVATE-KEY-AND-SOURCE".to_vec()],
            "401",
        ),
    ];
    for (status, chunks, expected) in cases {
        let server = fixture(chunks, false, status, "text/event-stream");
        let result = translate_one_streaming(
            &client(),
            &provider(&server.url),
            Ok("fixture-only".into()),
            "fixture",
            "en",
            "zh-Hans",
            |_| {},
        )
        .await;
        assert!(result.text.is_empty());
        let error = result.error.unwrap();
        assert!(error.contains(expected), "{expected}: {error}");
        assert!(!error.contains("PRIVATE-KEY-AND-SOURCE"));
        assert!(!error.contains("partial answer"));
        assert_eq!(server.worker.join().unwrap()["stream"], true);
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn streaming_http_cancellation_drops_reading_and_cannot_publish_late_content() {
    let server = fixture(
        vec![
            frame("first answer", None),
            frame("late answer", Some("stop")),
        ],
        true,
        "200 OK",
        "text/event-stream",
    );
    let requests = Arc::new(crate::translation_requests::TranslationRequests::default());
    let epoch = requests.resume(None).unwrap().epoch;
    let request_id = requests.begin(epoch).unwrap();
    let task_requests = requests.clone();
    let notify = Arc::new(tokio::sync::Notify::new());
    let callback_notify = notify.clone();
    let updates = Arc::new(Mutex::new(Vec::new()));
    let callback_updates = updates.clone();
    let p = provider(&server.url);
    let task = tokio::spawn(async move {
        task_requests
            .execute(
                request_id,
                translate_one_streaming(
                    &client(),
                    &p,
                    Ok("fixture-only".into()),
                    "fixture",
                    "en",
                    "zh-Hans",
                    move |text| {
                        callback_updates.lock().unwrap().push(text.to_owned());
                        callback_notify.notify_one();
                    },
                ),
            )
            .await
    });
    tokio::time::timeout(Duration::from_secs(3), notify.notified())
        .await
        .unwrap();
    requests.cancel(Some(request_id)).unwrap();
    assert_eq!(
        task.await.unwrap().unwrap_err(),
        crate::translation_requests::CANCELLED
    );
    server.release.send(()).unwrap();
    server.worker.join().unwrap();
    assert_eq!(*updates.lock().unwrap(), ["first answer"]);
    assert!(requests.finish(request_id, || Ok(())).is_err());
}

#[tokio::test]
async fn streaming_http_total_budget_counts_framing_and_unfinished_large_frames() {
    let server = fixture(
        vec![frame("partial answer", None), vec![b'x'; MAX_RESPONSE]],
        false,
        "200 OK",
        "text/event-stream",
    );
    let result = translate_one_streaming(
        &client(),
        &provider(&server.url),
        Ok("fixture-only".into()),
        "fixture",
        "en",
        "zh-Hans",
        |_| {},
    )
    .await;
    assert!(result.text.is_empty());
    assert!(result.error.unwrap().contains("2 MiB"));
    server.worker.join().unwrap();
}

#[test]
fn streaming_request_scopes_minimax_private_extension_to_exact_official_hosts() {
    for url in ["https://api.minimax.cn/v1", "https://api.minimax.io/v1"] {
        let p = provider(url);
        assert_eq!(
            streaming_request_body(&p, "fixture", "en", "zh-Hans", "")["reasoning_split"],
            true
        );
        assert_eq!(
            request_body(&p, "fixture", "en", "zh-Hans", "")["stream"],
            false
        );
    }
    for url in [
        "https://api.minimax.cn.attacker.invalid/v1",
        "https://other.invalid/api.minimax.io/v1",
    ] {
        assert!(
            streaming_request_body(&provider(url), "fixture", "en", "zh-Hans", "")
                .get("reasoning_split")
                .is_none()
        );
    }
}
