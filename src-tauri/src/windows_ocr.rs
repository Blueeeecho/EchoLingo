//! Local Windows OCR. Call only from a blocking worker, never the UI/hook thread.
//! No files, subprocesses, networking, logging, or clipboard access.
use std::sync::{
    atomic::{AtomicBool, Ordering},
    mpsc, Arc,
};
use std::time::{Duration, Instant};
use windows::core::{Error, RuntimeType};
use windows::Graphics::Imaging::{BitmapAlphaMode, BitmapDecoder, BitmapPixelFormat};
use windows::Media::Ocr::{OcrEngine, OcrResult};
use windows::Storage::Streams::{DataWriter, InMemoryRandomAccessStream};
use windows::Win32::System::Com::{CoDecrementMTAUsage, CoIncrementMTAUsage, CO_MTA_USAGE_COOKIE};
use windows::Win32::System::WinRT::{RoInitialize, RoUninitialize, RO_INIT_MULTITHREADED};
use windows_future::IAsyncOperation;
#[path = "windows_ocr_layout.rs"]
mod layout;
const CANCELLED: &str = "CANCELLED: Native task was superseded.";
const TIMEOUT: &str = "OCR_TIMEOUT: Local OCR exceeded 30 seconds.";
const LANGUAGE_MISSING: &str = "OCR_LANGUAGE_MISSING: Install an OCR-capable language in Windows Settings > Time & language > Language & region > Language options. English or Chinese basic typing/OCR language features are suitable.";

fn native_error(error: Error) -> String {
    // HRESULT only: native messages can include paths or other user data.
    format!(
        "OCR_UNAVAILABLE: Windows OCR failed (HRESULT 0x{:08X}).",
        error.code().0 as u32
    )
}
struct Apartment;
impl Apartment {
    fn new() -> Result<Self, String> {
        unsafe { RoInitialize(RO_INIT_MULTITHREADED) }.map_err(native_error)?;
        Ok(Self)
    }
}
impl Drop for Apartment {
    fn drop(&mut self) {
        unsafe { RoUninitialize() };
    }
}
// A callback may outlive the calling worker after cancellation. Keep the MTA
// alive until that callback has released its owned COM inputs, not just until
// RoUninitialize. Microsoft explicitly permits decrement on another thread:
// https://learn.microsoft.com/windows/win32/api/combaseapi/nf-combaseapi-coincrementmtausage
struct MtaLifetime(CO_MTA_USAGE_COOKIE);
unsafe impl Send for MtaLifetime {}
unsafe impl Sync for MtaLifetime {}
impl Drop for MtaLifetime {
    fn drop(&mut self) {
        let _ = unsafe { CoDecrementMTAUsage(self.0) };
    }
}
fn check(cancel: &AtomicBool, deadline: Instant) -> Result<(), String> {
    if cancel.load(Ordering::SeqCst) {
        Err(CANCELLED.into())
    } else if Instant::now() >= deadline {
        Err(TIMEOUT.into())
    } else {
        Ok(())
    }
}
/// Completion owns every asynchronous input plus the MTA lifetime. Cancellation
/// never calls Close on a running bitmap/stream. No stack pointer/event HANDLE
/// is retained by WinRT. The callback safely drops its result if we have left.
fn wait<T: RuntimeType + Send + 'static, K: Send + 'static>(
    operation: IAsyncOperation<T>,
    keep_alive: K,
    mta: Arc<MtaLifetime>,
    cancel: &AtomicBool,
    deadline: Instant,
) -> Result<T, String> {
    let (tx, rx) = mpsc::sync_channel(1);
    operation
        .when(move |result| {
            let _ = tx.send(result);
            drop(keep_alive);
            drop(mta);
        })
        .map_err(native_error)?;
    loop {
        if let Err(error) = check(cancel, deadline) {
            let _ = operation.Cancel();
            return Err(error);
        }
        let remaining = deadline.saturating_duration_since(Instant::now());
        match rx.recv_timeout(remaining.min(Duration::from_millis(30))) {
            Ok(result) => {
                check(cancel, deadline)?;
                return result.map_err(native_error);
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                return Err("OCR_UNAVAILABLE: Windows OCR completion channel closed.".into())
            }
        }
    }
}
fn engine() -> Result<OcrEngine, String> {
    match OcrEngine::TryCreateFromUserProfileLanguages() {
        Ok(engine) => Ok(engine),
        // windows-rs represents successful COM calls returning null as S_OK
        // errors. Only null means missing; don't hide real runtime failures.
        Err(error) if error.code().0 == 0 => {
            let languages = OcrEngine::AvailableRecognizerLanguages().map_err(native_error)?;
            if languages.Size().map_err(native_error)? == 0 {
                return Err(LANGUAGE_MISSING.into());
            }
            OcrEngine::TryCreateFromLanguage(&languages.GetAt(0).map_err(native_error)?).map_err(
                |e| {
                    if e.code().0 == 0 {
                        LANGUAGE_MISSING.into()
                    } else {
                        native_error(e)
                    }
                },
            )
        }
        Err(error) => Err(native_error(error)),
    }
}
pub fn available_languages() -> Result<Vec<String>, String> {
    let _apartment = Apartment::new()?;
    let languages = OcrEngine::AvailableRecognizerLanguages().map_err(native_error)?;
    (0..languages.Size().map_err(native_error)?)
        .map(|i| {
            Ok(languages
                .GetAt(i)
                .map_err(native_error)?
                .LanguageTag()
                .map_err(native_error)?
                .to_string())
        })
        .collect()
}
fn validate_dimensions(width: u32, height: u32, maximum: u32) -> Result<(), String> {
    if width == 0 || height == 0 {
        return Err("CAPTURE: Captured PNG was empty.".into());
    }
    if width > maximum || height > maximum || u64::from(width) * u64::from(height) > 32_000_000 {
        return Err(format!("OCR_IMAGE_TOO_LARGE: Selected image exceeds the Windows OCR limit of {maximum} pixels per dimension or 32 megapixels. Select a smaller region."));
    }
    Ok(())
}
fn layout_text(
    result: &OcrResult,
    cancel: &AtomicBool,
    deadline: Instant,
) -> Result<String, String> {
    let native_lines = result.Lines().map_err(native_error)?;
    let count = native_lines.Size().map_err(native_error)?;
    if count > 50_000 {
        return Err("OCR_RESULT_TOO_LARGE: Too many recognized lines.".into());
    }
    let mut lines = Vec::new();
    let mut text_bytes = 0usize;
    let mut total_words = 0u64;
    for i in 0..count {
        check(cancel, deadline)?;
        let native = native_lines.GetAt(i).map_err(native_error)?;
        let mut line = layout::Line {
            text: native.Text().map_err(native_error)?.to_string(),
            x: f64::INFINITY,
            y: f64::INFINITY,
            width: f64::NAN,
            height: f64::NAN,
        };
        text_bytes += line.text.len();
        if text_bytes > 2 * 1024 * 1024 {
            return Err("OCR_RESULT_TOO_LARGE: Recognized text exceeds 2 MiB.".into());
        }
        // Optional word geometry must never discard recognized line text.
        let bounds = (|| -> Result<(f64, f64, f64, f64), String> {
            let words = native.Words().map_err(native_error)?;
            let word_count = words.Size().map_err(native_error)?;
            total_words += u64::from(word_count);
            if total_words > 500_000 {
                return Err("OCR_RESULT_TOO_LARGE: Too many recognized words.".into());
            }
            let (mut left, mut top, mut right, mut bottom) = (
                f64::INFINITY,
                f64::INFINITY,
                f64::NEG_INFINITY,
                f64::NEG_INFINITY,
            );
            for j in 0..word_count {
                check(cancel, deadline)?;
                let b = words
                    .GetAt(j)
                    .map_err(native_error)?
                    .BoundingRect()
                    .map_err(native_error)?;
                let (x, y, w, h) = (b.X as f64, b.Y as f64, b.Width as f64, b.Height as f64);
                if [x, y, w, h].iter().all(|v| v.is_finite()) && w > 0.0 && h > 0.0 {
                    left = left.min(x);
                    top = top.min(y);
                    right = right.max(x + w);
                    bottom = bottom.max(y + h);
                }
            }
            Ok((left, top, right - left, bottom - top))
        })();
        if let Err(ref error) = bounds {
            if error.starts_with("CANCELLED:")
                || error.starts_with("OCR_TIMEOUT:")
                || error.starts_with("OCR_RESULT_TOO_LARGE:")
            {
                return Err(error.clone());
            }
        }
        if let Ok((x, y, width, height)) = bounds {
            line.x = x;
            line.y = y;
            line.width = width;
            line.height = height;
        }
        lines.push(line);
    }
    let geometry = match result.TextAngle() {
        Ok(reference) => reference
            .Value()
            .is_ok_and(|angle| angle.is_finite() && angle.abs() <= 10.0),
        Err(e) => e.code().0 == 0, // nullable angle: same as PS's no-angle case
    };
    check(cancel, deadline)?;
    let text = layout::join(&lines, geometry);
    check(cancel, deadline)?;
    if text.len() > 2 * 1024 * 1024 {
        return Err("OCR_RESULT_TOO_LARGE: Recognized text exceeds 2 MiB.".into());
    }
    if text.trim().is_empty() {
        Err("NO_TEXT: No text was recognized. Select a larger, clearer area and retry.".into())
    } else {
        Ok(text)
    }
}
pub fn recognize_png(png: &[u8], cancel: Arc<AtomicBool>) -> Result<String, String> {
    let deadline = Instant::now() + Duration::from_secs(30);
    check(&cancel, deadline)?;
    if png.is_empty() {
        return Err("CAPTURE: Captured PNG was empty.".into());
    }
    if png.len() > 8 * 1024 * 1024 {
        return Err(
            "CAPTURE_TOO_LARGE: Captured PNG exceeds 8 MiB. Select a smaller region.".into(),
        );
    }
    if !png.starts_with(b"\x89PNG\r\n\x1a\n") {
        return Err("CAPTURE: Invalid PNG input.".into());
    }
    let _apartment = Apartment::new()?;
    let mta = Arc::new(MtaLifetime(
        unsafe { CoIncrementMTAUsage() }.map_err(native_error)?,
    ));
    let engine = engine()?;
    check(&cancel, deadline)?;
    let stream = InMemoryRandomAccessStream::new().map_err(native_error)?;
    let writer = DataWriter::CreateDataWriter(&stream).map_err(native_error)?;
    writer.WriteBytes(png).map_err(native_error)?;
    check(&cancel, deadline)?;
    let stored = wait(
        writer.StoreAsync().map_err(native_error)?,
        (writer.clone(), stream.clone()),
        mta.clone(),
        &cancel,
        deadline,
    )?;
    if stored as usize != png.len() {
        return Err("CAPTURE: Incomplete PNG input.".into());
    }
    writer.DetachStream().map_err(native_error)?;
    stream.Seek(0).map_err(native_error)?;
    check(&cancel, deadline)?;
    let decoder = wait(
        BitmapDecoder::CreateWithIdAsync(
            BitmapDecoder::PngDecoderId().map_err(native_error)?,
            &stream,
        )
        .map_err(native_error)?,
        stream.clone(),
        mta.clone(),
        &cancel,
        deadline,
    )?;
    validate_dimensions(
        decoder.PixelWidth().map_err(native_error)?,
        decoder.PixelHeight().map_err(native_error)?,
        OcrEngine::MaxImageDimension().map_err(native_error)?,
    )?;
    check(&cancel, deadline)?;
    let bitmap = wait(
        decoder
            .GetSoftwareBitmapConvertedAsync(
                BitmapPixelFormat::Bgra8,
                BitmapAlphaMode::Premultiplied,
            )
            .map_err(native_error)?,
        (decoder.clone(), stream.clone()),
        mta.clone(),
        &cancel,
        deadline,
    )?;
    check(&cancel, deadline)?;
    let result = wait(
        engine.RecognizeAsync(&bitmap).map_err(native_error)?,
        (bitmap.clone(), engine, stream.clone()),
        mta,
        &cancel,
        deadline,
    )?;
    let text = layout_text(&result, &cancel, deadline)?;
    check(&cancel, deadline)?;
    // Recognition is terminal here; on early returns COM ownership, not Close,
    // releases inputs after any pending async callback finishes.
    let _ = bitmap.Close();
    let _ = stream.Close();
    Ok(text)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn cancellation_and_input_limits_precede_runtime() {
        let cancelled = Arc::new(AtomicBool::new(true));
        assert!(recognize_png(&[], cancelled)
            .unwrap_err()
            .starts_with("CANCELLED:"));
        assert!(recognize_png(&[], Arc::new(AtomicBool::new(false)))
            .unwrap_err()
            .starts_with("CAPTURE:"));
        assert!(recognize_png(
            &vec![0; 8 * 1024 * 1024 + 1],
            Arc::new(AtomicBool::new(false))
        )
        .unwrap_err()
        .starts_with("CAPTURE_TOO_LARGE:"));
        assert!(
            recognize_png(b"not a png", Arc::new(AtomicBool::new(false)))
                .unwrap_err()
                .starts_with("CAPTURE:")
        );
    }
    #[test]
    fn dimension_and_timeout_boundaries() {
        assert!(validate_dimensions(4096, 4096, 4096).is_ok());
        assert!(validate_dimensions(4097, 1, 4096).is_err());
        assert!(validate_dimensions(u32::MAX, u32::MAX, u32::MAX).is_err());
        assert!(validate_dimensions(0, 1, 4096).is_err());
        assert_eq!(
            check(&AtomicBool::new(false), Instant::now()).unwrap_err(),
            TIMEOUT
        );
    }
}

#[cfg(test)]
mod runtime_tests {
    use super::*;
    fn flag() -> Arc<AtomicBool> {
        Arc::new(AtomicBool::new(false))
    }
    fn white_png(width: u32, height: u32) -> Vec<u8> {
        let mut data = Vec::new();
        {
            let mut encoder = png::Encoder::new(&mut data, width, height);
            encoder.set_color(png::ColorType::Rgb);
            encoder.set_depth(png::BitDepth::Eight);
            let mut writer = encoder.write_header().unwrap();
            writer
                .write_image_data(&vec![255; (width as usize) * (height as usize) * 3])
                .unwrap();
        }
        data
    }
    #[test]
    fn native_generated_image_repeated_recognition_and_empty_semantics() {
        assert!(!available_languages()
            .expect("Windows CI requires an installed OCR language")
            .is_empty());
        let png = include_bytes!("../../tests/fixtures/windows-native-ocr-generated.png");
        for _ in 0..3 {
            let text =
                recognize_png(png, flag()).expect("generated image must be recognized locally");
            let compact: String = text.chars().filter(|c| !c.is_whitespace()).collect();
            assert!(
                compact.contains("ECHONATIVEOCR12345"),
                "synthetic OCR fixture mismatch"
            );
        }
        let error = recognize_png(&white_png(400, 150), flag()).unwrap_err();
        assert!(error.starts_with("NO_TEXT:"));
    }
    #[test]
    fn independent_workers_do_not_share_or_overwrite_results() {
        let workers: Vec<_> = (0..2)
            .map(|_| {
                std::thread::spawn(|| {
                    recognize_png(
                        include_bytes!("../../tests/fixtures/windows-native-ocr-generated.png"),
                        flag(),
                    )
                })
            })
            .collect();
        for worker in workers {
            let text = worker.join().unwrap().unwrap();
            assert!(text.contains("12345"));
        }
    }
    #[test]
    fn pending_operation_deadline_is_not_reset_per_phase() {
        let _apartment = Apartment::new().unwrap();
        let mta = Arc::new(MtaLifetime(unsafe { CoIncrementMTAUsage() }.unwrap()));
        let operation = IAsyncOperation::<u32>::spawn(|| {
            std::thread::sleep(Duration::from_millis(100));
            Ok(42)
        });
        let error = wait(
            operation,
            (),
            mta,
            &AtomicBool::new(false),
            Instant::now() + Duration::from_millis(5),
        )
        .unwrap_err();
        assert_eq!(error, TIMEOUT);
    }
    #[test]
    fn native_decoder_limit_before_bitmap_allocation() {
        let _apartment = Apartment::new().unwrap();
        let maximum = OcrEngine::MaxImageDimension().unwrap();
        let error = recognize_png(&white_png(maximum + 1, 1), flag()).unwrap_err();
        assert!(error.starts_with("OCR_IMAGE_TOO_LARGE:"));
        let error = recognize_png(b"\x89PNG\r\n\x1a\ninvalid", flag()).unwrap_err();
        assert!(error.starts_with("OCR_UNAVAILABLE:"));
    }
    #[test]
    fn pending_cancel_keeps_inputs_until_completion() {
        struct OwnedInput(Arc<AtomicBool>);
        impl Drop for OwnedInput {
            fn drop(&mut self) {
                self.0.store(true, Ordering::SeqCst);
            }
        }
        let _apartment = Apartment::new().unwrap();
        let mta = Arc::new(MtaLifetime(unsafe { CoIncrementMTAUsage() }.unwrap()));
        let dropped = flag();
        let cancel = flag();
        let c = cancel.clone();
        let operation = IAsyncOperation::<u32>::spawn(move || {
            std::thread::sleep(Duration::from_millis(100));
            Ok(42)
        });
        let trigger = std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(10));
            c.store(true, Ordering::SeqCst);
        });
        assert_eq!(
            wait(
                operation,
                OwnedInput(dropped.clone()),
                mta,
                &cancel,
                Instant::now() + Duration::from_secs(3)
            )
            .unwrap_err(),
            CANCELLED
        );
        trigger.join().unwrap();
        // Cancellation may itself complete the WinRT operation immediately.
        // Either way, retained inputs must eventually be released exactly once.
        let end = Instant::now() + Duration::from_secs(3);
        while !dropped.load(Ordering::SeqCst) && Instant::now() < end {
            std::thread::sleep(Duration::from_millis(10));
        }
        assert!(dropped.load(Ordering::SeqCst));
    }
}
