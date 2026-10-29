//! Only the bundled, pinned CPU engine is executed. No sockets, downloads,
//! credentials, shell expansion or user-configurable executable paths.
use crate::model::{Provider, TranslationResult};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::{
    fs::File,
    io::Read,
    path::{Component, Path, PathBuf},
    process::Stdio,
    time::{Duration, Instant},
};
use tokio::{
    io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader},
    process::{Child, ChildStdin, ChildStdout, Command},
    sync::Mutex,
};

const RESPONSE_LIMIT: usize = 256 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(90);
const RESOURCE_ERROR: &str =
    "离线模型资源缺失或校验失败，请重新安装包含离线翻译的 EchoLingo；不会改用云端服务";
const ENGINE_ERROR: &str = "本机离线翻译未能完成，请缩短原文后重试";

pub struct OfflineTranslation {
    root: PathBuf,
    worker: Mutex<Option<Worker>>,
}

struct Worker {
    _child: Child,
    input: ChildStdin,
    output: BufReader<ChildStdout>,
    sequence: u64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Manifest {
    format_version: u32,
    files: Vec<ResourceFile>,
}
#[derive(Deserialize)]
struct ResourceFile {
    path: String,
    size: u64,
    sha256: String,
}
#[derive(Deserialize)]
struct Answer {
    id: String,
    text: Option<String>,
    error: Option<String>,
}

fn languages(source: &str, target: &str) -> Result<(&'static str, &'static str), String> {
    match (source, target) {
        ("en", "zh" | "zh-Hans") => Ok(("en", "zh")),
        ("zh" | "zh-Hans" | "zh-Hant", "en") => Ok(("zh", "en")),
        // Never silently substitute a Simplified model for a Traditional target,
        // or reinterpret another detected language as English.
        _ => Err("内置离线翻译支持英语与简体中文互译；此语言方向请选择其他翻译服务".into()),
    }
}

fn validate_resources(root: &Path) -> Result<(), String> {
    // A replacement on-disk manifest cannot redefine the trusted model hashes.
    let manifest: Manifest = serde_json::from_str(include_str!(
        "../../resources/offline-translation/manifest.json"
    ))
    .map_err(|_| RESOURCE_ERROR)?;
    if manifest.format_version != 1 || manifest.files.len() != 7 {
        return Err(RESOURCE_ERROR.into());
    }
    for resource in manifest.files {
        let relative = Path::new(&resource.path);
        if !resource.path.starts_with("models/")
            || !relative
                .components()
                .all(|p| matches!(p, Component::Normal(_)))
            || resource.sha256.len() != 64
        {
            return Err(RESOURCE_ERROR.into());
        }
        let path = root.join(relative);
        let mut file = File::open(path).map_err(|_| RESOURCE_ERROR)?;
        if file.metadata().map_err(|_| RESOURCE_ERROR)?.len() != resource.size {
            return Err(RESOURCE_ERROR.into());
        }
        let mut digest = Sha256::new();
        let mut buffer = [0_u8; 64 * 1024];
        loop {
            let count = file.read(&mut buffer).map_err(|_| RESOURCE_ERROR)?;
            if count == 0 {
                break;
            }
            digest.update(&buffer[..count]);
        }
        if format!("{:x}", digest.finalize()) != resource.sha256 {
            return Err(RESOURCE_ERROR.into());
        }
    }
    Ok(())
}

fn parse_answer(bytes: &[u8], id: &str) -> Result<String, String> {
    if bytes.len() > RESPONSE_LIMIT || !bytes.ends_with(b"\n") {
        return Err(ENGINE_ERROR.into());
    }
    let answer: Answer = serde_json::from_slice(bytes).map_err(|_| ENGINE_ERROR)?;
    if answer.id != id || answer.error.is_some() {
        // Native diagnostics may contain input fragments. Only our fixed
        // actionable message crosses the IPC/log boundary.
        return Err(ENGINE_ERROR.into());
    }
    answer
        .text
        .filter(|text| !text.trim().is_empty() && text.len() <= RESPONSE_LIMIT)
        .ok_or_else(|| ENGINE_ERROR.into())
}

impl OfflineTranslation {
    pub fn new(root: PathBuf) -> Self {
        Self {
            root,
            worker: Mutex::new(None),
        }
    }

    async fn spawn(&self) -> Result<Worker, String> {
        #[cfg(all(target_os = "windows", target_arch = "x86_64"))]
        if !std::is_x86_feature_detected!("sse4.1") {
            return Err("内置离线翻译需要支持 SSE4.1 的处理器，请改用你配置的 API 服务".into());
        }
        let root = self.root.clone();
        tokio::task::spawn_blocking(move || validate_resources(&root))
            .await
            .map_err(|_| RESOURCE_ERROR)??;
        let executable = self.root.join("bin").join(if cfg!(windows) {
            "echolingo-offline-engine.exe"
        } else {
            "echolingo-offline-engine"
        });
        let mut command = Command::new(executable);
        command
            .arg("--model-root")
            .arg(self.root.join("models"))
            .current_dir(&self.root)
            .env_clear()
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true);
        #[cfg(target_os = "windows")]
        {
            command.creation_flags(0x08000000); // CREATE_NO_WINDOW
            for name in ["SystemRoot", "WINDIR", "TEMP", "TMP"] {
                if let Some(value) = std::env::var_os(name) {
                    command.env(name, value);
                }
            }
        }
        let mut child = command
            .spawn()
            .map_err(|_| "无法启动内置离线翻译引擎，请确认安装包完整且处理器受支持".to_string())?;
        let input = child.stdin.take().ok_or(ENGINE_ERROR)?;
        let output = BufReader::new(child.stdout.take().ok_or(ENGINE_ERROR)?);
        Ok(Worker {
            _child: child,
            input,
            output,
            sequence: 0,
        })
    }

    async fn translate(&self, text: &str, source: &str, target: &str) -> Result<String, String> {
        let (source, target) = languages(source, target)?;
        if text.trim().is_empty() || text.chars().count() > 20_000 || text.len() > 80_000 {
            return Err("离线翻译原文为空或超过 20,000 字符上限".into());
        }
        let mut slot = self.worker.lock().await;
        // The in-flight future owns the child rather than leaving it in the
        // cache: cancellation, timeout or a protocol failure drops/kills it.
        // Only a complete, matching response returns a worker to the cache.
        let mut worker = match slot.take() {
            Some(worker) => worker,
            None => self.spawn().await?,
        };
        worker.sequence = worker.sequence.wrapping_add(1);
        let id = worker.sequence.to_string();
        let mut request = serde_json::to_vec(&serde_json::json!({
            "id":id,"source":source,"target":target,"text":text
        }))
        .map_err(|_| ENGINE_ERROR)?;
        request.push(b'\n');
        let answer = tokio::time::timeout(REQUEST_TIMEOUT, async {
            worker
                .input
                .write_all(&request)
                .await
                .map_err(|_| ENGINE_ERROR)?;
            worker.input.flush().await.map_err(|_| ENGINE_ERROR)?;
            let mut bytes = Vec::new();
            (&mut worker.output)
                .take((RESPONSE_LIMIT + 1) as u64)
                .read_until(b'\n', &mut bytes)
                .await
                .map_err(|_| ENGINE_ERROR)?;
            parse_answer(&bytes, &id)
        })
        .await
        .map_err(|_| "本机离线翻译超时，请缩短原文后重试".to_string())??;
        *slot = Some(worker);
        Ok(answer)
    }

    pub async fn translate_result(
        &self,
        provider: &Provider,
        text: &str,
        source: &str,
        target: &str,
    ) -> TranslationResult {
        let started = Instant::now();
        let result = self.translate(text, source, target).await;
        TranslationResult {
            provider_id: provider.id.clone(),
            provider_name: provider.name.clone(),
            text: result.as_ref().cloned().unwrap_or_default(),
            error: result.err(),
            elapsed_ms: started.elapsed().as_millis() as u64,
            resolved_languages: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn direction_preserves_the_requested_script_and_never_reinterprets_other_languages() {
        assert_eq!(languages("en", "zh-Hans").unwrap(), ("en", "zh"));
        assert_eq!(languages("zh-Hans", "en").unwrap(), ("zh", "en"));
        assert_eq!(languages("zh-Hant", "en").unwrap(), ("zh", "en"));
        for (source, target) in [
            ("en", "zh-Hant"),
            ("fr", "en"),
            ("auto", "en"),
            ("en", "en"),
        ] {
            assert!(languages(source, target).is_err());
        }
    }

    #[test]
    fn protocol_requires_matching_complete_bounded_results_and_redacts_native_errors() {
        assert_eq!(
            parse_answer(b"{\"id\":\"7\",\"text\":\"hello\\n\\nworld\"}\n", "7").unwrap(),
            "hello\n\nworld"
        );
        for bytes in [
            &b"{\"id\":\"8\",\"text\":\"stale\"}\n"[..],
            &b"{\"id\":\"7\",\"text\":\" \"}\n"[..],
            &b"{\"id\":\"7\",\"text\":\"incomplete\"}"[..],
            &b"{\"id\":\"7\",\"error\":\"PRIVATE INPUT\"}\n"[..],
        ] {
            let error = parse_answer(bytes, "7").unwrap_err();
            assert_eq!(error, ENGINE_ERROR);
            assert!(!error.contains("PRIVATE"));
        }
        assert!(parse_answer(&vec![b'x'; RESPONSE_LIMIT + 1], "7").is_err());
    }

    /// Explicit acceptance only: never replace absent real resources with a mock.
    #[tokio::test]
    #[ignore = "requires the separately built genuine CPU engine and pinned models"]
    async fn real_models_translate_both_directions_reuse_and_cancel_the_native_worker() {
        let root = std::env::var_os("ECHOLINGO_REAL_OFFLINE_RESOURCES")
            .expect("set ECHOLINGO_REAL_OFFLINE_RESOURCES to the actual packaged resources");
        let engine = std::sync::Arc::new(OfflineTranslation::new(PathBuf::from(root)));
        let provider = crate::model::offline_translation_provider(true);
        let english = engine
            .translate_result(
                &provider,
                "The meeting starts at 09:30 tomorrow.",
                "en",
                "zh-Hans",
            )
            .await;
        assert!(english.error.is_none(), "{:?}", english.error);
        assert!(english.text.contains("09:30"));
        assert!(english
            .text
            .chars()
            .any(|c| ('\u{4e00}'..='\u{9fff}').contains(&c)));
        let process = engine.worker.lock().await.as_ref().unwrap()._child.id();
        let chinese = engine
            .translate_result(&provider, "请在明天上午九点之前发送报告。", "zh-Hans", "en")
            .await;
        assert!(chinese.error.is_none(), "{:?}", chinese.error);
        assert!(chinese.text.to_lowercase().contains("report"));
        assert_eq!(
            engine.worker.lock().await.as_ref().unwrap()._child.id(),
            process
        );
        let paragraphs = engine
            .translate_result(
                &provider,
                "First paragraph: save the file.\n\nSecond paragraph: restart the application.",
                "en",
                "zh-Hans",
            )
            .await;
        assert!(paragraphs.error.is_none(), "{:?}", paragraphs.error);
        assert!(paragraphs.text.contains("\n\n"));
        println!(
            "real-model en→zh: {} ({}ms); zh→en: {} ({}ms); paragraphs: {}",
            english.text, english.elapsed_ms, chinese.text, chinese.elapsed_ms, paragraphs.text
        );
        let shared = engine.clone();
        let pending = tokio::spawn(async move {
            shared
                .translate_result(
                    &provider,
                    &"Translate this long paragraph carefully. ".repeat(400),
                    "en",
                    "zh-Hans",
                )
                .await
        });
        let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
        loop {
            if engine.worker.try_lock().is_err() {
                break;
            }
            assert!(
                tokio::time::Instant::now() < deadline,
                "real inference did not start"
            );
            tokio::task::yield_now().await;
        }
        pending.abort();
        assert!(pending.await.unwrap_err().is_cancelled());
        assert!(
            engine.worker.lock().await.is_none(),
            "cancelled worker must never be reused"
        );
        let next = engine
            .translate_result(
                &crate::model::offline_translation_provider(true),
                "Hello, world.",
                "en",
                "zh-Hans",
            )
            .await;
        assert!(next.error.is_none(), "{:?}", next.error);
        assert_ne!(
            engine.worker.lock().await.as_ref().unwrap()._child.id(),
            process
        );
    }

    #[tokio::test]
    async fn missing_models_and_unsupported_direction_fail_without_network_or_credentials() {
        let engine =
            OfflineTranslation::new(std::env::temp_dir().join("echolingo-no-such-model-resources"));
        let provider = crate::model::offline_translation_provider(true);
        let unsupported = engine
            .translate_result(&provider, "hello", "en", "zh-Hant")
            .await;
        assert!(unsupported.text.is_empty());
        assert!(unsupported.error.unwrap().contains("此语言方向"));
        let missing = engine
            .translate_result(&provider, "hello", "en", "zh-Hans")
            .await;
        assert!(missing.text.is_empty());
        assert_eq!(missing.error.as_deref(), Some(RESOURCE_ERROR));
    }
}
