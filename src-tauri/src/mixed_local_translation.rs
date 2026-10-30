//! Conservative local-only translation of Chinese prose inside diagnostic logs.
//! Protected syntax is never sent to an engine and is reconstructed byte-for-byte.
//! No automatic cloud splitting, partial results, retries or detached work.
use std::{collections::HashMap, future::Future, ops::Range};

const MAX_FRAGMENTS: usize = 8;
const MAX_FRAGMENT_CHARS: usize = 512;
const MAX_INPUT_BYTES: usize = 20_000;
const MAX_OUTPUT_BYTES: usize = 2 * 1024 * 1024;

#[derive(Debug)]
pub struct Plan {
    original: String,
    spans: Vec<(Range<usize>, usize)>,
    fragments: Vec<String>,
    pub source: &'static str,
}

fn han(c: char) -> bool {
    matches!(c as u32, 0x3400..=0x4dbf | 0x4e00..=0x9fff | 0xf900..=0xfaff | 0x20000..=0x3134f)
}
fn other_script(c: char) -> bool {
    c.is_alphabetic() && !c.is_ascii_alphabetic() && !han(c)
}
fn technical_log(text: &str) -> bool {
    // Deliberately narrow: structured fields/calls, not normal bilingual prose.
    let fields = text.chars().filter(|c| matches!(c, ':' | '：')).count();
    let brackets =
        (text.contains('{') && text.contains('}')) || (text.contains('[') && text.contains(']'));
    let identifier = text
        .as_bytes()
        .windows(2)
        .any(|pair| pair[0].is_ascii_lowercase() && pair[1].is_ascii_uppercase())
        || text.contains('_');
    fields >= 2
        && brackets
        && identifier
        && text.chars().filter(|c| c.is_ascii_alphabetic()).count() >= 8
}

pub fn for_local_providers<'a>(
    text: &str,
    source: &str,
    target: &str,
    kinds: impl IntoIterator<Item = &'a str>,
) -> Option<Plan> {
    let mut any = false;
    let all_local = kinds.into_iter().all(|kind| {
        any = true;
        matches!(kind, "system" | "offline")
    });
    plan(text, source, target, any && all_local)
}

/// The original (unresolved) direction is required: explicit user choices win.
/// All selected providers must be local so one request/history has one direction.
fn plan(text: &str, source: &str, target: &str, local_only: bool) -> Option<Plan> {
    if !local_only
        || source != "auto"
        || target != "auto"
        || text.len() > MAX_INPUT_BYTES
        || !technical_log(text)
        || text.chars().any(other_script)
    {
        return None;
    }
    let mut protected = vec![false; text.len()];
    let mut fence: Option<(char, usize)> = None;
    let mut offset = 0;
    for line in text.split_inclusive('\n') {
        let trimmed = line.trim_start();
        let marker = trimmed
            .chars()
            .next()
            .filter(|c| matches!(c, '`' | '~'))
            .and_then(|marker| {
                let count = trimmed.chars().take_while(|c| *c == marker).count();
                (count >= 3).then_some((marker, count))
            });
        let was_fenced = fence.is_some();
        if let Some((marker, count)) = marker {
            match fence {
                Some((open_marker, open_count))
                    if marker == open_marker
                        && count >= open_count
                        && trimmed[count..].trim().is_empty() =>
                {
                    fence = None
                }
                None => fence = Some((marker, count)),
                _ => {}
            }
        }
        if was_fenced || fence.is_some() || marker.is_some() {
            protected[offset..offset + line.len()].fill(true);
        } else {
            // Inline code is syntax, not prose. Quotes alone do not protect Chinese
            // labels in log messages. An unmatched
            // opening delimiter protects the rest of its line rather than guessing.
            let bytes = line.as_bytes();
            let mut i = 0;
            while i < bytes.len() {
                if bytes[i] != b'`' {
                    i += 1;
                    continue;
                }
                let start = i;
                while i < bytes.len() && bytes[i] == b'`' {
                    i += 1;
                }
                let count = i - start;
                let mut end = bytes.len();
                let mut cursor = i;
                while cursor < bytes.len() {
                    if bytes[cursor] != b'`' {
                        cursor += 1;
                        continue;
                    }
                    let close = cursor;
                    while cursor < bytes.len() && bytes[cursor] == b'`' {
                        cursor += 1;
                    }
                    if cursor - close == count {
                        end = cursor;
                        break;
                    }
                }
                protected[offset + start..offset + end].fill(true);
                i = end;
            }
            // Preserve URL/email/path tokens, including Chinese path components.
            let mut start = 0;
            for token in line.split_inclusive(char::is_whitespace) {
                if token.contains('/') || token.contains('\\') || token.contains('@') {
                    protected[offset + start..offset + start + token.len()].fill(true);
                }
                start += token.len();
            }
        }
        offset += line.len();
    }
    let chars: Vec<_> = text.char_indices().collect();
    let mut spans = Vec::new();
    let mut fragments = Vec::new();
    let mut unique = HashMap::new();
    let mut i = 0;
    while i < chars.len() {
        let (start, c) = chars[i];
        if !han(c) || protected[start] {
            i += 1;
            continue;
        }
        let begin = i;
        while i < chars.len() && han(chars[i].1) && !protected[chars[i].0] {
            i += 1;
        }
        let end = chars.get(i).map_or(text.len(), |(at, _)| *at);
        // Chinese-containing identifiers stay intact; only isolated prose runs
        // of at least two Han characters are eligible.
        let identifier_neighbor = |c: char| c.is_ascii_alphanumeric() || c == '_';
        if i - begin > MAX_FRAGMENT_CHARS {
            return None;
        }
        if i - begin < 2
            || begin
                .checked_sub(1)
                .is_some_and(|n| identifier_neighbor(chars[n].1))
            || chars.get(i).is_some_and(|(_, c)| identifier_neighbor(*c))
        {
            continue;
        }
        let fragment = &text[start..end];
        let index = *unique.entry(fragment.to_owned()).or_insert_with(|| {
            fragments.push(fragment.to_owned());
            fragments.len() - 1
        });
        if fragments.len() > MAX_FRAGMENTS {
            return None;
        }
        spans.push((start..end, index));
    }
    if spans.is_empty() {
        return None;
    }
    // Structural Han text is not proof of Chinese (Japanese kanji can be all
    // Han too). Require an additional Chinese diagnostic cue; otherwise keep
    // the original native language-detection route instead of guessing.
    const CHINESE_CUES: &[&str] = &[
        "系统",
        "系統",
        "注册",
        "註冊",
        "错误",
        "錯誤",
        "失败",
        "无法",
        "無法",
        "文件",
        "窗口",
        "翻译",
        "翻譯",
        "设置",
        "設置",
        "复制",
        "複製",
        "连接",
        "連線",
        "下载",
        "下載",
        "加载",
        "載入",
        "读取",
        "讀取",
        "权限",
        "權限",
        "用户",
        "使用者",
    ];
    if !fragments
        .iter()
        .any(|fragment| CHINESE_CUES.iter().any(|cue| fragment.contains(cue)))
    {
        return None;
    }
    let chinese = fragments.join("");
    let source = match crate::language_detection::fallback_language(&chinese).as_deref() {
        Some("zh-Hant") => "zh-Hant",
        _ => "zh-Hans",
    };
    Some(Plan {
        original: text.to_owned(),
        spans,
        fragments,
        source,
    })
}

impl Plan {
    pub fn fragment_count(&self) -> usize {
        self.fragments.len()
    }
    /// Sequential bounded calls stay inside the caller's cancellable future.
    /// A failed fragment aborts the whole result; no partial text is published.
    pub async fn translate<F, Fut>(&self, translate: F) -> Result<String, String>
    where
        F: FnMut(String) -> Fut,
        Fut: Future<Output = Result<String, String>>,
    {
        self.translate_with_deadline(translate, std::time::Duration::from_secs(45))
            .await
    }

    async fn translate_with_deadline<F, Fut>(
        &self,
        translate: F,
        deadline: std::time::Duration,
    ) -> Result<String, String>
    where
        F: FnMut(String) -> Fut,
        Fut: Future<Output = Result<String, String>>,
    {
        tokio::time::timeout(deadline, self.translate_inner(translate))
            .await
            .map_err(|_| "本机混合文本翻译超时，请缩短文本或手动选择语言后重试".to_string())?
    }

    async fn translate_inner<F, Fut>(&self, mut translate: F) -> Result<String, String>
    where
        F: FnMut(String) -> Fut,
        Fut: Future<Output = Result<String, String>>,
    {
        let mut answers = Vec::with_capacity(self.fragments.len());
        for fragment in &self.fragments {
            let answer = translate(fragment.clone()).await?;
            let answer = answer.trim();
            // Do not inject apostrophes into an input containing single-quoted
            // syntax: a span may be only part of that value, not at its edges.
            // Unquoted inputs can still receive ordinary English contractions.
            if self.original.contains('\'') && answer.contains('\'') {
                return Err("本机混合文本翻译返回格式异常，请缩短文本或手动选择语言后重试".into());
            }
            if answer.is_empty()
                || answer.len() > 16_384
                || answer.chars().any(|c| {
                    c.is_control() || matches!(c, '"' | '`' | '\\' | '{' | '}' | '[' | ']')
                })
            {
                return Err("本机混合文本翻译返回格式异常，请缩短文本或手动选择语言后重试".into());
            }
            answers.push(answer.to_owned());
        }
        let mut result = String::with_capacity(self.original.len());
        let mut end = 0;
        for (span, index) in &self.spans {
            if result.len() + (span.start - end) + answers[*index].len() > MAX_OUTPUT_BYTES {
                return Err("本机混合文本译文超过大小上限，请缩短原文后重试".into());
            }
            result.push_str(&self.original[end..span.start]);
            result.push_str(&answers[*index]);
            end = span.end;
        }
        if result.len() + self.original.len() - end > MAX_OUTPUT_BYTES {
            return Err("本机混合文本译文超过大小上限，请缩短原文后重试".into());
        }
        result.push_str(&self.original[end..]);
        Ok(result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    const LOG: &str = "input (alt+KeyA)：系统注册失败：HotKey already registered: HotKey { mods: Modifiers(ALT), key: KeyA, id: 65555 }；ocr (shift+alt+KeyS)：系统注册失败";
    fn get(text: &str) -> Plan {
        plan(text, "auto", "auto", true).unwrap()
    }

    #[test]
    fn original_direction_and_local_only_are_required() {
        for (source, target, local) in [
            ("zh", "auto", true),
            ("auto", "en", true),
            ("auto", "auto", false),
        ] {
            assert!(plan(LOG, source, target, local).is_none());
        }
        assert_eq!(get(LOG).source, "zh-Hans");
    }
    #[test]
    fn real_provider_gate_accepts_only_nonempty_local_requests() {
        assert!(for_local_providers(LOG, "auto", "auto", ["system"]).is_some());
        assert!(for_local_providers(LOG, "auto", "auto", ["offline"]).is_some());
        assert!(for_local_providers(LOG, "auto", "auto", ["system", "offline"]).is_some());
        for kinds in [
            vec![],
            vec!["openai"],
            vec!["offline", "openai"],
            vec!["system", "unknown"],
        ] {
            assert!(for_local_providers(LOG, "auto", "auto", kinds).is_none());
        }
    }
    #[test]
    fn ordinary_text_and_other_languages_do_not_trigger() {
        for text in [
            "今天使用 Apple 翻译功能，效果很好。",
            "系统注册失败",
            "HotKey { key: KeyA, id: 1 }",
            "日本語です: HotKey { key: KeyA }",
            "오류: HotKey { key: KeyA }",
        ] {
            assert!(plan(text, "auto", "auto", true).is_none(), "{text}");
        }
    }
    #[test]
    fn ambiguous_han_identifiers_keep_original_language_detection() {
        assert!(plan(
            "HotKey { key: KeyA, reason: 登録失敗 }",
            "auto",
            "auto",
            true
        )
        .is_none());
    }
    #[tokio::test]
    async fn apostrophes_are_valid_english_unless_they_break_existing_quotes() {
        let unquoted = get("HotKey { key: KeyA, reason: 无法连接 }");
        assert!(unquoted
            .translate(|_| async { Ok("Can't connect".into()) })
            .await
            .unwrap()
            .contains("Can't connect"));
        let quoted = get("HotKey { key: KeyA, reason: '无法连接' }");
        assert!(quoted
            .translate(|_| async { Ok("Can't connect".into()) })
            .await
            .is_err());
        for text in [
            "HotKey { key: KeyA, reason: '无法连接，系统注册失败' }",
            "HotKey { key: KeyA, reason: 'error: 无法连接' }",
        ] {
            assert!(get(text)
                .translate(|_| async { Ok("Can't connect".into()) })
                .await
                .is_err());
        }
    }
    #[test]
    fn code_urls_paths_and_identifiers_are_preserved() {
        let text = format!("{LOG}\r\n`不应翻译` https://example.com/中文 C:\\中文\\file a中文Identifier\n```json\n{{\"中文\":\"字符串\"}}\n```\n~~~\n中文代码\n~~~\n");
        let plan = get(&text);
        assert_eq!(plan.fragments, ["系统注册失败"]);
        for (span, _) in plan.spans {
            assert_eq!(&text[span], "系统注册失败");
        }
    }
    #[test]
    fn multi_backtick_code_and_long_fences_remain_protected() {
        let text = format!("{LOG}\n``中文代码 ` 内部``\n````text\n```\n仍是代码\n````\n");
        assert_eq!(get(&text).fragments, ["系统注册失败"]);
    }
    #[test]
    fn quoted_log_labels_are_translated_but_quotes_are_not_sent() {
        let plan = get("HotKey { key: KeyA, reason: \"系统注册失败\" }");
        assert_eq!(plan.fragments, ["系统注册失败"]);
    }
    #[test]
    fn repeated_fragments_share_one_call_and_limits_fail_back_whole() {
        assert_eq!(get(LOG).fragments.len(), 1);
        let distinct = [
            "注册失败",
            "请求超时",
            "权限错误",
            "打开窗口",
            "关闭窗口",
            "加载文件",
            "读取文本",
            "翻译文本",
            "准备系统",
        ]
        .join("；");
        assert!(plan(
            &format!("HotKey {{ key: KeyA, note: {distinct} }}"),
            "auto",
            "auto",
            true
        )
        .is_none());
        assert!(plan(
            &format!("{LOG}{}", "x".repeat(MAX_INPUT_BYTES)),
            "auto",
            "auto",
            true
        )
        .is_none());
    }
    #[test]
    fn an_oversized_chinese_fragment_falls_back_the_entire_input() {
        assert!(plan(
            &format!("{LOG}；{}", "文".repeat(MAX_FRAGMENT_CHARS + 1)),
            "auto",
            "auto",
            true
        )
        .is_none());
    }
    #[test]
    fn traditional_prose_uses_existing_script_hint() {
        assert_eq!(
            get("HotKey { key: KeyA, reason: 系統註冊錯誤 }").source,
            "zh-Hant"
        );
    }
    #[tokio::test]
    async fn exact_log_symbols_newlines_and_english_round_trip() {
        let text = format!("{LOG}\r\n`中文代码`\n");
        let plan = get(&text);
        let mut calls = 0;
        let result = plan
            .translate(|fragment| {
                calls += 1;
                assert_eq!(fragment, "系统注册失败");
                async { Ok("System registration failed".into()) }
            })
            .await
            .unwrap();
        assert_eq!(calls, 1);
        assert_eq!(
            result,
            text.replace("系统注册失败", "System registration failed")
        );
    }
    #[tokio::test]
    async fn repeated_fragments_cannot_expand_output_without_bound() {
        let text = format!("HotKey {{ key: KeyA, note: {} }}", "错误；".repeat(1000));
        let plan = get(&text);
        assert_eq!(plan.fragment_count(), 1);
        let result = plan.translate(|_| async { Ok("x".repeat(16_000)) }).await;
        assert!(result.unwrap_err().contains("大小上限"));
    }
    #[tokio::test]
    async fn fragment_failure_aborts_without_retries_or_partial_answer() {
        let plan = get("HotKey { key: KeyA, reason: 注册失败；请求超时；权限错误 }");
        let mut calls = 0;
        let result = plan
            .translate(|_| {
                calls += 1;
                let index = calls;
                async move {
                    if index == 1 {
                        Ok("Failed".into())
                    } else {
                        Err("SYSTEM_TRANSLATION_DOWNLOAD_REQUIRED: setup".into())
                    }
                }
            })
            .await;
        assert_eq!(calls, 2);
        assert_eq!(
            result.unwrap_err(),
            "SYSTEM_TRANSLATION_DOWNLOAD_REQUIRED: setup"
        );
    }
    #[tokio::test]
    async fn invalid_output_cannot_corrupt_line_structure() {
        for answer in [
            "",
            " \t",
            "first\nsecond",
            "first\rsecond",
            "bad\"quote",
            "bad\\escape",
            "bad{field}",
            "bad\0value",
        ] {
            let result = get(LOG).translate(|_| async { Ok(answer.into()) }).await;
            assert!(result.is_err());
        }
    }
    #[tokio::test]
    async fn total_deadline_does_not_restart_for_each_fragment() {
        let plan = get("HotKey { key: KeyA, reason: 注册失败；请求超时 }");
        let mut calls = 0;
        let result = plan
            .translate_with_deadline(
                |_| {
                    calls += 1;
                    let call = calls;
                    async move {
                        if call == 1 {
                            Ok("Failed".into())
                        } else {
                            std::future::pending::<Result<String, String>>().await
                        }
                    }
                },
                std::time::Duration::from_millis(40),
            )
            .await;
        assert_eq!(calls, 2);
        assert!(result.unwrap_err().contains("超时"));
    }
    #[tokio::test]
    async fn cancellation_drops_pending_fragment_and_never_starts_next() {
        use std::sync::{
            atomic::{AtomicUsize, Ordering},
            Arc,
        };
        struct DropGuard(Arc<AtomicUsize>);
        impl Drop for DropGuard {
            fn drop(&mut self) {
                self.0.fetch_add(1, Ordering::SeqCst);
            }
        }
        let calls = Arc::new(AtomicUsize::new(0));
        let drops = Arc::new(AtomicUsize::new(0));
        let plan = get("HotKey { key: KeyA, reason: 注册失败；请求超时 }");
        let result = tokio::time::timeout(
            std::time::Duration::from_millis(10),
            plan.translate(|_| {
                calls.fetch_add(1, Ordering::SeqCst);
                let guard = DropGuard(drops.clone());
                async move {
                    let _guard = guard;
                    std::future::pending::<Result<String, String>>().await
                }
            }),
        )
        .await;
        assert!(result.is_err());
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        assert_eq!(drops.load(Ordering::SeqCst), 1);
    }
}
