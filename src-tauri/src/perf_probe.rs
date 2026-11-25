//! Release-profile measurements of in-process paths. Ignored unless requested.
//! Prints durations and this process's Linux RSS only. No source text, image
//! bytes, paths, or secrets are printed.
use super::{
    persist_trimmed_startup_history, startup_storage, trim_history, write_json, HistoryEntry,
    MAX_HISTORY_BYTES,
};
use crate::screenshot::{from_base64, png_base64_payload};
use crate::translation_requests::TranslationRequests;
use image::RgbaImage;
use std::time::Instant;

fn percentile(mut samples: Vec<u128>, q: f64) -> u128 {
    assert!(!samples.is_empty());
    samples.sort_unstable();
    let index = ((q * samples.len() as f64).ceil() as usize)
        .saturating_sub(1)
        .min(samples.len() - 1);
    samples[index]
}

fn measure(warmup: usize, runs: usize, mut body: impl FnMut()) -> Vec<u128> {
    for _ in 0..warmup {
        body();
    }
    let mut samples = Vec::with_capacity(runs);
    for _ in 0..runs {
        let started = Instant::now();
        body();
        samples.push(started.elapsed().as_nanos());
    }
    samples
}

fn report(name: &str, samples: &[u128]) {
    let mut ordered = samples.to_vec();
    ordered.sort_unstable();
    let us = |value: u128| value as f64 / 1_000.0;
    println!(
        "PERF name={name} n={} unit=us min={:.3} median={:.3} p95={:.3} max={:.3}",
        samples.len(),
        us(ordered[0]),
        us(percentile(ordered.clone(), 0.50)),
        us(percentile(ordered.clone(), 0.95)),
        us(*ordered.last().unwrap())
    );
}

fn parse_status_kib(text: &str, label: &str) -> Option<u64> {
    let prefix = format!("{label}:");
    for line in text.lines() {
        if let Some(rest) = line.strip_prefix(&prefix) {
            return rest.split_whitespace().next()?.parse().ok();
        }
    }
    None
}

fn vm_kib(label: &str) -> Option<u64> {
    parse_status_kib(&std::fs::read_to_string("/proc/self/status").ok()?, label)
}

fn report_rss(phase: &str) {
    match (vm_kib("VmRSS"), vm_kib("VmHWM")) {
        (Some(rss), Some(peak)) => {
            println!("PERF name=proc_{phase} unit=kib vmrss={rss} vmhwm={peak}");
        }
        _ => println!("PERF name=proc_{phase} unit=kib unavailable"),
    }
}

fn entry(index: usize, chars: usize) -> HistoryEntry {
    HistoryEntry {
        id: format!("fixture-{index}"),
        text: "x".repeat(chars),
        source_language: "en".into(),
        target_language: "zh-Hans".into(),
        results: Vec::new(),
        created_at: index as u64,
        favorite: false,
    }
}

fn history(count: usize, chars: usize) -> Vec<HistoryEntry> {
    (0..count).map(|index| entry(index, chars)).collect()
}

fn image(width: u32, height: u32, noisy: bool) -> RgbaImage {
    RgbaImage::from_fn(width, height, |x, y| {
        let pixel = if noisy {
            (x.wrapping_mul(13) ^ y.wrapping_mul(7)) as u8
        } else {
            ((x / 8) + (y / 8)) as u8
        };
        image::Rgba([pixel, pixel.wrapping_add(20), 40, 255])
    })
}

#[test]
fn status_kib_skips_unrelated_lines() {
    let text = "Name:\tprobe\nVmRSS:\t 12345 kB\nVmHWM:\t 23456 kB\n";
    assert_eq!(parse_status_kib(text, "VmRSS"), Some(12345));
    assert_eq!(parse_status_kib(text, "VmHWM"), Some(23456));
    assert_eq!(parse_status_kib(text, "VmSize"), None);
}
#[test]
fn percentile_uses_nearest_rank() {
    let samples: Vec<u128> = (1..=100).collect();
    assert_eq!(percentile(samples.clone(), 0.50), 50);
    assert_eq!(percentile(samples, 0.95), 95);
}

#[test]
#[ignore = "opt-in perf probe; run with cargo test --profile perf perf_probe_paths -- --ignored --nocapture"]
fn perf_probe_paths() {
    let wall = Instant::now();
    report_rss("probe_start");

    let small = history(20, 120);
    let samples = measure(5, 31, || {
        let mut owned = small.clone();
        trim_history(&mut owned, 20);
    });
    report("history_clone_trim_20x120", &samples);

    let large = history(100, 8_000);
    let samples = measure(2, 15, || {
        let mut owned = large.clone();
        owned.insert(0, entry(1_000, 8_000));
        trim_history(&mut owned, 100);
    });
    report("history_clone_insert_trim_100x8000", &samples);

    let directory = std::env::temp_dir().join(format!(
        "echolingo-perf-{:x}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir(&directory).unwrap();
    let path = directory.join("history.json");
    let stored = history(100, 2_000);
    write_json(&path, &stored).unwrap();
    let samples = measure(2, 15, || {
        let mut warnings = Vec::new();
        let loaded: Vec<HistoryEntry> = startup_storage::load(
            &path,
            |bytes| serde_json::from_slice(bytes).ok(),
            Vec::new,
            "历史文件",
            &mut warnings,
        )
        .unwrap();
        assert_eq!(loaded.len(), 100);
        assert!(warnings.is_empty());
    });
    report("history_startup_load_100x2000", &samples);

    let mut trim_samples = Vec::with_capacity(11);
    for _ in 0..2 {
        let mut loaded: Vec<HistoryEntry> =
            serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        persist_trimmed_startup_history(&path, &mut loaded, 20).unwrap();
        write_json(&path, &stored).unwrap();
    }
    for _ in 0..11 {
        let bytes = std::fs::read(&path).unwrap();
        let started = Instant::now();
        let mut loaded: Vec<HistoryEntry> = serde_json::from_slice(&bytes).unwrap();
        persist_trimmed_startup_history(&path, &mut loaded, 20).unwrap();
        trim_samples.push(started.elapsed().as_nanos());
        assert_eq!(loaded.len(), 20);
        write_json(&path, &stored).unwrap();
    }
    report("history_startup_trim_persist_100_to_20", &trim_samples);
    let saved: Vec<HistoryEntry> = serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
    assert!(saved.len() <= 100);
    assert!(std::fs::metadata(&path).unwrap().len() < MAX_HISTORY_BYTES as u64);
    std::fs::remove_dir_all(&directory).unwrap();

    for (name, width, height, noisy, warmup, runs) in [
        ("screenshot_payload_320x180", 320, 180, false, 2, 15),
        ("screenshot_payload_1920x1080_gradient", 1920, 1080, false, 1, 9),
        ("screenshot_payload_1920x1080_noisy", 1920, 1080, true, 1, 7),
    ] {
        let pixels = image(width, height, noisy);
        let payload = png_base64_payload(&pixels).unwrap();
        let encoded_len = payload.len();
        let samples = measure(warmup, runs, || {
            let encoded = png_base64_payload(&pixels).unwrap();
            assert!(encoded.len() > 32);
        });
        report(&format!("{name}_encode_base64"), &samples);
        let samples = measure(warmup, runs, || {
            let decoded = from_base64(&payload, true).unwrap();
            assert_eq!(decoded.width(), width);
        });
        report(&format!("{name}_from_base64"), &samples);
        println!("PERF name={name}_payload_bytes bytes={encoded_len}");
        drop(pixels);
        drop(payload);
    }
    report_rss("after_screenshot_payload");

    let requests = TranslationRequests::default();
    let samples = measure(50, 201, || {
        let epoch = requests.resume(None).unwrap().epoch;
        let id = requests.begin(epoch).unwrap();
        assert!(requests.cancel(Some(id)).unwrap().is_some());
    });
    report("translation_resume_begin_cancel", &samples);

    let samples = measure(20, 101, || {
        let scheduled = TranslationRequests::default();
        let epoch = scheduled.resume(None).unwrap().epoch;
        let id = scheduled.begin(epoch).unwrap();
        let future = scheduled.execute(id, std::future::ready(7u64));
        assert_eq!(poll_ready(future), 7);
    });
    report("translation_begin_execute_ready", &samples);
    report_rss("probe_end");
    println!(
        "PERF name=probe_wall_clock unit=ms value={:.3} note=includes_warmup_and_assertions_not_a_single_stage",
        wall.elapsed().as_secs_f64() * 1_000.0
    );
}

fn poll_ready(future: impl std::future::Future<Output = Result<u64, String>>) -> u64 {
    let mut future = std::pin::pin!(future);
    let waker = std::task::Waker::from(std::sync::Arc::new(NopWaker));
    let mut context = std::task::Context::from_waker(&waker);
    match future.as_mut().poll(&mut context) {
        std::task::Poll::Ready(value) => value.unwrap(),
        std::task::Poll::Pending => panic!("ready future stayed pending"),
    }
}

struct NopWaker;
impl std::task::Wake for NopWaker {
    fn wake(self: std::sync::Arc<Self>) {}
}
