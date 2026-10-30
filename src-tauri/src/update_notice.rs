//! Free, opt-in release notices, not an installer/updater. Only public GitHub
//! metadata is requested; no text, screenshots, credentials or arbitrary URLs.
use semver::Version;
use serde::{Deserialize, Serialize};
use std::{cmp::Ordering, path::PathBuf, time::Duration};

const RELEASES_API: &str =
    "https://api.github.com/repos/Blueeeecho/EchoLingo/releases?per_page=100";
const MAX_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const DAY_MS: u64 = 24 * 60 * 60 * 1000;
const MANUAL_COOLDOWN_MS: u64 = 60 * 1000;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Release {
    version: String,
    prerelease: bool,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", default)]
struct Cache {
    last_attempt: Option<u64>,
    checked_at: Option<u64>,
    failed: bool,
    releases: Vec<Release>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    available: Option<Release>,
    checked_at: Option<u64>,
    failed: bool,
}

fn version(tag: &str) -> Option<Version> {
    if tag.len() > 128 {
        return None;
    }
    Version::parse(tag.strip_prefix('v').unwrap_or(tag)).ok()
}

fn parse_releases(bytes: &[u8]) -> Result<Vec<Release>, ()> {
    if bytes.len() > MAX_RESPONSE_BYTES {
        return Err(());
    }
    let entries: Vec<serde_json::Value> = serde_json::from_slice(bytes).map_err(|_| ())?;
    if entries.len() > 100 {
        return Err(());
    }
    Ok(entries
        .iter()
        .filter_map(|entry| {
            // Missing/malformed safety fields are not treated as a public stable release.
            if entry.get("draft")?.as_bool()? {
                return None;
            }
            let prerelease = entry.get("prerelease")?.as_bool()?;
            let parsed = version(entry.get("tag_name")?.as_str()?)?;
            Some(Release {
                prerelease: prerelease || !parsed.pre.is_empty(),
                version: parsed.to_string(),
            })
        })
        .collect())
}

impl Cache {
    fn status(&self, current: &str, include_prereleases: bool) -> Status {
        let available = version(current).and_then(|current| {
            self.releases
                .iter()
                .filter_map(|release| {
                    let parsed = version(&release.version)?;
                    if (!include_prereleases && (release.prerelease || !parsed.pre.is_empty()))
                        || parsed.cmp_precedence(&current) != Ordering::Greater
                    {
                        return None;
                    }
                    Some((release, parsed))
                })
                .max_by(|(_, a), (_, b)| a.cmp_precedence(b))
                .map(|(release, _)| release.clone())
        });
        Status {
            available,
            checked_at: self.checked_at,
            failed: self.failed,
        }
    }

    fn due(&self, now: u64, manual: bool, automatic_enabled: bool) -> bool {
        if !manual && !automatic_enabled {
            return false;
        }
        let interval = if manual { MANUAL_COOLDOWN_MS } else { DAY_MS };
        self.last_attempt
            .is_none_or(|last| now.saturating_sub(last) >= interval)
    }

    fn complete(&mut self, result: Result<Vec<Release>, ()>, now: u64) {
        self.last_attempt = Some(now);
        self.failed = result.is_err();
        if let Ok(releases) = result {
            self.checked_at = Some(now);
            self.releases = releases;
        }
        // Failure does not discard a previously discovered version.
    }
}

pub struct Controller {
    cache: tokio::sync::Mutex<Cache>,
    path: PathBuf,
}

impl Controller {
    pub fn new(path: PathBuf) -> Self {
        // Only bounded, non-secret version/cadence data is persisted.
        let cache = std::fs::metadata(&path)
            .ok()
            .filter(|metadata| metadata.len() <= 32 * 1024)
            .and_then(|_| std::fs::read(&path).ok())
            .and_then(|bytes| serde_json::from_slice::<Cache>(&bytes).ok())
            .filter(|cache| cache.releases.len() <= 100)
            .unwrap_or_default();
        Self {
            cache: tokio::sync::Mutex::new(cache),
            path,
        }
    }

    pub async fn status(&self, current: &str, include_prereleases: bool) -> Status {
        self.cache.lock().await.status(current, include_prereleases)
    }

    pub async fn check(
        &self,
        current: &str,
        include_prereleases: bool,
        manual: bool,
        automatic_enabled: bool,
    ) -> Status {
        // Serialize all callers. A double-click, reload or simultaneous automatic
        // check observes the first result instead of issuing another request.
        let mut cache = self.cache.lock().await;
        let started = crate::now();
        if !cache.due(started, manual, automatic_enabled) {
            return cache.status(current, include_prereleases);
        }
        cache.last_attempt = Some(started);
        // Persist before networking: restarting after a failure cannot poll GitHub.
        let persisted = crate::write_json(&self.path, &*cache).is_ok();
        if !manual && !persisted {
            // Fail closed: without durable cadence an automatic check could
            // run on every restart. Explicit manual checks remain available.
            cache.failed = true;
            return cache.status(current, include_prereleases);
        }
        let result = fetch_releases().await;
        cache.complete(result, crate::now());
        let _ = crate::write_json(&self.path, &*cache);
        cache.status(current, include_prereleases)
    }
}

async fn fetch_releases() -> Result<Vec<Release>, ()> {
    // A separate credential-free client never inherits a provider's headers.
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(8))
        .connect_timeout(Duration::from_secs(4))
        .redirect(reqwest::redirect::Policy::none())
        .user_agent("EchoLingo-update-notice")
        .build()
        .map_err(|_| ())?;
    let mut response = client
        .get(RELEASES_API)
        .header("Accept", "application/vnd.github+json")
        .header("X-GitHub-Api-Version", "2022-11-28")
        .send()
        .await
        .map_err(|_| ())?;
    if response.status() != reqwest::StatusCode::OK
        || response
            .content_length()
            .is_some_and(|size| size > MAX_RESPONSE_BYTES as u64)
    {
        return Err(());
    }
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|_| ())? {
        if bytes.len().saturating_add(chunk.len()) > MAX_RESPONSE_BYTES {
            return Err(());
        }
        bytes.extend_from_slice(&chunk);
    }
    parse_releases(&bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn releases(entries: serde_json::Value) -> Cache {
        Cache {
            releases: parse_releases(&serde_json::to_vec(&entries).unwrap()).unwrap(),
            ..Cache::default()
        }
    }
    fn public(tag: &str) -> serde_json::Value {
        json!({"tag_name": tag, "draft": false, "prerelease": false})
    }
    fn selected(cache: &Cache, current: &str, beta: bool) -> Option<String> {
        cache
            .status(current, beta)
            .available
            .map(|release| release.version)
    }

    #[test]
    fn semver_numeric_prerelease_and_build_precedence() {
        let cache = releases(json!([
            public("v0.2.0-beta.2"),
            public("0.2.0-beta.11"),
            public("0.2.0-beta.9")
        ]));
        assert_eq!(
            selected(&cache, "0.2.0-beta.10", true).as_deref(),
            Some("0.2.0-beta.11")
        );
        assert_eq!(selected(&cache, "0.2.0", true), None);
        assert_eq!(selected(&cache, "0.1.0", false), None);
        let cache = releases(json!([public("0.2.9"), public("0.2.10"), public("0.2.0")]));
        assert_eq!(selected(&cache, "0.2.0", false).as_deref(), Some("0.2.10"));
        let cache = releases(json!([public("0.2.0+new")]));
        assert_eq!(selected(&cache, "0.2.0+old", true), None);
    }

    #[test]
    fn internal_plain_tag_obeys_github_flag_and_drafts_are_ignored() {
        let cache = releases(
            json!([public("0.1.0"), {"tag_name":"0.2.0","draft":false,"prerelease":true}, {"tag_name":"9.0.0","draft":true,"prerelease":false}]),
        );
        assert_eq!(
            selected(&cache, "0.1.0-beta.2.2", true).as_deref(),
            Some("0.2.0")
        );
        assert_eq!(selected(&cache, "0.1.0", false), None);
        assert_eq!(selected(&cache, "0.2.0", true), None);
        assert!(cache.status("0.1.0", true).available.unwrap().prerelease);
    }

    #[test]
    fn malformed_tags_fields_and_payload_are_rejected() {
        for tag in [
            "",
            "v",
            "0.2",
            "00.2.0",
            "0.2.0-beta.01",
            " 0.2.0",
            "0.2.0\n",
            "release/0.2.0",
            "0.2.0<script>",
            "18446744073709551616.0.0",
        ] {
            assert_eq!(
                selected(&releases(json!([public(tag)])), "0.1.0", true),
                None,
                "{tag}"
            );
        }
        assert_eq!(
            selected(
                &releases(
                    json!([{"tag_name":"2.0.0"}, {"tag_name":"2.0.0","draft":"false","prerelease":false}, null])
                ),
                "0.1.0",
                true
            ),
            None
        );
        assert_eq!(
            selected(&releases(json!([public("2.0.0")])), "unknown", true),
            None
        );
        assert!(parse_releases(b"{\"message\":\"rate limited\"}").is_err());
        assert!(parse_releases(&vec![b' '; MAX_RESPONSE_BYTES + 1]).is_err());
        assert!(parse_releases(&serde_json::to_vec(&vec![public("1.0.0"); 101]).unwrap()).is_err());
    }

    #[test]
    fn dates_names_links_and_assets_never_control_selection_or_navigation() {
        let cache = releases(json!([
            {"tag_name":"0.2.0","draft":false,"prerelease":false,"published_at":"2099-01-01T00:00:00Z","name":"<script>"},
            {"tag_name":"0.3.0","draft":false,"prerelease":false,"published_at":"invalid","html_url":"https://evil.invalid","assets":[{"browser_download_url":"file:///evil.exe"}]}
        ]));
        assert_eq!(selected(&cache, "0.1.0", true).as_deref(), Some("0.3.0"));
        // Date is deliberately not used as a version, and no API-supplied URL,
        // release body or asset survives parsing or reaches the frontend.
        let encoded = serde_json::to_string(&cache.status("0.1.0", true)).unwrap();
        assert!(!encoded.contains("evil"));
        assert!(!encoded.contains("script"));
        assert!(!encoded.contains("published"));
    }

    #[test]
    fn defaults_off_daily_bound_manual_cooldown_and_clock_rollback() {
        let mut cache = Cache::default();
        assert!(!cache.due(100, false, false));
        assert!(cache.due(100, true, false));
        cache.complete(Ok(vec![]), DAY_MS);
        assert!(!cache.due(DAY_MS - 1, true, true));
        assert!(!cache.due(DAY_MS + MANUAL_COOLDOWN_MS - 1, true, false));
        assert!(cache.due(DAY_MS + MANUAL_COOLDOWN_MS, true, false));
        assert!(!cache.due(2 * DAY_MS - 1, false, true));
        assert!(cache.due(2 * DAY_MS, false, true));
    }

    #[tokio::test]
    async fn cached_status_and_disabled_check_never_need_network() {
        let path = std::env::temp_dir().join(format!(
            "echolingo-update-cache-{}-{}.json",
            std::process::id(),
            crate::now()
        ));
        let mut cache = releases(json!([public("0.3.0")]));
        cache.checked_at = Some(42);
        crate::write_json(&path, &cache).unwrap();
        let controller = Controller::new(path.clone());
        let status = controller.check("0.2.0", true, false, false).await;
        assert_eq!(status.available.unwrap().version, "0.3.0");
        assert_eq!(status.checked_at, Some(42));
        assert!(controller.cache.lock().await.last_attempt.is_none());
        assert!(controller.status("0.3.0", true).await.available.is_none());
        std::fs::write(&path, b"invalid cache").unwrap();
        assert!(Controller::new(path.clone())
            .status("0.2.0", true)
            .await
            .checked_at
            .is_none());
        std::fs::remove_file(path).unwrap();
    }

    #[tokio::test]
    async fn automatic_check_without_writable_cadence_cache_fails_closed() {
        let path = std::env::temp_dir()
            .join(format!(
                "echolingo-missing-update-cache-{}-{}",
                std::process::id(),
                crate::now()
            ))
            .join("cache.json");
        let controller = Controller::new(path);
        let status = controller.check("0.2.0", true, false, true).await;
        assert!(status.failed);
        assert!(status.checked_at.is_none());
        assert!(controller.cache.lock().await.last_attempt.is_some());
    }

    #[test]
    fn offline_failure_keeps_cached_notice_and_throttles_retry_across_restarts() {
        let mut cache = releases(json!([public("0.3.0")]));
        cache.checked_at = Some(1);
        cache.complete(Err(()), DAY_MS);
        let cache: Cache = serde_json::from_slice(&serde_json::to_vec(&cache).unwrap()).unwrap();
        assert!(cache.status("0.2.0", true).failed);
        assert_eq!(cache.status("0.2.0", true).checked_at, Some(1));
        assert_eq!(selected(&cache, "0.2.0", true).as_deref(), Some("0.3.0"));
        assert!(!cache.due(DAY_MS + 1, false, true));
        assert_eq!(selected(&cache, "0.3.0", true), None);
    }
}
