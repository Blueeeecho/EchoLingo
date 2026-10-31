//! The explicitly named automatic Chinese/English mode is not an arbitrary
//! language detector. Manual language choices keep the normal multilingual path.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Plan {
    Preserve,
    Translate {
        source: &'static str,
        target: &'static str,
    },
}

fn han(c: char) -> bool {
    matches!(c as u32, 0x3400..=0x4dbf | 0x4e00..=0x9fff | 0xf900..=0xfaff | 0x20000..=0x3134f)
}
fn unquote(token: &str) -> &str {
    for quote in ['"', '\''] {
        if let Some(inner) = token
            .strip_prefix(quote)
            .and_then(|s| s.strip_suffix(quote))
        {
            return inner;
        }
    }
    token
}
fn filename(token: &str) -> bool {
    let Some((stem, extension)) = token.rsplit_once('.') else {
        return false;
    };
    !stem.is_empty()
        && !extension.is_empty()
        && extension.len() <= 10
        && extension.bytes().all(|c| c.is_ascii_alphanumeric())
        && extension.as_bytes()[0].is_ascii_alphabetic()
        && stem
            .chars()
            .all(|c| c.is_alphanumeric() || matches!(c, '_' | '-' | '.' | ' '))
}
fn path_or_url(token: &str) -> bool {
    if token.starts_with('/')
        || token.starts_with("./")
        || token.starts_with("../")
        || token.starts_with("~/")
    {
        return true;
    }
    let bytes = token.as_bytes();
    if bytes.len() >= 3
        && bytes[0].is_ascii_alphabetic()
        && bytes[1] == b':'
        && matches!(bytes[2], b'/' | b'\\')
    {
        return true;
    }
    if let Some((scheme, address)) = token.split_once("://") {
        if !scheme.is_empty()
            && scheme
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || b"+.-".contains(&c))
            && !address.is_empty()
        {
            return true;
        }
    }
    // A slash alone is not a path: yes/no and 翻译/识别 are real prose.
    (token.contains('/') || token.contains('\\'))
        && token.rsplit(['/', '\\']).next().is_some_and(filename)
}
fn structural_token(token: &str) -> bool {
    let token = unquote(token);
    if token.is_empty() {
        return false;
    }
    if !token.chars().any(char::is_alphabetic) {
        return true;
    }
    if token.chars().any(char::is_whitespace) {
        return false;
    }
    // Slash-delimited paths/URLs are treated as addresses, not natural prose.
    if path_or_url(token) {
        return true;
    }
    if filename(token) {
        return true;
    }
    // Opaque model/version identifiers, not ordinary English words or sentences.
    token
        .bytes()
        .all(|c| c.is_ascii_alphanumeric() || b"_.:-".contains(&c))
        && (token.bytes().any(|c| c.is_ascii_digit())
            || token.contains('_')
            || token.contains("::"))
}
fn no_prose(text: &str) -> bool {
    if !text.chars().any(char::is_alphabetic) {
        return true;
    }
    text.lines().all(|line| {
        let line = line.trim();
        if line.is_empty() {
            return true;
        }
        let quoted = unquote(line);
        if quoted.len() != line.len() && (filename(quoted) || path_or_url(quoted)) {
            return true;
        }
        line.split_whitespace().all(structural_token)
    })
}

/// Some(Preserve) is a positive structural classification, never an error
/// fallback. Its raw input must be returned without detector/provider/key calls.
pub fn resolve(text: &str, source: &str, target: &str) -> Result<Option<Plan>, String> {
    if source != "auto" || target != "auto" {
        return Ok(None);
    }
    if no_prose(text) {
        return Ok(Some(Plan::Preserve));
    }
    if text.chars().any(han) {
        return Ok(Some(Plan::Translate {
            source: crate::language_detection::chinese_script_hint(text),
            target: "en",
        }));
    }
    // Keep the short ASCII-text behavior, but do not reject English merely
    // because OCR or a borrowed word contributed a non-ASCII letter. The local
    // classifier must positively identify English; other/uncertain languages
    // still require an explicit choice. Never rewrite the captured text.
    if text
        .chars()
        .filter(|c| c.is_alphabetic())
        .all(|c| c.is_ascii_alphabetic())
        || whatlang::detect(text)
            .is_some_and(|info| info.is_reliable() && info.lang() == whatlang::Lang::Eng)
    {
        return Ok(Some(Plan::Translate {
            source: "en",
            target: "zh-Hans",
        }));
    }
    Err("自动中英互译仅用于中文和英文；请手动选择源语言或目标语言后重试".into())
}

/// Shared routing gates used by the production request path. Merely creating
/// the fallback closures performs no work; the preserve branch never invokes
/// them, and all branches stay within the caller's cancellation lifecycle.
pub async fn detect_if_needed<F, Fut>(plan: Option<Plan>, source: &str, detect: F) -> Option<String>
where
    F: FnOnce() -> Fut,
    Fut: std::future::Future<Output = Result<String, String>>,
{
    if plan.is_some() || source != "auto" {
        None
    } else {
        detect().await.ok()
    }
}
pub async fn dispatch<T, P, F, Fut>(plan: Option<Plan>, raw: &str, preserve: P, translate: F) -> T
where
    P: FnOnce(&str) -> T,
    F: FnOnce() -> Fut,
    Fut: std::future::Future<Output = T>,
{
    if plan == Some(Plan::Preserve) {
        preserve(raw)
    } else {
        translate().await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn automatic(text: &str) -> Plan {
        resolve(text, "auto", "auto").unwrap().unwrap()
    }
    #[test]
    fn exact_filename_screenshot_and_other_structure_are_preserved() {
        for text in [
            "EchoLingo_0.2.1_macos_arm64.dmg\nEchoLingo_0.2.0_macos_arm64.dmg",
            "  EchoLingo_0.2.1_macos_arm64.dmg\r\n\r\n报告.txt\t\n",
            "/tmp/fixtures/report.txt",
            "C:\\Temp\\fixtures\\report.txt",
            "src/main.rs",
            "\"/tmp/fixtures/My report.txt\"",
            "\"My report.txt\"",
            "https://example.com/path?q=1",
            "gpt-4.1-mini",
            "Qwen3-4B",
            "x64 arm64",
            "12345\n+ - !@#$%^&*() {} [] ——",
            "file_name model::type",
        ] {
            assert_eq!(automatic(text), Plan::Preserve, "{text}");
        }
    }
    #[test]
    fn exact_windows_description_is_one_chinese_to_english_request() {
        let text =
            "Windows\n\nWindows 10 1809+ / 11 · x64\n\n选词翻译、无感 OCR 与内置中英离线翻译。";
        assert_eq!(
            automatic(text),
            Plan::Translate {
                source: "zh-Hans",
                target: "en"
            }
        );
        assert_eq!(
            automatic("Windows\n\n選詞翻譯、無感 OCR 與內建中英離線翻譯。"),
            Plan::Translate {
                source: "zh-Hant",
                target: "en"
            }
        );
        assert_eq!(
            automatic("HotKey: 系统注册失败 { key: KeyA }"),
            Plan::Translate {
                source: "zh-Hans",
                target: "en"
            }
        );
        assert_eq!(
            automatic("EchoLingo_0.2.1.dmg 文件下载失败"),
            Plan::Translate {
                source: "zh-Hans",
                target: "en"
            }
        );
    }
    #[test]
    fn ordinary_english_is_translated_not_silently_returned() {
        for text in [
            "Hello world",
            "Hello.",
            "Windows",
            "Please read report.txt",
            "The path /tmp/report.txt is missing.",
            "Version 2 is available",
            "input (alt+KeyA): already registered",
        ] {
            assert_eq!(
                automatic(text),
                Plan::Translate {
                    source: "en",
                    target: "zh-Hans"
                },
                "{text}"
            );
        }
    }
    #[test]
    fn slash_separated_prose_is_not_a_file_path() {
        for text in ["翻译/识别", "打开/关闭", "\"翻译/识别功能\""] {
            assert_eq!(
                automatic(text),
                Plan::Translate {
                    source: "zh-Hans",
                    target: "en"
                }
            );
        }
        assert_eq!(
            automatic("yes/no"),
            Plan::Translate {
                source: "en",
                target: "zh-Hans"
            }
        );
    }
    #[test]
    fn english_prose_with_ocr_noise_or_borrowed_words_keeps_english_direction() {
        let prose = "Please read the report and preserve the original paragraph boundaries. Do not change the numbers or code when translating this text.";
        for text in [
            format!("{prose}\u{0105}Xy"),
            format!("{prose}\u{00e9}"),
            format!("{prose}\u{03b1}"),
            "Please read the café menu and tell me whether the vegetarian option is available today.".into(),
        ] {
            assert_eq!(
                automatic(&text),
                Plan::Translate {
                    source: "en",
                    target: "zh-Hans"
                },
                "{text}"
            );
            assert_eq!(resolve(&text, "fr", "de").unwrap(), None);
        }
    }
    #[test]
    fn extended_alphabet_does_not_make_other_languages_english() {
        for text in [
            "Veuillez lire le résumé du rapport et conserver les paragraphes, les chiffres et la ponctuation du texte original.",
            "Proszę przeczytać ten dokument i zachować jego oryginalny układ oraz wszystkie liczby. To jest tekst napisany po polsku.",
            "Пожалуйста, прочитайте этот документ и сохраните исходные абзацы, числа и знаки препинания.",
            "こんにちは、ありがとうございます。おはようございます。",
            "\u{0105}\u{00e9}\u{017a}\u{03b1}",
        ] {
            assert!(resolve(text, "auto", "auto").is_err(), "{text}");
            assert_eq!(resolve(text, "auto", "en").unwrap(), None);
        }
    }
    #[test]
    fn manual_language_choices_keep_multilingual_behavior() {
        for text in [
            "EchoLingo_0.2.1.dmg",
            "日本語です",
            "bonjour le monde",
            "注册失败",
        ] {
            for (source, target) in [("ja", "auto"), ("auto", "fr"), ("en", "zh-Hans")] {
                assert_eq!(resolve(text, source, target).unwrap(), None);
            }
        }
    }
    #[test]
    fn other_scripts_require_manual_choice_not_random_model_download() {
        for text in ["こんにちは", "안녕하세요", "Привет мир", "français"] {
            assert!(resolve(text, "auto", "auto")
                .unwrap_err()
                .contains("手动选择"));
        }
        // Han-only text is intentionally Chinese in the named bilingual mode.
        // Japanese kanji ambiguity is resolved by an explicit source selection.
        assert!(matches!(
            automatic("日本語"),
            Plan::Translate { target: "en", .. }
        ));
        assert_eq!(resolve("日本語", "ja", "en").unwrap(), None);
    }
    #[tokio::test]
    async fn passthrough_preserves_exact_bytes_and_invokes_no_callbacks() {
        let raw = "  EchoLingo_0.2.1_macos_arm64.dmg\r\n\r\nEchoLingo_0.2.0_macos_arm64.dmg\t\n";
        let plan = resolve(raw, "auto", "auto").unwrap();
        assert_eq!(
            detect_if_needed(plan, "auto", || async { panic!("detector must not run") }).await,
            None
        );
        let result: Result<String, String> = dispatch(
            plan,
            raw,
            |raw| Ok(raw.to_owned()),
            || async { panic!("provider/key/model must not run") },
        )
        .await;
        assert_eq!(result.unwrap().as_bytes(), raw.as_bytes());
    }
    #[tokio::test]
    async fn bilingual_prose_skips_detector_but_keeps_one_provider_and_real_errors() {
        let raw = "Windows 10 1809+ / 11 · x64\n选词翻译、无感 OCR 与内置中英离线翻译。";
        let plan = resolve(raw, "auto", "auto").unwrap();
        assert_eq!(
            detect_if_needed(plan, "auto", || async {
                panic!("no arbitrary language identification")
            })
            .await,
            None
        );
        let mut calls = 0;
        let result: Result<String, String> = dispatch(
            plan,
            raw,
            |_| panic!("prose must not preserve"),
            || {
                calls += 1;
                async { Err("SYSTEM_TRANSLATION_DOWNLOAD_REQUIRED: real engine failure".into()) }
            },
        )
        .await;
        assert_eq!(calls, 1);
        assert_eq!(
            result.unwrap_err(),
            "SYSTEM_TRANSLATION_DOWNLOAD_REQUIRED: real engine failure"
        );
    }
    #[tokio::test]
    async fn manual_auto_source_still_calls_native_and_provider() {
        let plan = resolve("bonjour", "auto", "en").unwrap();
        assert_eq!(
            detect_if_needed(plan, "auto", || async { Ok("fr".into()) }).await,
            Some("fr".into())
        );
        let result = dispatch(
            plan,
            "bonjour",
            |_| "wrong".to_string(),
            || async { "hello".to_string() },
        )
        .await;
        assert_eq!(result, "hello");
    }
}
