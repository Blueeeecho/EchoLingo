//! Pure shortcut recording and registration policies. The caller serializes
//! access to a gate and resolves an accepted binding ID to its current action.
use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex, RwLock,
};
use std::time::{Duration, Instant};

pub const RECORDING_LEASE: Duration = Duration::from_secs(15);
pub const RELEASE_COOLDOWN: Duration = Duration::from_millis(350);

/// Serialize registration work without making UI commands wait for a worker
/// that may itself be synchronously dispatching an OS call to the UI thread.
#[derive(Default)]
pub struct ShortcutMaintenance(AtomicBool);

pub struct MaintenanceGuard<'a>(&'a AtomicBool);

impl Drop for MaintenanceGuard<'_> {
    fn drop(&mut self) {
        self.0.store(false, Ordering::SeqCst);
    }
}

impl ShortcutMaintenance {
    pub fn try_enter(&self) -> Option<MaintenanceGuard<'_>> {
        self.0
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .ok()
            .map(|_| MaintenanceGuard(&self.0))
    }

    /// Take ownership before checking the lease. Recording admission checks
    /// that ownership under the same gate, so neither ordering can cancel a
    /// live recording or admit one while maintenance is touching native hooks.
    pub fn try_enter_idle(
        &self,
        gate: &Mutex<ShortcutGate>,
        now: Instant,
    ) -> Result<Option<MaintenanceGuard<'_>>, String> {
        let Some(guard) = self.try_enter() else {
            return Ok(None);
        };
        if gate.lock().map_err(|_| "快捷键状态异常")?.is_recording(now) {
            return Ok(None);
        }
        Ok(Some(guard))
    }

    pub fn begin_recording(&self, gate: &Mutex<ShortcutGate>, now: Instant) -> Result<u64, String> {
        let mut gate = gate.lock().map_err(|_| "快捷键状态异常")?;
        if self.0.load(Ordering::SeqCst) {
            return Err("快捷键正在更新，请稍后再录制。".into());
        }
        gate.begin(now)
    }
}

#[cfg(test)]
mod maintenance_tests {
    use super::*;

    #[test]
    fn recording_wins_admission_without_losing_lease_or_held_pair() {
        let maintenance = ShortcutMaintenance::default();
        let gate = Mutex::new(ShortcutGate::default());
        let now = Instant::now();
        let lease = maintenance.begin_recording(&gate, now).unwrap();
        gate.lock().unwrap().observe(7, true, now);
        assert!(maintenance.try_enter_idle(&gate, now).unwrap().is_none());
        assert!(gate.lock().unwrap().matches_recording(lease, now));
        assert_eq!(
            gate.lock().unwrap().observe(7, false, now),
            ShortcutDelivery::Recorded(lease)
        );
        assert!(gate.lock().unwrap().end(lease, now));
        assert!(maintenance.try_enter_idle(&gate, now).unwrap().is_some());
    }

    #[test]
    fn maintenance_wins_admission_and_releases_ownership_on_early_return() {
        let maintenance = ShortcutMaintenance::default();
        let gate = Mutex::new(ShortcutGate::default());
        let now = Instant::now();
        let guard = maintenance.try_enter_idle(&gate, now).unwrap().unwrap();
        // Simulates UI commands arriving while native registration waits for
        // the main thread: admission is nonblocking and the gate is unlocked.
        assert!(gate.try_lock().is_ok());
        assert!(maintenance.try_enter().is_none());
        assert!(maintenance.begin_recording(&gate, now).is_err());
        assert!(!gate.lock().unwrap().is_recording(now));
        drop(guard);
        let lease = maintenance.begin_recording(&gate, now).unwrap();
        assert!(gate.lock().unwrap().matches_recording(lease, now));
    }

    #[test]
    fn expired_recording_allows_maintenance_but_never_rearms_old_press() {
        let maintenance = ShortcutMaintenance::default();
        let gate = Mutex::new(ShortcutGate::default());
        let now = Instant::now();
        let old = maintenance.begin_recording(&gate, now).unwrap();
        gate.lock().unwrap().observe(7, true, now);
        let later = now + RECORDING_LEASE + RELEASE_COOLDOWN;
        let guard = maintenance.try_enter_idle(&gate, later).unwrap().unwrap();
        assert!(!gate.lock().unwrap().end(old, later));
        drop(guard);
        let next = maintenance.begin_recording(&gate, later).unwrap();
        assert!(next > old);
        assert_eq!(
            gate.lock().unwrap().observe(7, false, later),
            ShortcutDelivery::Ignored
        );
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum ShortcutDelivery {
    Ignored,
    Action,
    Recorded(u64),
}

struct Recording {
    id: u64,
    expires: Instant,
}

#[derive(Default)]
pub struct ShortcutGate {
    next_id: u64,
    recording: Option<Recording>,
    cooldown_until: Option<Instant>,
    // Retain held IDs across suppression: an auto-repeat after recording ends
    // must not turn a key held during recording into a fresh allowed press.
    held: HashSet<u32>,
    allowed_pressed: HashSet<u32>,
    recording_pressed: HashSet<u32>,
}

impl ShortcutGate {
    /// Replace any old recording with a new, bounded lease. A stale end request
    /// cannot close this lease, even if another field began recording meanwhile.
    pub fn begin(&mut self, now: Instant) -> Result<u64, String> {
        let Some(id) = self.next_id.checked_add(1) else {
            self.cancel(now);
            return Err("快捷键录入编号已用尽，请重新启动应用".into());
        };
        self.next_id = id;
        self.recording = Some(Recording {
            id,
            expires: now + RECORDING_LEASE,
        });
        self.allowed_pressed.clear();
        self.recording_pressed.clear();
        self.cooldown_until = None;
        Ok(id)
    }

    /// End only the matching live lease. Apply the same release protection when
    /// the recording expires without an explicit frontend end request.
    pub fn end(&mut self, id: u64, now: Instant) -> bool {
        self.expire(now);
        if self.recording.as_ref().is_none_or(|lease| lease.id != id) {
            return false;
        }
        self.recording = None;
        self.suppress_releases(now);
        true
    }

    /// Call for blur/navigation and before a binding update. This invalidates
    /// presses even when no recording lease currently exists.
    pub fn cancel(&mut self, now: Instant) {
        self.recording = None;
        self.suppress_releases(now);
    }

    pub fn is_recording(&mut self, now: Instant) -> bool {
        self.expire(now);
        self.recording.is_some()
    }

    pub fn matches_recording(&mut self, id: u64, now: Instant) -> bool {
        self.expire(now);
        self.recording.as_ref().is_some_and(|lease| lease.id == id)
    }

    /// Feed BOTH event phases. `true` permits one action on this release; a
    /// press/repeat, unmatched release or suppressed event always returns false.
    pub fn allows_release(&mut self, binding: u32, pressed: bool, now: Instant) -> bool {
        self.observe(binding, pressed, now) == ShortcutDelivery::Action
    }

    pub fn observe(&mut self, binding: u32, pressed: bool, now: Instant) -> ShortcutDelivery {
        self.expire(now);
        let blocked = self.recording.is_some() || self.cooldown_until.is_some();
        if pressed {
            let fresh = self.held.insert(binding);
            if fresh && !blocked {
                self.allowed_pressed.insert(binding);
            }
            if fresh && self.recording.is_some() {
                self.recording_pressed.insert(binding);
            }
            return ShortcutDelivery::Ignored;
        }
        self.held.remove(&binding);
        let recorded = self.recording_pressed.remove(&binding);
        let action = self.allowed_pressed.remove(&binding) && !blocked;
        if let Some(lease) = self.recording.as_ref().filter(|_| recorded) {
            ShortcutDelivery::Recorded(lease.id)
        } else if action {
            ShortcutDelivery::Action
        } else {
            ShortcutDelivery::Ignored
        }
    }

    /// Native hooks already own a complete down/up pair. Observe the pair
    /// while the caller holds one gate lock, even if final delivery is later
    /// rejected as stale; no synthetic held key can leak into the next input.
    pub fn observe_pair(&mut self, binding: u32, now: Instant) -> ShortcutDelivery {
        self.observe(binding, true, now);
        self.observe(binding, false, now)
    }

    fn suppress_releases(&mut self, now: Instant) {
        self.allowed_pressed.clear();
        self.recording_pressed.clear();
        self.cooldown_until = Some(now + RELEASE_COOLDOWN);
    }

    fn expire(&mut self, now: Instant) {
        if let Some(expired_at) = self
            .recording
            .as_ref()
            .filter(|lease| now >= lease.expires)
            .map(|lease| lease.expires)
        {
            self.recording = None;
            self.allowed_pressed.clear();
            self.recording_pressed.clear();
            // The lease really ends at its deadline, even if the next event is
            // much later. Clearing allowed presses also rejects a held key's
            // late release, without swallowing a fresh press after long idle.
            self.cooldown_until = Some(expired_at + RELEASE_COOLDOWN);
        }
        if self.cooldown_until.is_some_and(|until| now >= until) {
            self.cooldown_until = None;
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShortcutRoute {
    pub action: String,
    pub combo: String,
}

pub type ShortcutRouteSnapshot = Arc<BTreeMap<u32, ShortcutRoute>>;

/// Hotkey callbacks must not wait for settings persistence or OS registration.
/// Build the next map outside this lock; hold it only to clone/replace an Arc.
#[derive(Default)]
pub struct ShortcutRoutes(RwLock<ShortcutRouteSnapshot>);

impl ShortcutRoutes {
    pub fn publish_registered(
        &self,
        desired: impl IntoIterator<Item = (u32, ShortcutRoute)>,
        registered: impl IntoIterator<Item = u32>,
    ) -> Result<(), String> {
        let registered: BTreeSet<_> = registered.into_iter().collect();
        let next: BTreeMap<_, _> = desired
            .into_iter()
            .filter(|(id, _)| registered.contains(id))
            .collect();
        let next = Arc::new(next);
        let mut current = self.0.write().map_err(|_| "快捷键路由状态异常")?;
        // Provider/theme-only saves do not invalidate a pending hotkey.
        if current.as_ref() != next.as_ref() {
            *current = next;
        }
        Ok(())
    }

    pub fn snapshot(&self) -> Result<ShortcutRouteSnapshot, String> {
        self.0
            .read()
            .map(|current| Arc::clone(&current))
            .map_err(|_| "快捷键路由状态异常".into())
    }

    pub fn is_current(&self, snapshot: &ShortcutRouteSnapshot) -> bool {
        self.0
            .read()
            .is_ok_and(|current| Arc::ptr_eq(&current, snapshot))
    }
}

/// A read-only snapshot of the four supported modifier families. No hook,
/// sequence, text, clipboard, application query, or permission is involved.
pub fn recording_modifiers_down() -> Option<u8> {
    #[cfg(target_os = "windows")]
    {
        #[link(name = "user32")]
        unsafe extern "system" {
            fn GetAsyncKeyState(key: i32) -> i16;
        }
        let mut mask = 0;
        for (key, bit) in [(0x11, 1), (0x12, 2), (0x10, 4), (0x5b, 8), (0x5c, 8)] {
            if unsafe { GetAsyncKeyState(key) } < 0 {
                mask |= bit;
            }
        }
        Some(mask)
    }
    #[cfg(not(target_os = "windows"))]
    None
}

/// Registry operations affect exactly one ID. An Err must leave that ID's
/// registration unchanged, matching native RegisterHotKey/UnregisterHotKey.
pub trait Registry {
    fn register(&mut self, binding: u32) -> Result<(), String>;
    fn unregister(&mut self, binding: u32) -> Result<(), String>;
}

/// Recover unavailable rows independently. This runtime-only operation has no
/// persistence callback: a timer must not rewrite settings or trim history.
pub fn recover_bindings(
    registry: &mut impl Registry,
    candidates: &[(String, u32)],
    failures: &mut BTreeMap<String, String>,
) -> bool {
    let mut recovered = false;
    for (action, id) in candidates {
        match registry.register(*id) {
            Ok(()) => {
                failures.remove(action);
                recovered = true;
            }
            Err(error) => {
                failures.insert(action.clone(), error);
            }
        }
    }
    recovered
}

/// Plan a settings update from successfully acquired IDs, rather than treating
/// every configured shortcut as an existing registration. Callers supply parsed,
/// enabled action/ID pairs after validating duplicate actions and bindings.
///
/// Keep any acquired ID that is still desired, including action swaps. Attempt
/// new or changed actions, but leave an unchanged unavailable action inactive:
/// saving an unrelated setting must not keep retrying its failed registration.
/// `retry_actions` identifies an explicit edit/re-record of an unavailable row;
/// it never causes an already acquired ID to be registered again.
pub fn registration_targets(
    actual: &[u32],
    previous: &[(String, u32)],
    next: &[(String, u32)],
    retry_actions: &[String],
) -> Vec<u32> {
    let actual: BTreeSet<_> = actual.iter().copied().collect();
    let previous: BTreeMap<_, _> = previous
        .iter()
        .map(|(action, id)| (action.as_str(), *id))
        .collect();
    let retries: BTreeSet<_> = retry_actions.iter().map(String::as_str).collect();
    next.iter()
        .filter(|(action, id)| {
            actual.contains(id)
                || previous.get(action.as_str()) != Some(id)
                || retries.contains(action.as_str())
        })
        .map(|(_, id)| *id)
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect()
}

/// Stage new-only IDs while old bindings remain registered; then remove old-only
/// IDs and persist. Shared IDs (including action swaps) never touch the OS.
/// The caller owns settings-memory consistency if its persist callback mutates
/// memory and subsequently returns Err. Rollback failures are always reported.
pub fn replace_bindings(
    registry: &mut impl Registry,
    old: &[u32],
    new: &[u32],
    persist: impl FnOnce() -> Result<(), String>,
) -> Result<(), String> {
    let old: BTreeSet<_> = old.iter().copied().collect();
    let new: BTreeSet<_> = new.iter().copied().collect();
    let mut added = Vec::new();
    let mut removed = Vec::new();
    for binding in new.difference(&old).copied() {
        if let Err(error) = registry.register(binding) {
            return Err(rollback(
                registry,
                &added,
                &removed,
                format!("注册快捷键失败：{error}"),
            ));
        }
        added.push(binding);
    }
    for binding in old.difference(&new).copied() {
        if let Err(error) = registry.unregister(binding) {
            return Err(rollback(
                registry,
                &added,
                &removed,
                format!("移除旧快捷键失败：{error}"),
            ));
        }
        removed.push(binding);
    }
    if let Err(error) = persist() {
        return Err(rollback(
            registry,
            &added,
            &removed,
            format!("保存快捷键失败：{error}"),
        ));
    }
    Ok(())
}

fn rollback(
    registry: &mut impl Registry,
    added: &[u32],
    removed: &[u32],
    original_error: String,
) -> String {
    let mut failures = Vec::new();
    for binding in removed.iter().rev().copied() {
        if let Err(error) = registry.register(binding) {
            failures.push(format!("恢复旧快捷键 {binding} 失败：{error}"));
        }
    }
    for binding in added.iter().rev().copied() {
        if let Err(error) = registry.unregister(binding) {
            failures.push(format!("撤销新快捷键 {binding} 失败：{error}"));
        }
    }
    if failures.is_empty() {
        original_error
    } else {
        format!(
            "{original_error}；快捷键回滚未完成：{}",
            failures.join("；")
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::{Cell, RefCell};
    use std::collections::VecDeque;
    use std::rc::Rc;

    fn route(action: &str, combo: &str) -> ShortcutRoute {
        ShortcutRoute {
            action: action.into(),
            combo: combo.into(),
        }
    }

    #[test]
    fn route_reads_finish_while_another_thread_holds_settings_for_persistence() {
        use std::sync::{mpsc, Mutex};
        let routes = Arc::new(ShortcutRoutes::default());
        routes
            .publish_registered([(1, route("selection", "Alt+D"))], [1])
            .unwrap();
        let settings = Arc::new(Mutex::new(route("selection", "Alt+D")));
        let (held_tx, held_rx) = mpsc::channel();
        let (release_tx, release_rx) = mpsc::channel();
        let writer_routes = Arc::clone(&routes);
        let writer_settings = Arc::clone(&settings);
        let writer = std::thread::spawn(move || {
            let mut locked = writer_settings.lock().unwrap();
            held_tx.send(()).unwrap();
            release_rx.recv().unwrap();
            *locked = route("selection", "Ctrl+D");
            writer_routes
                .publish_registered([(2, locked.clone())], [2])
                .unwrap();
        });
        held_rx.recv_timeout(Duration::from_secs(2)).unwrap();
        assert!(settings.try_lock().is_err());
        let reader_routes = Arc::clone(&routes);
        let (read_tx, read_rx) = mpsc::channel();
        let reader = std::thread::spawn(move || {
            let mut gate = ShortcutGate::default();
            let now = Instant::now();
            assert_eq!(gate.observe(1, true, now), ShortcutDelivery::Ignored);
            assert_eq!(gate.observe(1, false, now), ShortcutDelivery::Action);
            let snapshot = reader_routes.snapshot().unwrap();
            read_tx.send(snapshot.get(&1).cloned()).unwrap();
        });
        // The write is still blocked on release_rx, not on timing or disk speed.
        let received = read_rx.recv_timeout(Duration::from_secs(2));
        release_tx.send(()).unwrap();
        writer.join().unwrap();
        reader.join().unwrap();
        assert_eq!(received.unwrap(), Some(route("selection", "Alt+D")));
        assert_eq!(
            routes.snapshot().unwrap().get(&2),
            Some(&route("selection", "Ctrl+D"))
        );
        assert!(!routes.snapshot().unwrap().contains_key(&1));
    }

    #[test]
    fn route_generation_changes_only_when_action_combo_or_registration_changes() {
        let routes = ShortcutRoutes::default();
        routes
            .publish_registered([(1, route("selection", "Alt+D"))], [1])
            .unwrap();
        let accepted = routes.snapshot().unwrap();
        routes
            .publish_registered([(1, route("selection", "Alt+D"))], [1])
            .unwrap();
        assert!(routes.is_current(&accepted));
        routes
            .publish_registered([(1, route("silentOcr", "Alt+D"))], [1])
            .unwrap();
        assert!(!routes.is_current(&accepted));
        assert_eq!(accepted.get(&1), Some(&route("selection", "Alt+D")));
        let swapped = routes.snapshot().unwrap();
        assert_eq!(swapped.get(&1), Some(&route("silentOcr", "Alt+D")));
        routes
            .publish_registered([(1, route("silentOcr", "Alt+D"))], [])
            .unwrap();
        assert!(!routes.is_current(&swapped));
        assert!(routes.snapshot().unwrap().is_empty());
    }

    #[test]
    fn partial_registry_recovery_never_routes_missing_or_unconfigured_ids() {
        let routes = ShortcutRoutes::default();
        //1 was restored,2 failed restoration,3 is an orphan staged registration.
        routes
            .publish_registered(
                [
                    (1, route("selection", "Alt+D")),
                    (2, route("silentOcr", "Alt+S")),
                ],
                [1, 3],
            )
            .unwrap();
        let snapshot = routes.snapshot().unwrap();
        assert_eq!(snapshot.len(), 1);
        assert_eq!(snapshot.get(&1), Some(&route("selection", "Alt+D")));
        assert!(!snapshot.contains_key(&2));
        assert!(!snapshot.contains_key(&3));
    }

    #[test]
    fn native_recording_bridge_requires_one_fresh_pair_in_the_same_live_lease() {
        let now = Instant::now();
        let mut gate = ShortcutGate::default();
        let id = gate.begin(now).unwrap();
        assert_eq!(gate.observe(1, false, now), ShortcutDelivery::Ignored);
        assert_eq!(gate.observe(1, true, now), ShortcutDelivery::Ignored);
        assert_eq!(gate.observe(1, true, now), ShortcutDelivery::Ignored);
        assert_eq!(gate.observe(1, false, now), ShortcutDelivery::Recorded(id));
        assert_eq!(gate.observe(1, false, now), ShortcutDelivery::Ignored);
        assert!(gate.matches_recording(id, now));
        assert!(!gate.matches_recording(id + 1, now));
    }

    #[test]
    fn a_press_before_begin_cannot_become_a_recorded_shortcut() {
        let now = Instant::now();
        let mut gate = ShortcutGate::default();
        gate.observe(1, true, now);
        let id = gate.begin(now).unwrap();
        assert_eq!(gate.observe(1, true, now), ShortcutDelivery::Ignored);
        assert_eq!(gate.observe(1, false, now), ShortcutDelivery::Ignored);
        gate.observe(1, true, now);
        assert_eq!(gate.observe(1, false, now), ShortcutDelivery::Recorded(id));
    }

    #[test]
    fn stale_recorded_pairs_expiry_and_cancel_cannot_emit_or_execute() {
        let now = Instant::now();
        let mut gate = ShortcutGate::default();
        let old = gate.begin(now).unwrap();
        gate.observe(1, true, now);
        let current = gate.begin(now).unwrap();
        assert_ne!(old, current);
        assert_eq!(gate.observe(1, false, now), ShortcutDelivery::Ignored);
        gate.observe(2, true, now);
        assert_eq!(
            gate.observe(2, false, now + RECORDING_LEASE),
            ShortcutDelivery::Ignored
        );
        assert!(!gate.matches_recording(current, now + RECORDING_LEASE));
        gate.begin(now + RECORDING_LEASE).unwrap();
        gate.observe(3, true, now + RECORDING_LEASE);
        gate.cancel(now + RECORDING_LEASE);
        assert_eq!(
            gate.observe(3, false, now + RECORDING_LEASE),
            ShortcutDelivery::Ignored
        );
    }

    #[test]
    fn only_one_matching_release_after_a_fresh_press_executes() {
        let mut gate = ShortcutGate::default();
        let now = Instant::now();
        assert!(!gate.allows_release(1, false, now));
        assert!(!gate.allows_release(1, true, now));
        assert!(!gate.allows_release(1, true, now));
        assert!(!gate.allows_release(2, false, now));
        assert!(gate.allows_release(1, false, now));
        assert!(!gate.allows_release(1, false, now));
    }

    #[test]
    fn begin_invalidates_an_already_allowed_press() {
        let now = Instant::now();
        let mut gate = ShortcutGate::default();
        gate.allows_release(1, true, now);
        let id = gate.begin(now).unwrap();
        assert!(gate.end(id, now));
        assert!(!gate.allows_release(1, false, now + RELEASE_COOLDOWN));
        gate.allows_release(1, true, now + RELEASE_COOLDOWN);
        assert!(gate.allows_release(1, false, now + RELEASE_COOLDOWN));
    }

    #[test]
    fn recording_and_cooldown_do_not_execute_or_rearm_held_keys() {
        let now = Instant::now();
        let mut gate = ShortcutGate::default();
        let id = gate.begin(now).unwrap();
        assert!(!gate.allows_release(3, true, now));
        assert!(!gate.allows_release(4, true, now));
        assert!(!gate.allows_release(4, false, now));
        assert!(gate.end(id, now));
        assert!(!gate.allows_release(5, true, now + Duration::from_millis(349)));
        let later = now + RELEASE_COOLDOWN;
        assert!(!gate.allows_release(3, true, later));
        assert!(!gate.allows_release(5, true, later));
        assert!(!gate.allows_release(3, false, later));
        assert!(!gate.allows_release(5, false, later));
        assert!(!gate.allows_release(3, true, later));
        assert!(gate.allows_release(3, false, later));
    }

    #[test]
    fn stale_end_cannot_close_a_replacement_lease() {
        let now = Instant::now();
        let mut gate = ShortcutGate::default();
        let old = gate.begin(now).unwrap();
        let current = gate.begin(now + Duration::from_millis(1)).unwrap();
        assert!(current > old);
        assert!(!gate.end(old, now + Duration::from_millis(2)));
        assert!(gate.is_recording(now + Duration::from_millis(2)));
        assert!(!gate.allows_release(1, true, now + Duration::from_millis(2)));
        assert!(!gate.allows_release(1, false, now + Duration::from_millis(2)));
        assert!(gate.end(current, now + Duration::from_millis(3)));
    }

    #[test]
    fn expiry_discovered_by_release_cannot_submit_the_recorded_binding() {
        let now = Instant::now();
        let mut gate = ShortcutGate::default();
        gate.begin(now).unwrap();
        gate.allows_release(1, true, now + Duration::from_secs(14));
        let expiry = now + RECORDING_LEASE;
        assert!(!gate.allows_release(1, false, expiry));
        assert!(!gate.is_recording(expiry));
        gate.allows_release(1, true, expiry + Duration::from_millis(349));
        assert!(!gate.allows_release(1, false, expiry + Duration::from_millis(349)));
        gate.allows_release(1, true, expiry + RELEASE_COOLDOWN);
        assert!(gate.allows_release(1, false, expiry + RELEASE_COOLDOWN));
    }

    #[test]
    fn expiry_boundary_press_cannot_rearm_when_its_release_is_after_cooldown() {
        let now = Instant::now();
        let mut gate = ShortcutGate::default();
        let id = gate.begin(now).unwrap();
        let expiry = now + RECORDING_LEASE;
        assert!(!gate.allows_release(1, true, expiry));
        assert!(!gate.end(id, expiry));
        assert!(!gate.allows_release(1, true, expiry + RELEASE_COOLDOWN));
        assert!(!gate.allows_release(1, false, expiry + RELEASE_COOLDOWN));
        gate.allows_release(1, true, expiry + RELEASE_COOLDOWN);
        assert!(gate.allows_release(1, false, expiry + RELEASE_COOLDOWN));
    }

    #[test]
    fn lease_expiry_does_not_swallow_a_fresh_press_after_long_idle() {
        let now = Instant::now();
        let mut gate = ShortcutGate::default();
        gate.begin(now).unwrap();
        gate.allows_release(1, true, now);
        let later = now + Duration::from_secs(40);
        assert!(!gate.allows_release(1, false, later));
        gate.allows_release(2, true, later);
        assert!(gate.allows_release(2, false, later));
    }

    #[test]
    fn cancel_for_blur_navigation_or_update_invalidates_preexisting_presses() {
        let now = Instant::now();
        let mut gate = ShortcutGate::default();
        gate.allows_release(1, true, now);
        gate.cancel(now);
        let later = now + RELEASE_COOLDOWN;
        assert!(!gate.allows_release(1, true, later));
        assert!(!gate.allows_release(1, false, later));
        gate.allows_release(1, true, later);
        assert!(gate.allows_release(1, false, later));
        let id = gate.begin(later).unwrap();
        gate.cancel(later);
        assert!(!gate.is_recording(later));
        assert!(!gate.end(id, later));
    }

    #[test]
    fn cooldown_boundary_is_exclusive_and_old_end_does_not_extend_it() {
        let now = Instant::now();
        let mut gate = ShortcutGate::default();
        let id = gate.begin(now).unwrap();
        gate.end(id, now);
        assert!(!gate.end(id, now + Duration::from_millis(300)));
        gate.allows_release(1, true, now + RELEASE_COOLDOWN);
        assert!(gate.allows_release(1, false, now + RELEASE_COOLDOWN));
    }

    #[test]
    fn multiple_bindings_keep_independent_press_release_pairs() {
        let now = Instant::now();
        let mut gate = ShortcutGate::default();
        gate.allows_release(1, true, now);
        gate.allows_release(2, true, now);
        assert!(gate.allows_release(2, false, now));
        assert!(gate.allows_release(1, false, now));
    }

    #[test]
    fn update_time_release_is_fed_and_the_first_later_fresh_pair_works() {
        let now = Instant::now();
        let mut gate = ShortcutGate::default();
        gate.allows_release(1, true, now);
        gate.cancel(now); // The binding update begins.
        let release = now + Duration::from_millis(10);
        gate.cancel(release); // Dispatcher still feeds phases during update.
        assert!(!gate.allows_release(1, false, release));
        let next = release + RELEASE_COOLDOWN;
        gate.allows_release(1, true, next);
        assert!(gate.allows_release(1, false, next));
    }

    #[test]
    fn a_long_update_cannot_arm_a_press_for_release_after_update_finishes() {
        let now = Instant::now();
        let mut gate = ShortcutGate::default();
        gate.cancel(now);
        let during = now + Duration::from_secs(1);
        gate.cancel(during); // Update is still running past the first cooldown.
        gate.allows_release(1, true, during);
        let after = during + RELEASE_COOLDOWN;
        assert!(!gate.allows_release(1, false, after));
        gate.allows_release(1, true, after);
        assert!(gate.allows_release(1, false, after));
    }

    #[test]
    fn exhausted_lease_ids_fail_closed_without_reusing_an_old_id() {
        let now = Instant::now();
        let mut gate = ShortcutGate {
            next_id: u64::MAX,
            ..Default::default()
        };
        gate.allows_release(1, true, now);
        assert!(gate.begin(now).is_err());
        assert!(!gate.allows_release(1, false, now));
        assert_eq!(gate.next_id, u64::MAX);
    }

    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    enum Operation {
        Add(u32),
        Remove(u32),
    }

    struct FakeRegistry {
        active: BTreeSet<u32>,
        fail: VecDeque<Operation>,
        operations: Vec<Operation>,
        trace: Rc<RefCell<Vec<String>>>,
    }

    impl FakeRegistry {
        fn new(active: &[u32], fail: &[Operation]) -> Self {
            Self {
                active: active.iter().copied().collect(),
                fail: fail.iter().copied().collect(),
                operations: Vec::new(),
                trace: Rc::new(RefCell::new(Vec::new())),
            }
        }

        fn inspect(&mut self, operation: Operation) -> Result<(), String> {
            self.operations.push(operation);
            self.trace.borrow_mut().push(format!("{operation:?}"));
            if self.fail.front() == Some(&operation) {
                self.fail.pop_front();
                Err(format!("synthetic {operation:?}"))
            } else {
                Ok(())
            }
        }
    }

    impl Registry for FakeRegistry {
        fn register(&mut self, binding: u32) -> Result<(), String> {
            self.inspect(Operation::Add(binding))?;
            if self.active.insert(binding) {
                Ok(())
            } else {
                Err("binding already active".into())
            }
        }

        fn unregister(&mut self, binding: u32) -> Result<(), String> {
            self.inspect(Operation::Remove(binding))?;
            if self.active.remove(&binding) {
                Ok(())
            } else {
                Err("binding not active".into())
            }
        }
    }

    fn named_bindings(values: &[(&str, u32)]) -> Vec<(String, u32)> {
        values
            .iter()
            .map(|(action, id)| ((*action).into(), *id))
            .collect()
    }

    #[test]
    fn runtime_recovery_keeps_working_rows_and_attempts_conflicts_independently() {
        let mut registry = FakeRegistry::new(&[1], &[Operation::Add(2)]);
        let mut failures = BTreeMap::from([
            ("capture".into(), "old conflict".into()),
            ("input".into(), "old input conflict".into()),
            ("reserved".into(), "permanent error".into()),
        ]);
        let candidates = named_bindings(&[("capture", 2), ("input", 3)]);
        assert!(recover_bindings(&mut registry, &candidates, &mut failures));
        assert_eq!(registry.active, BTreeSet::from([1, 3]));
        assert_eq!(registry.operations, [Operation::Add(2), Operation::Add(3)]);
        assert!(failures["capture"].contains("synthetic"));
        assert!(!failures.contains_key("input"));
        assert_eq!(failures["reserved"], "permanent error");
        registry.operations.clear();
        assert!(recover_bindings(
            &mut registry,
            &named_bindings(&[("capture", 2)]),
            &mut failures
        ));
        assert_eq!(registry.operations, [Operation::Add(2)]);
        assert_eq!(registry.active, BTreeSet::from([1, 2, 3]));
        assert!(!failures.contains_key("capture"));
    }

    #[test]
    fn empty_or_failed_runtime_recovery_does_not_claim_success_or_remove_bindings() {
        let mut registry = FakeRegistry::new(&[1], &[Operation::Add(2)]);
        let mut failures = BTreeMap::new();
        assert!(!recover_bindings(&mut registry, &[], &mut failures));
        assert!(registry.operations.is_empty());
        assert!(!recover_bindings(
            &mut registry,
            &named_bindings(&[("capture", 2)]),
            &mut failures
        ));
        assert_eq!(registry.active, BTreeSet::from([1]));
        assert_eq!(registry.operations, [Operation::Add(2)]);
        assert!(failures.contains_key("capture"));
    }

    #[test]
    fn unavailable_unchanged_action_does_not_block_new_free_shortcuts() {
        let previous = named_bindings(&[("selection", 1), ("capture", 2)]);
        for free in [3, 4, 5] {
            let next = named_bindings(&[("selection", free), ("capture", 2)]);
            let mut registry = FakeRegistry::new(&[1], &[Operation::Add(2)]);
            let persisted = Cell::new(0);
            let targets = registration_targets(&[1], &previous, &next, &[]);
            replace_bindings(&mut registry, &[1], &targets, || {
                persisted.set(persisted.get() + 1);
                Ok(())
            })
            .unwrap();
            assert_eq!(registry.active, BTreeSet::from([free]));
            assert_eq!(persisted.get(), 1);
            assert_eq!(
                registry.operations,
                [Operation::Add(free), Operation::Remove(1)]
            );
        }
    }

    #[test]
    fn empty_actual_registry_can_recover_one_action_without_retrying_other_defaults() {
        let previous = named_bindings(&[("selection", 1), ("capture", 2)]);
        let next = named_bindings(&[("selection", 3), ("capture", 2)]);
        let mut registry = FakeRegistry::new(&[], &[Operation::Add(2)]);
        let targets = registration_targets(&[], &previous, &next, &[]);
        replace_bindings(&mut registry, &[], &targets, || Ok(())).unwrap();
        assert_eq!(registry.active, BTreeSet::from([3]));
        assert_eq!(registry.operations, [Operation::Add(3)]);
    }

    #[test]
    fn unrelated_settings_save_does_not_retry_missing_configured_actions() {
        let configured = named_bindings(&[("selection", 1), ("capture", 2)]);
        let mut registry = FakeRegistry::new(&[1], &[Operation::Add(2)]);
        let persisted = Cell::new(false);
        let targets = registration_targets(&[1], &configured, &configured, &[]);
        replace_bindings(&mut registry, &[1], &targets, || {
            persisted.set(true);
            Ok(())
        })
        .unwrap();
        assert!(persisted.get());
        assert!(registry.operations.is_empty());
        assert_eq!(registry.active, BTreeSet::from([1]));
    }

    #[test]
    fn explicit_same_row_retry_reports_conflict_without_losing_working_actions() {
        let configured = named_bindings(&[("selection", 1), ("capture", 2)]);
        let targets = registration_targets(&[1], &configured, &configured, &["capture".into()]);
        let mut registry = FakeRegistry::new(&[1], &[Operation::Add(2)]);
        let persisted = Cell::new(false);
        let error = replace_bindings(&mut registry, &[1], &targets, || {
            persisted.set(true);
            Ok(())
        })
        .unwrap_err();
        assert!(error.contains("注册快捷键失败"));
        assert!(!persisted.get());
        assert_eq!(registry.active, BTreeSet::from([1]));
        assert_eq!(registry.operations, [Operation::Add(2)]);

        // A later explicit retry can acquire that same configured row once the
        // competing owner has released it; no unrelated save performed a retry.
        registry.operations.clear();
        replace_bindings(&mut registry, &[1], &targets, || Ok(())).unwrap();
        assert_eq!(registry.active, BTreeSet::from([1, 2]));
        assert_eq!(registry.operations, [Operation::Add(2)]);
    }

    #[test]
    fn action_swaps_reuse_acquired_ids_even_when_only_one_row_is_active() {
        let previous = named_bindings(&[("selection", 1), ("capture", 2)]);
        let next = named_bindings(&[("selection", 2), ("capture", 1)]);
        assert_eq!(registration_targets(&[1, 2], &previous, &next, &[]), [1, 2]);
        let targets = registration_targets(&[1], &previous, &next, &[]);
        let mut registry = FakeRegistry::new(&[1], &[]);
        replace_bindings(&mut registry, &[1], &targets, || Ok(())).unwrap();
        assert_eq!(registry.active, BTreeSet::from([1, 2]));
        assert_eq!(registry.operations, [Operation::Add(2)]);
    }

    #[test]
    fn disabling_rows_removes_only_acquired_ids_and_ignores_disabled_retry_requests() {
        let previous = named_bindings(&[("selection", 1), ("capture", 2)]);
        let next = named_bindings(&[("capture", 2)]);
        let targets = registration_targets(&[1], &previous, &next, &["selection".into()]);
        let mut registry = FakeRegistry::new(&[1], &[Operation::Add(2)]);
        replace_bindings(&mut registry, &[1], &targets, || Ok(())).unwrap();
        assert!(registry.active.is_empty());
        assert_eq!(registry.operations, [Operation::Remove(1)]);
    }

    #[test]
    fn already_active_retry_and_new_action_alias_do_not_reregister_shared_id() {
        let previous = named_bindings(&[("selection", 1)]);
        let next = named_bindings(&[("capture", 1)]);
        let targets = registration_targets(&[1], &previous, &next, &["capture".into()]);
        let mut registry = FakeRegistry::new(&[1], &[Operation::Add(1)]);
        replace_bindings(&mut registry, &[1], &targets, || Ok(())).unwrap();
        assert!(registry.operations.is_empty());
        assert_eq!(registry.active, BTreeSet::from([1]));
    }

    #[test]
    fn initial_registration_plan_includes_all_new_desired_actions() {
        let next = named_bindings(&[("selection", 2), ("capture", 1)]);
        assert_eq!(registration_targets(&[], &[], &next, &[]), [1, 2]);
    }

    #[test]
    fn replacement_stages_all_new_ids_before_removing_old_then_persists_once() {
        let mut registry = FakeRegistry::new(&[1, 2], &[]);
        let trace = registry.trace.clone();
        replace_bindings(&mut registry, &[1, 2], &[2, 3, 4], || {
            trace.borrow_mut().push("persist".into());
            Ok(())
        })
        .unwrap();
        assert_eq!(registry.active, BTreeSet::from([2, 3, 4]));
        assert_eq!(
            *registry.trace.borrow(),
            ["Add(3)", "Add(4)", "Remove(1)", "persist"]
        );
    }

    #[test]
    fn conflict_keeps_old_bindings_and_cleans_only_successful_staged_ids() {
        let mut registry = FakeRegistry::new(&[1, 2], &[Operation::Add(4)]);
        let persisted = Cell::new(false);
        let error = replace_bindings(&mut registry, &[1, 2], &[3, 4], || {
            persisted.set(true);
            Ok(())
        })
        .unwrap_err();
        assert!(error.starts_with("注册快捷键失败："));
        assert!(!persisted.get());
        assert_eq!(registry.active, BTreeSet::from([1, 2]));
        assert_eq!(
            registry.operations,
            [Operation::Add(3), Operation::Add(4), Operation::Remove(3)]
        );
    }

    #[test]
    fn remove_failure_restores_removed_old_ids_and_cleans_new_ids() {
        let mut registry = FakeRegistry::new(&[1, 2], &[Operation::Remove(2)]);
        let error = replace_bindings(&mut registry, &[1, 2], &[3], || {
            panic!("persist must not run after registry failure")
        })
        .unwrap_err();
        assert!(error.starts_with("移除旧快捷键失败："));
        assert_eq!(registry.active, BTreeSet::from([1, 2]));
        assert_eq!(
            registry.operations,
            [
                Operation::Add(3),
                Operation::Remove(1),
                Operation::Remove(2),
                Operation::Add(1),
                Operation::Remove(3)
            ]
        );
    }

    #[test]
    fn persistence_failure_rolls_back_the_complete_registry_change() {
        let mut registry = FakeRegistry::new(&[1, 2], &[]);
        let error = replace_bindings(&mut registry, &[1, 2], &[3, 4], || {
            Err("synthetic disk failure".into())
        })
        .unwrap_err();
        assert!(error.contains("保存快捷键失败：synthetic disk failure"));
        assert!(!error.contains("回滚未完成"));
        assert_eq!(registry.active, BTreeSet::from([1, 2]));
        assert_eq!(
            &registry.operations[4..],
            [
                Operation::Add(2),
                Operation::Add(1),
                Operation::Remove(4),
                Operation::Remove(3)
            ]
        );
    }

    #[test]
    fn action_swaps_and_duplicate_ids_do_not_reregister_shared_bindings() {
        let mut registry = FakeRegistry::new(&[1, 2], &[]);
        let persisted = Cell::new(0);
        replace_bindings(&mut registry, &[1, 2], &[2, 1, 2], || {
            persisted.set(persisted.get() + 1);
            Ok(())
        })
        .unwrap();
        assert_eq!(persisted.get(), 1);
        assert!(registry.operations.is_empty());
        assert_eq!(registry.active, BTreeSet::from([1, 2]));
    }

    #[test]
    fn clearing_all_bindings_and_initial_install_need_no_special_case() {
        let mut registry = FakeRegistry::new(&[1, 2], &[]);
        replace_bindings(&mut registry, &[1, 2], &[], || Ok(())).unwrap();
        assert!(registry.active.is_empty());
        replace_bindings(&mut registry, &[], &[3], || Ok(())).unwrap();
        assert_eq!(registry.active, BTreeSet::from([3]));
    }

    #[test]
    fn failed_restore_and_cleanup_errors_are_both_reported_with_original_failure() {
        let mut registry = FakeRegistry::new(&[1], &[Operation::Add(1), Operation::Remove(3)]);
        let error = replace_bindings(&mut registry, &[1], &[3], || {
            Err("original persistence error".into())
        })
        .unwrap_err();
        assert!(error.contains("original persistence error"));
        assert!(error.contains("快捷键回滚未完成"));
        assert!(error.contains("恢复旧快捷键 1 失败"));
        assert!(error.contains("撤销新快捷键 3 失败"));
        assert_eq!(registry.active, BTreeSet::from([3]));
    }

    #[test]
    fn failed_staging_cleanup_is_explicit_and_never_unregisters_old_bindings() {
        let mut registry = FakeRegistry::new(&[1, 2], &[Operation::Add(4), Operation::Remove(3)]);
        let error = replace_bindings(&mut registry, &[1, 2], &[3, 4], || Ok(())).unwrap_err();
        assert!(error.contains("注册快捷键失败"));
        assert!(error.contains("撤销新快捷键 3 失败"));
        assert!(registry.active.contains(&1) && registry.active.contains(&2));
        assert!(!registry.operations.contains(&Operation::Remove(1)));
        assert!(!registry.operations.contains(&Operation::Remove(2)));
    }

    #[test]
    fn persistence_failure_on_unchanged_ids_has_no_registry_side_effect() {
        let mut registry = FakeRegistry::new(&[1, 2], &[]);
        let error = replace_bindings(&mut registry, &[1, 2], &[2, 1], || {
            Err("write rejected".into())
        })
        .unwrap_err();
        assert!(error.contains("保存快捷键失败：write rejected"));
        assert!(registry.operations.is_empty());
        assert_eq!(registry.active, BTreeSet::from([1, 2]));
    }
}

#[cfg(test)]
mod completed_pair_tests {
    use super::*;
    #[test]
    fn discarded_completed_pair_never_consumes_the_next_press() {
        let mut gate = ShortcutGate::default();
        let now = Instant::now();
        let stale_delivery = gate.observe_pair(23, now);
        assert_eq!(stale_delivery, ShortcutDelivery::Action);
        // The route/context validator discards stale_delivery after the lock, but
        // this next complete physical gesture still owns a fresh press.
        assert_eq!(
            gate.observe_pair(23, now + Duration::from_millis(1)),
            ShortcutDelivery::Action
        );
    }
    #[test]
    fn recorded_complete_pair_does_not_leave_a_held_id_after_end() {
        let mut gate = ShortcutGate::default();
        let now = Instant::now();
        let lease = gate.begin(now).unwrap();
        assert_eq!(
            gate.observe_pair(29, now),
            ShortcutDelivery::Recorded(lease)
        );
        assert!(gate.end(lease, now));
        assert_eq!(
            gate.observe_pair(29, now + Duration::from_secs(1)),
            ShortcutDelivery::Action
        );
    }
}
