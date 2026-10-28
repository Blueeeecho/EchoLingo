//! Process-memory credential results, scoped to an OS account and protocol/origin.
//!
//! This module never accesses the OS store, disk, logs or application events.
//! Callers supply a loader with already-redacted errors and must never serialize
//! a cached value. In particular, passive settings metadata must not call a
//! loader. `T = String` can represent a missing credential with an empty string.
use std::collections::HashMap;
use std::sync::{Condvar, Mutex, MutexGuard};

const CACHE_ERROR: &str = "凭据缓存状态异常，请重新启动应用";
const CHANGED: &str = "凭据已更改，本次读取已取消，请重试";
const ABANDONED: &str = "系统凭据读取未完成，请在服务设置中重新保存凭据";

// Deliberately no Debug/Serialize implementations on keys, cache or outcomes.
#[derive(Clone, PartialEq, Eq, Hash)]
pub struct CredentialKey {
    account: String,
    scope: String,
}

impl CredentialKey {
    pub fn new(account: impl Into<String>, scope: impl Into<String>) -> Self {
        Self {
            account: account.into(),
            scope: scope.into(),
        }
    }
}

enum Entry<T> {
    Loading { token: u64 },
    Ready(Result<T, String>),
}

struct CacheState<T> {
    entries: HashMap<CredentialKey, Entry<T>>,
    account_revisions: HashMap<String, u64>,
    deleted_accounts: HashMap<String, T>,
    next_token: u64,
}

impl<T> Default for CacheState<T> {
    fn default() -> Self {
        Self {
            entries: HashMap::new(),
            account_revisions: HashMap::new(),
            deleted_accounts: HashMap::new(),
            next_token: 0,
        }
    }
}

pub struct CredentialCache<T: Clone> {
    state: Mutex<CacheState<T>>,
    changed: Condvar,
}

impl<T: Clone> Default for CredentialCache<T> {
    fn default() -> Self {
        Self {
            state: Mutex::new(CacheState::default()),
            changed: Condvar::new(),
        }
    }
}

impl<T: Clone> CredentialCache<T> {
    fn lock(&self) -> Result<MutexGuard<'_, CacheState<T>>, String> {
        self.state.lock().map_err(|_| CACHE_ERROR.to_owned())
    }

    /// Coalesce simultaneous reads of one account/scope. All outcomes, including
    /// denied reads and missing credentials, remain cached until an explicit
    /// credential action calls store/invalidate/delete. Different keys can load
    /// concurrently; the OS loader never runs while the cache mutex is held.
    pub fn get_or_load(
        &self,
        key: &CredentialKey,
        loader: impl FnOnce() -> Result<T, String>,
    ) -> Result<T, String> {
        let mut state = self.lock()?;
        let revision = state
            .account_revisions
            .get(&key.account)
            .copied()
            .unwrap_or(0);
        loop {
            let current_revision = state
                .account_revisions
                .get(&key.account)
                .copied()
                .unwrap_or(0);
            if revision != current_revision {
                return Err(CHANGED.into());
            }
            if let Some(missing) = state.deleted_accounts.get(&key.account) {
                return Ok(missing.clone());
            }
            match state.entries.get(key) {
                Some(Entry::Ready(result)) => return result.clone(),
                Some(Entry::Loading { .. }) => {
                    state = self
                        .changed
                        .wait(state)
                        .map_err(|_| CACHE_ERROR.to_owned())?;
                }
                None => break,
            }
        }
        let token = state.next_token.checked_add(1).ok_or(CACHE_ERROR)?;
        state.next_token = token;
        state.entries.insert(key.clone(), Entry::Loading { token });
        drop(state);

        // Unwinding through a user-supplied loader must wake waiters and must not
        // cause an endless Loading state or an automatic authorization retry.
        let mut pending = PendingLoad {
            cache: self,
            key,
            token,
            armed: true,
        };
        let loaded = loader();
        let mut state = self.lock()?;
        let owns_slot = matches!(state.entries.get(key), Some(Entry::Loading { token: current }) if *current == token);
        if owns_slot {
            state
                .entries
                .insert(key.clone(), Entry::Ready(loaded.clone()));
            pending.armed = false;
            self.changed.notify_all();
            return loaded;
        }
        // Save/delete/invalidate won the race. Discard the older result, even
        // for its initiating caller; it may not revive or use the old secret.
        pending.armed = false;
        Err(CHANGED.into())
    }

    /// Memory-only inspection. None also covers an in-flight read. This must
    /// not be exposed through IPC as a credential-bearing value.
    pub fn peek(&self, key: &CredentialKey) -> Result<Option<Result<T, String>>, String> {
        let state = self.lock()?;
        if let Some(missing) = state.deleted_accounts.get(&key.account) {
            return Ok(Some(Ok(missing.clone())));
        }
        Ok(match state.entries.get(key) {
            Some(Entry::Ready(result)) => Some(result.clone()),
            _ => None,
        })
    }

    /// Call only after an explicit OS credential save succeeds. Publishing a
    /// replacement invalidates every previous scope of that OS account. It also
    /// supersedes denied/missing results and any older in-flight load.
    pub fn store(&self, key: &CredentialKey, value: Result<T, String>) -> Result<(), String> {
        let mut state = self.lock()?;
        Self::advance_account(&mut state, &key.account)?;
        state
            .entries
            .retain(|old_key, _| old_key.account != key.account);
        state.deleted_accounts.remove(&key.account);
        state.entries.insert(key.clone(), Entry::Ready(value));
        self.changed.notify_all();
        Ok(())
    }

    /// An explicit credential retry/configuration action permits the next read
    /// to call the OS loader again. Never call this during a passive refresh,
    /// normal translation, a failed read or automatic error recovery.
    pub fn invalidate_account(&self, account: &str) -> Result<(), String> {
        let mut state = self.lock()?;
        Self::advance_account(&mut state, account)?;
        state.entries.retain(|key, _| key.account != account);
        state.deleted_accounts.remove(account);
        self.changed.notify_all();
        Ok(())
    }

    /// Explicit Settings retry, checked and invalidated in one ordering
    /// boundary. A ready replacement cannot be erased by an earlier observed
    /// failure, and a concurrent Loading slot must not start a second OS read.
    /// The predicate must be pure and may not call back into this cache.
    pub fn retry_if(
        &self,
        key: &CredentialKey,
        unavailable: impl FnOnce(&Result<T, String>) -> bool,
    ) -> Result<bool, String> {
        let mut state = self.lock()?;
        let retry = if let Some(missing) = state.deleted_accounts.get(&key.account) {
            unavailable(&Ok(missing.clone()))
        } else if let Some(Entry::Ready(value)) = state.entries.get(key) {
            unavailable(value)
        } else {
            false
        };
        if retry {
            Self::advance_account(&mut state, &key.account)?;
            state
                .entries
                .retain(|old_key, _| old_key.account != key.account);
            state.deleted_accounts.remove(&key.account);
            self.changed.notify_all();
        }
        Ok(retry)
    }

    /// Call after successful OS deletion (including NoEntry). Account-wide
    /// negative caching suppresses future reads even through a different scope,
    /// and prevents a load started before deletion from reviving the old value.
    pub fn delete_account(&self, account: &str, missing: T) -> Result<(), String> {
        let mut state = self.lock()?;
        Self::advance_account(&mut state, account)?;
        state.entries.retain(|key, _| key.account != account);
        state.deleted_accounts.insert(account.into(), missing);
        self.changed.notify_all();
        Ok(())
    }

    fn advance_account(state: &mut CacheState<T>, account: &str) -> Result<(), String> {
        let revision = state.next_token.checked_add(1).ok_or(CACHE_ERROR)?;
        state.next_token = revision;
        state.account_revisions.insert(account.into(), revision);
        Ok(())
    }
}

struct PendingLoad<'a, T: Clone> {
    cache: &'a CredentialCache<T>,
    key: &'a CredentialKey,
    token: u64,
    armed: bool,
}

impl<T: Clone> Drop for PendingLoad<'_, T> {
    fn drop(&mut self) {
        if !self.armed {
            return;
        }
        if let Ok(mut state) = self.cache.state.lock() {
            let owns_slot = matches!(state.entries.get(self.key), Some(Entry::Loading { token }) if *token == self.token);
            if owns_slot {
                state
                    .entries
                    .insert(self.key.clone(), Entry::Ready(Err(ABANDONED.into())));
            }
        }
        self.cache.changed.notify_all();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::{mpsc, Arc, Barrier};
    use std::time::Duration;

    fn key() -> CredentialKey {
        CredentialKey::new("translation-fixture", "openai|https://supplier.example")
    }

    #[test]
    fn repeated_success_missing_and_denied_reads_are_cached_without_reprompting() {
        for outcome in [
            Ok("fixture-only".to_owned()),
            Ok(String::new()),
            Err("授权被拒绝".into()),
        ] {
            let cache = CredentialCache::<String>::default();
            let reads = AtomicUsize::new(0);
            for _ in 0..6 {
                let result = cache.get_or_load(&key(), || {
                    reads.fetch_add(1, Ordering::SeqCst);
                    outcome.clone()
                });
                assert_eq!(result, outcome);
            }
            assert_eq!(reads.load(Ordering::SeqCst), 1);
            assert_eq!(cache.peek(&key()).unwrap(), Some(outcome));
        }
    }

    #[test]
    fn concurrent_reads_share_one_loader_and_one_denied_outcome() {
        for denied in [false, true] {
            let cache = Arc::new(CredentialCache::<String>::default());
            let reads = Arc::new(AtomicUsize::new(0));
            let start = Arc::new(Barrier::new(13));
            let workers: Vec<_> = (0..12)
                .map(|_| {
                    let cache = cache.clone();
                    let reads = reads.clone();
                    let start = start.clone();
                    std::thread::spawn(move || {
                        start.wait();
                        cache.get_or_load(&key(), || {
                            reads.fetch_add(1, Ordering::SeqCst);
                            std::thread::sleep(Duration::from_millis(15));
                            if denied {
                                Err("授权被拒绝".into())
                            } else {
                                Ok("fixture-only".into())
                            }
                        })
                    })
                })
                .collect();
            start.wait();
            let expected = if denied {
                Err("授权被拒绝".into())
            } else {
                Ok("fixture-only".into())
            };
            for worker in workers {
                assert_eq!(worker.join().unwrap(), expected);
            }
            assert_eq!(reads.load(Ordering::SeqCst), 1);
        }
    }

    #[test]
    fn account_protocol_origin_and_ocr_namespaces_cannot_share_values() {
        let cache = CredentialCache::<usize>::default();
        let keys = [
            CredentialKey::new("service-one", "openai|https://one.example"),
            CredentialKey::new("service-two", "openai|https://one.example"),
            CredentialKey::new("service-one", "deepl|https://one.example"),
            CredentialKey::new("service-one", "openai|https://two.example"),
            CredentialKey::new(
                "ocr-service-one-openai-vision",
                "openai-vision|https://one.example",
            ),
        ];
        for (index, key) in keys.iter().enumerate() {
            assert_eq!(cache.get_or_load(key, || Ok(index)), Ok(index));
        }
        for (index, key) in keys.iter().enumerate() {
            assert_eq!(
                cache.get_or_load(key, || panic!("cached scope must not reload")),
                Ok(index)
            );
        }
    }

    #[test]
    fn loading_one_account_does_not_block_different_keys_or_passive_inspection() {
        let cache = Arc::new(CredentialCache::<String>::default());
        let (started, start_notice) = mpsc::channel();
        let (release, gate) = mpsc::channel();
        let task_cache = cache.clone();
        let worker = std::thread::spawn(move || {
            task_cache.get_or_load(&key(), || {
                started.send(()).unwrap();
                gate.recv_timeout(Duration::from_secs(2)).unwrap();
                Ok("fixture-only".into())
            })
        });
        start_notice.recv_timeout(Duration::from_secs(2)).unwrap();
        assert_eq!(cache.peek(&key()).unwrap(), None);
        let unrelated = CredentialKey::new("another-service", "openai|https://another.example");
        assert_eq!(
            cache.get_or_load(&unrelated, || Ok("unrelated-fixture".into())),
            Ok("unrelated-fixture".into())
        );
        release.send(()).unwrap();
        assert_eq!(worker.join().unwrap(), Ok("fixture-only".into()));
    }

    #[test]
    fn explicit_successful_save_replaces_denied_cached_values_and_old_scope() {
        let cache = CredentialCache::<String>::default();
        let old_scope = CredentialKey::new("translation-fixture", "deepl|https://old.example");
        cache
            .get_or_load(&old_scope, || Ok("old-fixture".into()))
            .unwrap();
        assert!(cache
            .get_or_load(&key(), || Err("授权被拒绝".into()))
            .is_err());
        cache.store(&key(), Ok("saved-fixture".into())).unwrap();
        assert_eq!(cache.peek(&old_scope).unwrap(), None);
        assert_eq!(
            cache.get_or_load(&key(), || panic!("saved value must not reread")),
            Ok("saved-fixture".into())
        );
        cache
            .store(&key(), Ok("replacement-fixture".into()))
            .unwrap();
        assert_eq!(
            cache.get_or_load(&key(), || panic!("replacement must not reread")),
            Ok("replacement-fixture".into())
        );
    }

    #[test]
    fn explicit_invalidation_allows_exactly_one_new_read() {
        let cache = CredentialCache::<String>::default();
        let reads = AtomicUsize::new(0);
        assert!(cache
            .get_or_load(&key(), || Err("授权被拒绝".into()))
            .is_err());
        cache.invalidate_account("unrelated-account").unwrap();
        assert!(cache
            .get_or_load(&key(), || panic!(
                "unrelated action cannot retry denied read"
            ))
            .is_err());
        cache.invalidate_account("translation-fixture").unwrap();
        for _ in 0..3 {
            assert_eq!(
                cache.get_or_load(&key(), || {
                    reads.fetch_add(1, Ordering::SeqCst);
                    Ok("retry-fixture".into())
                }),
                Ok("retry-fixture".into())
            );
        }
        assert_eq!(reads.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn save_delete_and_invalidate_cannot_be_undone_by_an_inflight_load() {
        for action in ["save", "delete", "invalidate"] {
            let cache = Arc::new(CredentialCache::<String>::default());
            let (started, start_notice) = mpsc::channel();
            let (release, gate) = mpsc::channel();
            let task_cache = cache.clone();
            let worker = std::thread::spawn(move || {
                task_cache.get_or_load(&key(), || {
                    started.send(()).unwrap();
                    gate.recv_timeout(Duration::from_secs(2)).unwrap();
                    Ok("outdated-fixture".into())
                })
            });
            start_notice.recv_timeout(Duration::from_secs(2)).unwrap();
            match action {
                "save" => cache.store(&key(), Ok("new-fixture".into())).unwrap(),
                "delete" => cache
                    .delete_account("translation-fixture", String::new())
                    .unwrap(),
                _ => {
                    cache.invalidate_account("translation-fixture").unwrap();
                    assert_eq!(
                        cache.get_or_load(&key(), || Ok("new-fixture".into())),
                        Ok("new-fixture".into())
                    );
                }
            }
            release.send(()).unwrap();
            assert_eq!(worker.join().unwrap().unwrap_err(), CHANGED);
            let expected = if action == "delete" {
                String::new()
            } else {
                "new-fixture".into()
            };
            assert_eq!(
                cache.get_or_load(&key(), || panic!(
                    "stale load must not replace published state"
                )),
                Ok(expected)
            );
        }
    }

    #[test]
    fn deletion_suppresses_every_scope_until_explicit_save_or_retry() {
        let cache = CredentialCache::<String>::default();
        let other_scope = CredentialKey::new("translation-fixture", "openai|https://other.example");
        cache.store(&key(), Ok("fixture-only".into())).unwrap();
        cache
            .delete_account("translation-fixture", String::new())
            .unwrap();
        for key in [&key(), &other_scope] {
            assert_eq!(
                cache.get_or_load(key, || panic!("deleted account must not reread")),
                Ok(String::new())
            );
        }
        cache.store(&key(), Ok("saved-fixture".into())).unwrap();
        assert_eq!(
            cache.get_or_load(&key(), || panic!("saved value must not reread")),
            Ok("saved-fixture".into())
        );
    }

    #[test]
    fn loader_unwind_never_leaves_loading_or_reprompts_automatically() {
        let cache = CredentialCache::<String>::default();
        let unwind = std::panic::catch_unwind(|| {
            cache.get_or_load(&key(), || panic!("synthetic loader unwind"))
        });
        assert!(unwind.is_err());
        assert_eq!(
            cache.get_or_load(&key(), || panic!("abandoned read must not retry")),
            Err(ABANDONED.into())
        );
        cache.store(&key(), Ok("saved-fixture".into())).unwrap();
        assert_eq!(
            cache.get_or_load(&key(), || panic!("saved value must not reread")),
            Ok("saved-fixture".into())
        );
    }

    #[test]
    fn atomic_retry_preserves_loading_and_a_successful_replacement_after_a_stale_peek() {
        let cache = Arc::new(CredentialCache::<String>::default());
        let unavailable =
            |value: &Result<String, String>| value.as_ref().map_or(true, |value| value.is_empty());
        cache.store(&key(), Err("fixture-denied".into())).unwrap();
        assert!(cache.retry_if(&key(), unavailable).unwrap());
        assert!(!cache.retry_if(&key(), unavailable).unwrap()); // No slot yet.
        let (started, start_notice) = mpsc::channel();
        let (release, gate) = mpsc::channel();
        let task_cache = cache.clone();
        let worker = std::thread::spawn(move || {
            task_cache.get_or_load(&key(), || {
                started.send(()).unwrap();
                gate.recv_timeout(Duration::from_secs(2)).unwrap();
                Ok("old-inflight-fixture".into())
            })
        });
        start_notice.recv_timeout(Duration::from_secs(2)).unwrap();
        assert!(!cache.retry_if(&key(), unavailable).unwrap()); // Coalesce, not retry.
        cache.store(&key(), Ok("saved-fixture".into())).unwrap();
        assert!(!cache.retry_if(&key(), unavailable).unwrap());
        release.send(()).unwrap();
        assert_eq!(worker.join().unwrap().unwrap_err(), CHANGED);

        cache
            .store(&key(), Err("fixture-denied-again".into()))
            .unwrap();
        let (peeked, peek_notice) = mpsc::channel();
        let (resume, resume_gate) = mpsc::channel();
        let retry_cache = cache.clone();
        let retry = std::thread::spawn(move || {
            // Reproduce a command that observed failure before another command
            // saved a usable credential. retry_if must inspect the newer state.
            assert!(matches!(retry_cache.peek(&key()).unwrap(), Some(Err(_))));
            peeked.send(()).unwrap();
            resume_gate.recv_timeout(Duration::from_secs(2)).unwrap();
            retry_cache.retry_if(&key(), unavailable)
        });
        peek_notice.recv_timeout(Duration::from_secs(2)).unwrap();
        cache.store(&key(), Ok("latest-fixture".into())).unwrap();
        resume.send(()).unwrap();
        assert!(!retry.join().unwrap().unwrap());
        assert_eq!(
            cache.get_or_load(&key(), || panic!("new successful save must not reload")),
            Ok("latest-fixture".into())
        );

        cache
            .delete_account("translation-fixture", String::new())
            .unwrap();
        assert!(cache.retry_if(&key(), unavailable).unwrap());
        assert_eq!(
            cache.get_or_load(&key(), || Ok("explicit-retry-fixture".into())),
            Ok("explicit-retry-fixture".into())
        );
    }
}
