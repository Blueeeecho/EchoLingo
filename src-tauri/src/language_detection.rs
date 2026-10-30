//! Resolve the user's direction once for every provider and the history entry.
//! Detection is local and never reads a clipboard, requests permission or uses
//! a network service. The native detector is optional; Unicode handles the
//! common Chinese/English cases when it is unavailable.

fn valid_language(value: &str) -> bool {
    let mut parts = value.split('-');
    let Some(first) = parts.next() else {
        return false;
    };
    (2..=8).contains(&first.len())
        && first.bytes().all(|c| c.is_ascii_alphabetic())
        && parts.clone().count() <= 3
        && parts.all(|part| {
            (1..=8).contains(&part.len()) && part.bytes().all(|c| c.is_ascii_alphanumeric())
        })
}

fn chinese(value: &str) -> bool {
    value
        .split('-')
        .next()
        .is_some_and(|code| code.eq_ignore_ascii_case("zh"))
}

fn native_uses_han(value: &str) -> bool {
    chinese(value)
        || value
            .split('-')
            .next()
            .is_some_and(|code| code.eq_ignore_ascii_case("ja") || code.eq_ignore_ascii_case("ko"))
}

fn is_han(c: char) -> bool {
    matches!(c as u32, 0x3400..=0x4dbf | 0x4e00..=0x9fff | 0xf900..=0xfaff | 0x20000..=0x3134f)
}

/// Digits, punctuation and symbols do not turn Han-only text into another
/// language. Mixed Latin/Kana/Hangul or other letters retain the native route.
fn han_without_other_letters(text: &str) -> bool {
    text.chars().any(is_han) && text.chars().filter(|c| c.is_alphabetic()).all(is_han)
}

/// Strong script evidence is useful for short Chinese phrases for which an OS
/// recognizer can report Traditional Chinese even when every character is shared
/// by both scripts (for example, 你好). This is a conservative hint, not a full
/// script converter or a claim to distinguish every ambiguous Chinese sentence.
fn chinese_script_hint(text: &str) -> &'static str {
    const TRADITIONAL: &str = "體國學術語譯軟電腦網頁開關設置權錄螢幕選擇輸歡應簡實現測試錯誤請這個為與來說對會時後過還讓無發現經驗點擊備註書寫讀畫圖區裡處動視務預設總廣東臺灣樂萬億專業聲";
    const SIMPLIFIED: &str = "体国学术语译软电脑网页开关设置权录荧选择输欢应简实现测试错误请这个为与来说对会时后过还让无发现经验点击备书写读画图区里处动视务预总广东台万亿专业声";
    let traditional = text.chars().filter(|c| TRADITIONAL.contains(*c)).count();
    let simplified = text.chars().filter(|c| SIMPLIFIED.contains(*c)).count();
    if traditional > simplified {
        "zh-Hant"
    } else {
        "zh-Hans"
    }
}

/// Useful for Windows and for short text that a general-purpose recognizer
/// cannot identify. Kana/Hangul take precedence over Han, so Japanese/Korean
/// text is not silently labelled Chinese. Non-Latin scripts remain unknown.
pub fn fallback_language(text: &str) -> Option<String> {
    let mut han = 0usize;
    let mut latin = 0usize;
    let mut other_letters = false;
    for c in text.chars() {
        if matches!(c as u32, 0x3040..=0x30ff | 0x31f0..=0x31ff) {
            return Some("ja".into());
        }
        if matches!(c as u32, 0x1100..=0x11ff | 0x3130..=0x318f | 0xac00..=0xd7af) {
            return Some("ko".into());
        }
        if is_han(c) {
            han += 1;
        } else if c.is_ascii_alphabetic() {
            latin += 1;
        } else if c.is_alphabetic() {
            other_letters = true;
        }
    }
    if other_letters {
        return None;
    }
    if han > 0 && han.saturating_mul(2) >= latin {
        Some(chinese_script_hint(text).into())
    } else if latin > 0 {
        Some("en".into())
    } else {
        None
    }
}

/// A language recognizer has very little evidence in short technical labels:
/// e.g. `quiet-pin` is reported as Catalan and `task:` as Danish by macOS.
/// Treat ASCII identifiers/labels as English in the default bilingual workflow.
/// Ordinary words and sentences still use the native language result, and a
/// manually chosen source always wins. This only examines structure; it never
/// changes the source text sent to a provider.
fn ascii_technical_label(text: &str) -> bool {
    let text = text.trim();
    if text.len() > 240
        || text.lines().filter(|line| !line.trim().is_empty()).count() > 1
        || !text.chars().any(|c| c.is_ascii_alphabetic())
        || text.chars().any(|c| {
            c.is_alphabetic() && !c.is_ascii_alphabetic()
                || matches!(c as u32, 0x0300..=0x036f | 0x1ab0..=0x1aff | 0x1dc0..=0x1dff | 0x20d0..=0x20ff | 0xfe20..=0xfe2f)
        })
        || text
            .split(|c: char| !c.is_ascii_alphanumeric())
            .filter(|part| !part.is_empty())
            .count()
            > 10
    {
        return false;
    }
    let chars: Vec<_> = text.chars().collect();
    if chars
        .windows(2)
        .any(|pair| pair[0].is_ascii_lowercase() && pair[1].is_ascii_uppercase())
        || chars.windows(3).any(|part| {
            part[0].is_ascii_uppercase()
                && part[1].is_ascii_uppercase()
                && part[2].is_ascii_lowercase()
        })
    {
        return true;
    }
    // Internal identifier separators also cover repeated underscores, paths,
    // dotted names, and symbols surrounding those identifiers.
    let mut before_separator = false;
    let mut separator = false;
    for c in chars {
        if c.is_ascii_alphanumeric() {
            if before_separator && separator {
                return true;
            }
            before_separator = true;
            separator = false;
        } else if "_-./\\:+*=&%@#$^~|[]{}<>\u{ff1a}\u{ff5c}".contains(c) {
            separator |= before_separator;
        } else {
            before_separator = false;
            separator = false;
        }
    }
    let after_list_number = text.trim_start_matches(|c: char| c.is_ascii_digit());
    let ordered_list = after_list_number.len() != text.len()
        && (after_list_number.starts_with(". ") || after_list_number.starts_with(") "));
    ordered_list
        || text.ends_with([':', '\u{ff1a}'])
        || text.starts_with(['#', '$', '@', '_', '~', '[', '{', '<', '`'])
        || text.starts_with("- ")
        || text.starts_with("* ")
        || text.starts_with("+ ")
        || text.starts_with("\u{2022} ")
        || text.starts_with("\u{25aa} ")
}

/// Stabilize the default local bilingual direction only when mixed prose has
/// several independent Chinese sentence cues. This is not language proof and
/// never changes the text, explicit choices, cloud requests, or JA/KO results.
pub fn local_mixed_prose_direction<'a>(
    text: &str,
    source: &str,
    target: &str,
    detected: Option<&str>,
    provider_kinds: impl IntoIterator<Item = &'a str>,
) -> Option<(String, String)> {
    let mut any_provider = false;
    let local_only = provider_kinds.into_iter().all(|kind| {
        any_provider = true;
        matches!(kind, "system" | "offline")
    });
    if !any_provider
        || !local_only
        || source != "auto"
        || target != "auto"
        || detected.is_some_and(|language| {
            language.split('-').next().is_some_and(|root| {
                root.eq_ignore_ascii_case("ja") || root.eq_ignore_ascii_case("ko")
            })
        })
        || !text.chars().any(|c| c.is_ascii_alphabetic())
        || text
            .chars()
            .any(|c| c.is_alphabetic() && !c.is_ascii_alphabetic() && !is_han(c))
    {
        return None;
    }
    let han_count = text.chars().filter(|c| is_han(*c)).count();
    let prose_runs = text
        .split(|c: char| !is_han(c))
        .filter(|run| run.chars().count() >= 4)
        .count();
    if han_count < 12 || prose_runs < 2 {
        return None;
    }
    // Simplified/traditional aliases count as one cue. Repeating one cue cannot
    // turn names, short labels, or isolated Han terms into Chinese prose.
    const CUES: &[&[&str]] = &[
        &["如果"],
        &["因为", "因為"],
        &["但是"],
        &["所以"],
        &["需要"],
        &["可以"],
        &["已经", "已經"],
        &["我们", "我們"],
        &["你们", "你們"],
        &["他们", "他們"],
        &["这个", "這個"],
        &["这些", "這些"],
        &["为了", "為了"],
        &["并且", "並且"],
        &["之后", "之後"],
        &["之前"],
        &["导致", "導致"],
        &["申请", "申請"],
        &["当前", "當前"],
    ];
    if CUES
        .iter()
        .filter(|aliases| aliases.iter().any(|cue| text.contains(cue)))
        .count()
        < 2
    {
        return None;
    }
    Some((chinese_script_hint(text).to_owned(), "en".to_owned()))
}

pub fn resolve_translation_languages(
    text: &str,
    source: &str,
    target: &str,
    detected: Option<&str>,
) -> Result<(String, String), String> {
    if source != "auto" && !valid_language(source) || target != "auto" && !valid_language(target) {
        return Err("语言设置无效，请重新选择源语言和目标语言".into());
    }
    let source = if source != "auto" {
        source.to_owned()
    } else {
        let has_letters = text.chars().any(char::is_alphabetic);
        let native = detected.filter(|value| {
            has_letters && valid_language(value) && !matches!(*value, "und" | "unknown" | "auto")
        });
        let fallback = fallback_language(text);
        match (native, fallback) {
            (native, Some(language))
                if chinese(&language)
                    && han_without_other_letters(text)
                    // Japanese Kanji and Korean Hanja can also be Han-only;
                    // preserve those native results instead of changing direction.
                    && native.map_or(true, |value| !native_uses_han(value)) =>
            {
                language
            }
            (_, Some(language)) if language == "en" && ascii_technical_label(text) => language,
            // Stabilize shared short Han text. For longer text, retain the
            // native Chinese script; both still choose English as the target.
            (Some(language), Some(fallback))
                if chinese(language)
                    && chinese(&fallback)
                    && text.chars().filter(|c| c.is_alphabetic()).count() <= 8 =>
            {
                fallback
            }
            (Some(language), _) => language.into(),
            (None, Some(language)) => language,
            (None, None) => "auto".into(),
        }
    };
    let target = if target == "auto" {
        if chinese(&source) {
            "en"
        } else {
            "zh-Hans"
        }
    } else {
        target
    };
    Ok((source, target.into()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn local_mixed_prose_uses_chinese_script_and_preserves_whole_input() {
        let text = "主题可以用：\n\nGrOk Bot 停止云端代理后仍继续运行，导致 CUISOr 周额度耗尽，申请核查与补\n\n如果想让对方更快看懂，也可以用英文： Cloud agent Kept running after stop request, used up my weekly Cursor quota - request for review and compensation";
        let before = text.to_owned();
        for detector in [Some("en"), Some("ca"), Some("zh-Hant"), None] {
            assert_eq!(
                local_mixed_prose_direction(text, "auto", "auto", detector, ["system"]),
                Some(("zh-Hans".into(), "en".into()))
            );
        }
        assert_eq!(text, before);
        let traditional = "我們已經完成了這個功能，並且可以使用 Apple 翻譯；如果需要更多資料，請查看 English documentation。";
        assert_eq!(
            local_mixed_prose_direction(traditional, "auto", "auto", Some("en"), ["offline"]),
            Some(("zh-Hant".into(), "en".into()))
        );
        let prose = "如果使用 DeepSeek 翻译，需要先配置自己的服务；我们已经说明了相关步骤，英文 API documentation 可以保留。";
        assert_eq!(
            local_mixed_prose_direction(prose, "auto", "auto", None, ["system", "offline"]),
            Some(("zh-Hans".into(), "en".into()))
        );
    }
    #[test]
    fn mixed_prose_never_overrides_manual_cloud_or_japanese_korean() {
        let text = "我们已经完成了这个功能，如果需要更多说明，可以查看 English documentation。";
        for detected in [Some("ja"), Some("ja-JP"), Some("ko"), Some("ko-KR")] {
            assert!(
                local_mixed_prose_direction(text, "auto", "auto", detected, ["system"]).is_none()
            );
        }
        for (source, target) in [("zh-Hans", "auto"), ("auto", "en"), ("en", "zh-Hans")] {
            assert!(
                local_mixed_prose_direction(text, source, target, Some("en"), ["system"]).is_none()
            );
        }
        for providers in [vec![], vec!["openai"], vec!["system", "openai"]] {
            assert!(local_mixed_prose_direction(text, "auto", "auto", None, providers).is_none());
        }
    }
    #[test]
    fn mixed_prose_requires_distinct_sentence_cues_not_only_han_or_names() {
        for text in [
            "Cloud agent kept running after the stop request.",
            "中国 日本 汉字 北京 上海 深圳 南京 Apple Translate", // labels/names
            "我们 Apple",
            "如果可以 Apple",                                   // insufficient prose
            "可以继续执行，可以继续执行，可以继续执行 English", // repeated one cue
            "因为继续执行，因為繼續執行，English",              // same cue in two scripts
            "我们已经完成了这个功能，もし必要なら English を確認してください。", // kana
            "我们已经完成了这个功能，如果需要 한국어 documentation。", // hangul
            "如果需要更多说明，可以查看 français documentation。", // other letters
        ] {
            assert!(
                local_mixed_prose_direction(text, "auto", "auto", Some("en"), ["system"]).is_none(),
                "{text}"
            );
        }
    }
    #[test]
    fn auto_direction_covers_english_chinese_and_short_shared_han() {
        for (text, detected, expected) in [
            ("Hello world", Some("en"), ("en", "zh-Hans")),
            ("你好", Some("zh-Hant"), ("zh-Hans", "en")),
            ("你好", None, ("zh-Hans", "en")),
            ("歡迎使用翻譯", None, ("zh-Hant", "en")),
            ("hello", None, ("en", "zh-Hans")),
            ("日本語です", Some("ja"), ("ja", "zh-Hans")),
            ("한국어", None, ("ko", "zh-Hans")),
            ("12345?!", None, ("auto", "zh-Hans")),
        ] {
            let (source, target) =
                resolve_translation_languages(text, "auto", "auto", detected).unwrap();
            assert_eq!((&*source, &*target), expected, "{text}");
        }
    }

    #[test]
    fn han_with_digits_and_symbols_overrides_unreliable_native_guesses() {
        for (text, expected) in [
            ("晚上9-10单打1=1，三级", "zh-Hans"),
            ("【20:30】第3组_进度=100%！", "zh-Hans"),
            ("9-10，三级", "zh-Hans"),
            ("（1）三级；2=2", "zh-Hans"),
            ("晚上９－１０，三級＝１ 🪞", "zh-Hans"),
            ("晚上9-10，請選擇第3組；進度=100%", "zh-Hant"),
        ] {
            for detected in [Some("en"), Some("es"), Some("ru"), Some("und"), None] {
                assert_eq!(
                    resolve_translation_languages(text, "auto", "auto", detected).unwrap(),
                    (expected.into(), "en".into()),
                    "{text} / {detected:?}"
                );
            }
        }
    }

    #[test]
    fn pure_han_preserves_japanese_and_korean_native_language_variants() {
        for (text, detected) in [
            ("日本語", "ja"),
            ("東京都", "ja-JP"),
            ("大韓民國", "ko"),
            ("韓國9-10=1", "ko-KR"),
        ] {
            assert!(han_without_other_letters(text));
            assert_eq!(
                resolve_translation_languages(text, "auto", "auto", Some(detected)).unwrap(),
                (detected.into(), "zh-Hans".into()),
                "{text} / {detected}"
            );
            assert_eq!(
                resolve_translation_languages(text, "en", "auto", Some(detected)).unwrap(),
                ("en".into(), "zh-Hans".into())
            );
        }
    }

    #[test]
    fn han_evidence_preserves_explicit_choices_and_other_script_detection() {
        let text = "晚上9-10单打1=1，三级";
        assert_eq!(
            resolve_translation_languages(text, "en", "auto", Some("zh-Hans")).unwrap(),
            ("en".into(), "zh-Hans".into())
        );
        assert_eq!(
            resolve_translation_languages(text, "ja", "fr", Some("zh-Hans")).unwrap(),
            ("ja".into(), "fr".into())
        );
        assert_eq!(
            resolve_translation_languages(text, "auto", "zh-Hant", Some("en")).unwrap(),
            ("zh-Hans".into(), "zh-Hant".into())
        );
        // Keep the existing native model variant for longer Chinese text.
        for language in ["zh-Hans", "zh-Hant"] {
            assert_eq!(
                resolve_translation_languages(
                    "晚上9-10单打1=1，三级；明天仍然继续练习。",
                    "auto",
                    "auto",
                    Some(language),
                )
                .unwrap(),
                (language.into(), "en".into())
            );
        }
        for (text, detected) in [
            ("日本語です9-10=1", "ja"),
            ("漢字カナ9_10", "ja"),
            ("한국 漢字 9=1", "ko"),
            ("Привет 中文 9-10", "ru"),
            ("中文 مرحبا 9=1", "ar"),
            ("Bonjour à 中文 9-10", "fr"),
            ("A long English sentence 你好 9=1", "en"),
        ] {
            assert!(!han_without_other_letters(text));
            assert_eq!(
                resolve_translation_languages(text, "auto", "auto", Some(detected)).unwrap(),
                (detected.into(), "zh-Hans".into()),
                "{text}"
            );
        }
    }

    #[test]
    fn explicit_choices_are_preserved_and_bad_detector_output_is_ignored() {
        for (source, target, expected) in [
            ("en", "auto", ("en", "zh-Hans")),
            ("zh-Hant", "auto", ("zh-Hant", "en")),
            ("fr", "de", ("fr", "de")),
            ("auto", "zh-Hant", ("zh-Hans", "zh-Hant")),
            ("auto", "en", ("zh-Hans", "en")),
        ] {
            let pair = resolve_translation_languages("你好", source, target, Some(";bad")).unwrap();
            assert_eq!((&*pair.0, &*pair.1), expected);
        }
        assert_eq!(
            resolve_translation_languages("你好", "auto", "auto", Some("und")).unwrap(),
            ("zh-Hans".into(), "en".into())
        );
        for (source, target) in [("", "en"), ("auto", "en\n"), ("en;open", "zh-Hans")] {
            assert!(resolve_translation_languages("hello", source, target, None).is_err());
        }
    }

    #[test]
    fn fallback_is_conservative_about_other_scripts_and_mixed_content() {
        assert_eq!(fallback_language("こんにちは 世界"), Some("ja".into()));
        assert_eq!(fallback_language("한국 漢字"), Some("ko".into()));
        assert_eq!(fallback_language("Bonjour à tous"), None);
        assert_eq!(fallback_language("Привет"), None);
        assert_eq!(fallback_language("这是 API 测试"), Some("zh-Hans".into()));
        assert_eq!(
            fallback_language("A long English sentence 你好"),
            Some("en".into())
        );
        assert_eq!(fallback_language("\n 123 🪞"), None);
    }

    #[test]
    fn technical_identifiers_and_markdown_labels_override_short_native_misclassification() {
        for text in [
            "- quiet-pin:",
            "quiet_pin",
            "quiet.pin",
            "quiet/pin",
            "#quiet-pin",
            "`quiet_pin`",
            "[quiet_pin]:",
            "$quiet_pin",
            "quiet__pin",
            "quietPin",
            "- task:",
            "* task:",
            "+ task:",
            "task:",
            "[ ] quiet_pin",
            "`arbitrary_identifier`",
            "someNovelIdentifier",
            "module/path_name.rs",
            "HTTPServer",
            "1. task",
            "2) task",
            "quiet+pin",
            "quiet=pin",
            "module::name",
            "\u{2022} task",
            "task\u{ff1a}",
            "quiet\u{ff5c}pin",
        ] {
            for detected in [Some("ca"), Some("tr"), Some("da"), Some("und"), None] {
                assert_eq!(
                    resolve_translation_languages(text, "auto", "auto", detected).unwrap(),
                    ("en".into(), "zh-Hans".into()),
                    "{text} / {detected:?}"
                );
            }
            assert_eq!(
                resolve_translation_languages(text, "fr", "de", Some("ca")).unwrap(),
                ("fr".into(), "de".into())
            );
        }
    }

    #[test]
    fn identifier_hint_does_not_override_natural_languages_or_invent_symbol_languages() {
        for (text, detected, expected) in [
            ("bonjour", "fr", "fr"),
            ("Hola", "es", "es"),
            ("bonjour tout le monde", "fr", "fr"),
            ("café_label", "fr", "fr"),
            ("cafe\u{301}_label", "fr", "fr"),
            ("- 任务:", "zh-Hans", "zh-Hans"),
            ("مرحبا_label", "ar", "ar"),
            ("こんにちは_label", "ja", "ja"),
            ("한국어_label", "ko", "ko"),
            ("Привет_label", "ru", "ru"),
            (
                "French paragraph here\nwith_identifier on another line",
                "fr",
                "fr",
            ),
        ] {
            assert!(!ascii_technical_label(text), "{text}");
            assert_eq!(
                resolve_translation_languages(text, "auto", "auto", Some(detected))
                    .unwrap()
                    .0,
                expected
            );
        }
        for text in ["---:", "___", "$$$", "#[]:", "123 :", " 🪞 ", ""] {
            for detected in [Some("en"), Some("unknown"), Some("und"), None] {
                assert_eq!(
                    resolve_translation_languages(text, "auto", "auto", detected)
                        .unwrap()
                        .0,
                    "auto",
                    "{text}"
                );
            }
        }
    }
}
