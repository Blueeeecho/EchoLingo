//! Automatic mode chooses a direction, never whether content may be translated.
//! Detection failure is a hint to use the shared fallback, not a request failure.

pub async fn resolve<F, Fut>(
    text: &str,
    source: &str,
    target: &str,
    detect: F,
) -> Result<(String, String), String>
where
    F: FnOnce() -> Fut,
    Fut: std::future::Future<Output = Result<String, String>>,
{
    let detected = if source == "auto" {
        detect().await.ok()
    } else {
        None
    };
    crate::language_detection::resolve_translation_languages(
        text,
        source,
        target,
        detected.as_deref(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn automatic_content_always_resolves_a_direction_despite_detection_failure() {
        for (text, expected) in [
            ("EchoLingo_0.2.1_macos_arm64.dmg", ("en", "zh-Hans")),
            ("/tmp/fixtures/report.txt", ("en", "zh-Hans")),
            ("C:\\Temp\\fixtures\\report.txt", ("en", "zh-Hans")),
            ("https://example.com/path?q=1", ("en", "zh-Hans")),
            ("gpt-4.1-mini", ("en", "zh-Hans")),
            ("12345\n+ - !@#$%^&*() {} [] —— 🪞", ("en", "zh-Hans")),
            ("\u{0105}\u{00e9}\u{017a}\u{03b1}", ("en", "zh-Hans")),
            ("Hello world", ("en", "zh-Hans")),
            ("报告.txt", ("zh-Hans", "en")),
            ("選詞翻譯、無感 OCR。", ("zh-Hant", "en")),
            ("日本語です9-10=1", ("ja", "zh-Hans")),
            ("한국 漢字 9=1", ("ko", "zh-Hans")),
        ] {
            let raw = text.to_owned();
            let mut calls = 0;
            let pair = resolve(&raw, "auto", "auto", || {
                calls += 1;
                async { Err("uncertain detection".into()) }
            })
            .await
            .unwrap();
            assert_eq!((&*pair.0, &*pair.1), expected, "{text}");
            assert_eq!(calls, 1);
            assert_eq!(raw.as_bytes(), text.as_bytes());
        }
    }

    #[tokio::test]
    async fn recognized_other_languages_translate_to_chinese() {
        for (text, detected) in [
            ("Veuillez lire le résumé du rapport.", "fr"),
            ("Пожалуйста, прочитайте этот документ.", "ru"),
            ("日本語です", "ja"),
            ("日本語", "ja"),
        ] {
            let pair = resolve(text, "auto", "auto", || async { Ok(detected.into()) })
                .await
                .unwrap();
            assert_eq!(pair, (detected.into(), "zh-Hans".into()));
        }
    }

    #[tokio::test]
    async fn explicit_source_skips_detection_and_manual_target_is_preserved() {
        assert_eq!(
            resolve("报告.txt", "fr", "de", || async {
                panic!("explicit source must not invoke detection")
            })
            .await
            .unwrap(),
            ("fr".into(), "de".into())
        );
        assert_eq!(
            resolve("bonjour", "auto", "en", || async { Ok("fr".into()) })
                .await
                .unwrap(),
            ("fr".into(), "en".into())
        );
    }
}
