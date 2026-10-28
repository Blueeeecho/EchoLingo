//! Bounded OpenAI-compatible SSE decoding. No network, app events or credentials.
use serde_json::Value;

pub(super) const MAX_RESPONSE: usize = 2 * 1024 * 1024;
const INVALID: &str = "服务返回了不兼容的流式译文，请检查端点与模型";
const INCOMPLETE: &str = "流式译文接收中断，未获得完整结果，请重试";
const FILTERED: &str = "服务返回了截断或过滤的译文，请缩短输入或检查模型限制";

#[derive(Default)]
struct AnswerText {
    text: String,
    pending: String,
    // MiniMax legacy models can place a leading think block in content.
    // Other providers' literal translated tags must remain untouched.
    split_inline_reasoning: bool,
    in_reasoning: bool,
    answer_started: bool,
}

impl AnswerText {
    fn new(split_inline_reasoning: bool) -> Self {
        Self {
            split_inline_reasoning,
            ..Self::default()
        }
    }

    fn push(&mut self, fragment: &str) {
        if !self.split_inline_reasoning || self.answer_started {
            self.text.push_str(fragment);
            return;
        }
        self.pending.push_str(fragment);
        loop {
            if self.in_reasoning {
                let Some(end) = self.pending.find("</think>") else {
                    // Discard hidden reasoning immediately, retaining only a
                    // possible split closing tag. Long reasoning streams must
                    // not repeatedly rescan or keep a second complete copy.
                    let marker = "</think>";
                    let keep = (1..marker.len())
                        .rev()
                        .find(|&length| self.pending.ends_with(&marker[..length]))
                        .unwrap_or(0);
                    self.pending.drain(..self.pending.len() - keep);
                    return;
                };
                self.pending.drain(..end + "</think>".len());
                self.in_reasoning = false;
                // A separator after thinking is not part of the translation.
                self.pending = self.pending.trim_start().to_owned();
            }
            let content = self.pending.trim_start();
            if content.is_empty()
                || (content.len() < "<think>".len() && "<think>".starts_with(content))
            {
                return;
            }
            if content.starts_with("<think>") {
                self.pending = content["<think>".len()..].to_owned();
                self.in_reasoning = true;
                continue;
            }
            self.answer_started = true;
            self.text.push_str(&self.pending);
            self.pending.clear();
            return;
        }
    }

    fn finish(mut self) -> Result<String, String> {
        if self.in_reasoning {
            return Err(INCOMPLETE.into());
        }
        // A complete answer may legitimately end in a partial literal marker.
        if !self.answer_started {
            self.text.push_str(&self.pending);
        }
        if self.text.trim().is_empty() {
            return Err("API 返回格式不兼容或译文为空；请检查服务类型和模型".into());
        }
        Ok(self.text)
    }
}

pub(super) fn split_minimax_answer(text: &str) -> Result<String, String> {
    let mut answer = AnswerText::new(true);
    answer.push(text);
    answer.finish()
}

pub(super) struct OpenAiStream {
    line: Vec<u8>,
    data: String,
    event_error: bool,
    first_line: bool,
    skip_lf: bool,
    bytes_received: usize,
    answer: AnswerText,
    finished: bool,
    done: bool,
}

impl OpenAiStream {
    pub(super) fn new(split_inline_reasoning: bool) -> Self {
        Self {
            line: Vec::new(),
            data: String::new(),
            event_error: false,
            first_line: true,
            skip_lf: false,
            bytes_received: 0,
            answer: AnswerText::new(split_inline_reasoning),
            finished: false,
            done: false,
        }
    }

    pub(super) fn done(&self) -> bool {
        self.done
    }

    pub(super) fn push(&mut self, bytes: &[u8], on_progress: &impl Fn(&str)) -> Result<(), String> {
        self.bytes_received = self.bytes_received.saturating_add(bytes.len());
        if self.bytes_received > MAX_RESPONSE {
            return Err("API 响应超过 2 MiB 上限".into());
        }
        for &byte in bytes {
            if self.done {
                break;
            }
            if self.skip_lf {
                self.skip_lf = false;
                if byte == b'\n' {
                    continue;
                }
            }
            match byte {
                b'\r' => {
                    self.consume_line(on_progress)?;
                    self.skip_lf = true;
                }
                b'\n' => self.consume_line(on_progress)?,
                _ => self.line.push(byte),
            }
        }
        Ok(())
    }

    fn consume_line(&mut self, on_progress: &impl Fn(&str)) -> Result<(), String> {
        let bytes = std::mem::take(&mut self.line);
        let line = std::str::from_utf8(&bytes).map_err(|_| INVALID)?;
        let line = if self.first_line {
            self.first_line = false;
            line.strip_prefix('\u{feff}').unwrap_or(line)
        } else {
            line
        };
        if line.is_empty() {
            return self.consume_event(on_progress);
        }
        if line.starts_with(':') {
            return Ok(());
        }
        let (field, value) = line.split_once(':').unwrap_or((line, ""));
        let value = value.strip_prefix(' ').unwrap_or(value);
        match field {
            "data" => {
                if !self.data.is_empty() {
                    self.data.push('\n');
                }
                self.data.push_str(value);
            }
            "event" => self.event_error = value == "error",
            // EventSource metadata is not translated content.
            _ => {}
        }
        Ok(())
    }

    fn consume_event(&mut self, on_progress: &impl Fn(&str)) -> Result<(), String> {
        let data = std::mem::take(&mut self.data);
        let event_error = std::mem::take(&mut self.event_error);
        if event_error {
            return Err("服务在流式翻译过程中返回错误，请检查服务状态或额度".into());
        }
        if data.trim().is_empty() {
            return Ok(());
        }
        if data.trim() == "[DONE]" {
            self.done = true;
            return Ok(());
        }
        let value: Value = serde_json::from_str(&data).map_err(|_| INVALID)?;
        if value.get("error").is_some_and(|error| !error.is_null())
            || value
                .pointer("/base_resp/status_code")
                .and_then(Value::as_i64)
                .is_some_and(|code| code != 0)
        {
            // Never expose upstream messages, which can echo keys or source.
            return Err("服务在流式翻译过程中返回错误，请检查服务状态或额度".into());
        }
        let choices = value
            .get("choices")
            .and_then(Value::as_array)
            .ok_or(INVALID)?;
        // A final usage-only frame has an empty choices array.
        if choices.is_empty() {
            return Ok(());
        }
        let choice = choices.iter().find(|choice| {
            choice
                .get("index")
                .is_none_or(|index| index.as_u64() == Some(0))
        });
        let Some(choice) = choice else {
            return Ok(());
        };
        let reason = choice
            .get("finish_reason")
            .filter(|reason| !reason.is_null());
        if let Some(reason) = reason {
            match reason.as_str() {
                Some("stop") => {}
                Some("length" | "content_filter") => return Err(FILTERED.into()),
                _ => return Err("服务未返回完整文本译文，请检查模型与生成限制".into()),
            }
        }
        let empty_delta = serde_json::Map::new();
        let delta = match choice.get("delta") {
            Some(Value::Object(delta)) => delta,
            // Some compatible gateways use a null/missing delta in the final
            // finish-only frame. It cannot introduce any translated content.
            None | Some(Value::Null) if reason.is_some() => &empty_delta,
            _ => return Err(INVALID.into()),
        };
        if delta
            .get("refusal")
            .and_then(Value::as_str)
            .is_some_and(|s| !s.is_empty())
            || delta
                .get("tool_calls")
                .and_then(Value::as_array)
                .is_some_and(|v| !v.is_empty())
            || delta.get("function_call").is_some_and(|v| !v.is_null())
        {
            return Err("服务没有返回可用的文本译文，请检查模型与服务设置".into());
        }
        if let Some(content) = delta.get("content").filter(|value| !value.is_null()) {
            let text = content.as_str().ok_or(INVALID)?;
            if self.finished && !text.is_empty() {
                return Err(INVALID.into());
            }
            let before = self.answer.text.len();
            // Only content is an answer. reasoning_content/reasoning are ignored.
            self.answer.push(text);
            if self.answer.text.len() != before {
                on_progress(&self.answer.text);
            }
        }
        if reason.is_some() {
            self.finished = true;
        }
        Ok(())
    }

    pub(super) fn finish(mut self, on_progress: &impl Fn(&str)) -> Result<String, String> {
        if !self.done {
            // Complete lines only: an unterminated SSE event is not a terminal
            // marker, even when the underlying HTTP response ended cleanly.
            if !self.line.is_empty() || !self.data.is_empty() || self.event_error {
                return Err(INCOMPLETE.into());
            }
            if !self.finished {
                return Err(INCOMPLETE.into());
            }
        }
        let before = self.answer.text.len();
        let answer = std::mem::take(&mut self.answer).finish()?;
        if answer.len() != before {
            on_progress(&answer);
        }
        Ok(answer)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    fn frame(text: &str, finish: Option<&str>) -> String {
        format!(
            "data: {}\n\n",
            serde_json::json!({"choices":[{"index":0,"delta":{"content":text},"finish_reason":finish}]})
        )
    }

    #[test]
    fn sse_byte_splits_utf8_bom_crlf_and_multiline_data_preserve_only_content() {
        let source = format!(
            "\u{feff}: keepalive\r\nevent: message\r\ndata: {{\"choices\":[{{\"index\":0,\"delta\":{{\"role\":\"assistant\",\r\ndata: \"reasoning_content\":\"PRIVATE-REASONING-FIXTURE\",\"content\":\"你好 🪞\"}},\"finish_reason\":null}}]}}\r\n\r\n{}data: {{\"choices\":[],\"usage\":{{\"total_tokens\":3}}}}\r\n\r\ndata: [DONE]\r\n\r\n",
            frame("\n\n第二段。", Some("stop"))
        );
        let updates = RefCell::new(Vec::new());
        let publish = |text: &str| updates.borrow_mut().push(text.to_owned());
        for size in [1, 2, 3, 7, source.len()] {
            let mut parser = OpenAiStream::new(false);
            for bytes in source.as_bytes().chunks(size) {
                parser.push(bytes, &publish).unwrap();
            }
            assert_eq!(parser.finish(&publish).unwrap(), "你好 🪞\n\n第二段。");
        }
        assert!(updates
            .borrow()
            .iter()
            .all(|text| !text.contains("REASONING")));
    }

    #[test]
    fn sse_accepts_done_or_stop_but_never_an_unterminated_partial_answer() {
        let publish = |_: &str| {};
        for suffix in ["data: [DONE]\n\n", &frame("", Some("stop"))] {
            let mut parser = OpenAiStream::new(false);
            parser
                .push(
                    format!("{}{suffix}", frame("answer", None)).as_bytes(),
                    &publish,
                )
                .unwrap();
            assert_eq!(parser.finish(&publish).unwrap(), "answer");
        }
        for source in [
            frame("partial", None),
            format!("{}data: [DONE]", frame("partial", None)),
        ] {
            let mut parser = OpenAiStream::new(false);
            parser.push(source.as_bytes(), &publish).unwrap();
            assert!(parser.finish(&publish).unwrap_err().contains("中断"));
        }
        let parser = OpenAiStream::new(false);
        assert!(parser.finish(&publish).is_err());
        for delta in ["null", "{}"] {
            let mut parser = OpenAiStream::new(false);
            let source = format!(
                "{}data: {{\"choices\":[{{\"delta\":{delta},\"finish_reason\":\"stop\"}}]}}\n\n",
                frame("answer", None)
            );
            parser.push(source.as_bytes(), &publish).unwrap();
            assert_eq!(parser.finish(&publish).unwrap(), "answer");
        }
    }

    #[test]
    fn sse_redacts_error_events_and_rejects_filtered_tool_or_malformed_finishes() {
        let publish = |_: &str| {};
        let private = "FIXTURE-KEY-AND-RAW-SOURCE";
        let failures = [
            format!("event: error\ndata: {private}\n\n"),
            format!("data: {{\"error\":{{\"message\":\"{private}\"}}}}\n\n"),
            format!(
                "data: {{\"base_resp\":{{\"status_code\":1004,\"status_msg\":\"{private}\"}}}}\n\n"
            ),
            "data: {broken-json}\n\n".into(),
            frame("never accepted", Some("length")),
            frame("never accepted", Some("content_filter")),
            frame("never accepted", Some("tool_calls")),
            "data: {\"choices\":[{\"delta\":{\"content\":[\"unexpected\"]}}]}\n\n".into(),
            "data: {\"choices\":[{\"delta\":{\"refusal\":\"private refusal\"}}]}\n\n".into(),
        ];
        for failure in failures {
            let mut parser = OpenAiStream::new(false);
            parser
                .push(frame("visible partial", None).as_bytes(), &publish)
                .unwrap();
            let error = parser.push(failure.as_bytes(), &publish).unwrap_err();
            assert!(!error.contains(private));
            assert!(!error.contains("visible partial"));
            assert!(!error.contains("private refusal"));
        }
        let mut parser = OpenAiStream::new(false);
        assert!(parser.push(b"data: \xff\n\n", &publish).is_err());
        let mut parser = OpenAiStream::new(false);
        parser
            .push(frame("done", Some("stop")).as_bytes(), &publish)
            .unwrap();
        assert!(parser
            .push(frame("late content", None).as_bytes(), &publish)
            .is_err());
    }

    #[test]
    fn sse_reasoning_only_is_empty_and_total_response_budget_includes_reasoning() {
        let mut parser = OpenAiStream::new(false);
        let publish = |_: &str| panic!("reasoning is never progress");
        parser.push(b"data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"private reasoning\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n", &publish).unwrap();
        assert!(parser.finish(&publish).is_err());
        let mut parser = OpenAiStream::new(false);
        let source = vec![b':'; MAX_RESPONSE + 1];
        assert!(parser
            .push(&source, &publish)
            .unwrap_err()
            .contains("2 MiB"));
    }

    #[test]
    fn minimax_inline_reasoning_is_isolated_across_chunks_without_rewriting_other_providers() {
        let updates = RefCell::new(Vec::new());
        let publish = |text: &str| updates.borrow_mut().push(text.to_owned());
        let mut parser = OpenAiStream::new(true);
        for fragment in [
            "<",
            "thi",
            "nk>",
            "PRIVATE-REASONING",
            "</thi",
            "nk>\n",
            "最终",
            "译文",
        ] {
            parser
                .push(frame(fragment, None).as_bytes(), &publish)
                .unwrap();
        }
        parser
            .push(frame("", Some("stop")).as_bytes(), &publish)
            .unwrap();
        assert_eq!(parser.finish(&publish).unwrap(), "最终译文");
        assert_eq!(*updates.borrow(), ["最终", "最终译文"]);
        let literal = "<think>literal translated XML</think>";
        let mut parser = OpenAiStream::new(false);
        parser
            .push(frame(literal, Some("stop")).as_bytes(), &|_| {})
            .unwrap();
        assert_eq!(parser.finish(&|_| {}).unwrap(), literal);
        assert!(split_minimax_answer("<think>unfinished reasoning").is_err());
        assert_eq!(
            split_minimax_answer("<think>private</think>\nanswer").unwrap(),
            "answer"
        );
    }
}
