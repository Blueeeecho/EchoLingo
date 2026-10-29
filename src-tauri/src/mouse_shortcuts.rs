//! Scalar policy for Windows priority keyboard and opt-in side-button pairs.
//! The native callback owns this state; actions run only after a paired release.

pub const PRIORITY_D: u8 = 1;
pub const PRIORITY_S: u8 = 2;
pub const MOUSE_X1: u8 = 4;
pub const MOUSE_X2: u8 = 8;
pub const MOUSE_X1_ID: u32 = 0x8000_0001;
pub const MOUSE_X2_ID: u32 = 0x8000_0002;

// Only keys relevant to a priority pair or its modifier exclusion are sampled.
pub const HELD_D: u16 = 1;
pub const HELD_S: u16 = 2;
pub fn recovery_key_bit(key: u32, scan: u32, extended: bool) -> u16 {
    match key {
        0x44 => HELD_D,
        0x53 => HELD_S,
        0xa4 => 4,
        0xa5 => 8,
        0x12 => {
            if extended {
                8
            } else {
                4
            }
        }
        0xa2 => 16,
        0xa3 => 32,
        0x11 => {
            if extended {
                32
            } else {
                16
            }
        }
        0xa0 => 64,
        0xa1 => 128,
        0x10 => {
            if scan == 0x36 {
                128
            } else {
                64
            }
        }
        0x5b => 256,
        0x5c => 512,
        _ => 0,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Button {
    X1,
    X2,
}
impl Button {
    pub fn id(self) -> u32 {
        match self {
            Self::X1 => MOUSE_X1_ID,
            Self::X2 => MOUSE_X2_ID,
        }
    }
    pub fn bit(self) -> u8 {
        match self {
            Self::X1 => MOUSE_X1,
            Self::X2 => MOUSE_X2,
        }
    }
    pub fn name(self) -> &'static str {
        match self {
            Self::X1 => "MouseX1",
            Self::X2 => "MouseX2",
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Context {
    pub generation: u64,
    pub foreground: isize,
    pub focus: isize,
    pub capture: u64,
    pub recording: u64,
    pub blocked: bool,
}
impl Context {
    /// A zero focus means the bounded native metadata query was unavailable.
    /// Reject known changes without inventing a focus identity for unknowns.
    pub fn matches(self, other: Self) -> bool {
        self.generation == other.generation
            && self.capture == other.capture
            && self.recording == other.recording
            && self.blocked == other.blocked
            && self.foreground == other.foreground
            && (self.focus == 0 || other.focus == 0 || self.focus == other.focus)
    }
}
#[derive(Clone, Copy, Debug)]
pub enum Alt {
    Left,
    Right,
}
impl Alt {
    fn bit(self) -> u8 {
        match self {
            Self::Left => 1,
            Self::Right => 2,
        }
    }
}

#[derive(Clone, Copy, Debug, Default)]
struct Held {
    owned: bool,
    accepted: bool,
    context: Context,
}
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Decision {
    pub consume: bool,
    pub release: bool,
    pub mask_alt: bool,
    pub context: Context,
}
#[derive(Default)]
pub struct Policy {
    held: [Held; 4],
    mask_alt: bool,
    alt_held: u8,
    alt_anchor: Option<Context>,
}
impl Policy {
    /// Anchor the first observed Alt down, never a repeat or the other side.
    /// Native metadata is scalar only; a missing foreground cannot arm intent.
    pub fn alt_down(&mut self, side: Alt, mut context: Context) {
        if self.alt_held == 0 {
            context.capture = 0;
            self.alt_anchor = (context.foreground != 0).then_some(context);
        }
        self.alt_held |= side.bit();
    }
    pub fn alt_up(&mut self, side: Alt) -> bool {
        self.alt_held &= !side.bit();
        if self.alt_held != 0 {
            return false;
        }
        self.alt_anchor = None;
        std::mem::take(&mut self.mask_alt)
    }
    /// A missing OS Alt context flag can fall back only to the same side being
    /// both observed here and still physically down. Stale or unobserved bits
    /// must never turn ordinary typing into a priority shortcut.
    pub fn tracked_alt_down(&self, left_down: bool, right_down: bool) -> bool {
        (self.alt_held & Alt::Left.bit() != 0 && left_down)
            || (self.alt_held & Alt::Right.bit() != 0 && right_down)
    }
    /// Called only after the recovery pump proves physical keys and owned
    /// keyboard pairs are drained; never abandon a suffix release.
    pub fn reset_alt_anchor(&mut self) {
        if !self.keyboard_owned() {
            self.alt_held = 0;
            self.alt_anchor = None;
            self.mask_alt = false;
        }
    }
    fn anchor_matches(&self, context: Context) -> bool {
        self.alt_anchor.is_some_and(|anchor| {
            anchor.generation == context.generation
                && anchor.foreground == context.foreground
                && anchor.focus == context.focus
                && anchor.recording == context.recording
                && anchor.blocked == context.blocked
        })
    }
    /// Only a fresh, exact binding down can arm an action. An owned release is
    /// always consumed even if recording/settings/config/capture changed.
    pub fn pair(
        &mut self,
        slot: usize,
        down: bool,
        enabled: bool,
        mut context: Context,
    ) -> Decision {
        // A keyboard pair begins a new intent even if the old picker ends
        // between down and up. Mouse pairs remain owned by capture sessions.
        if slot < 2 {
            context.capture = 0;
        }
        let anchored = slot >= 2 || self.anchor_matches(context);
        let held = &mut self.held[slot];
        if down {
            if held.owned {
                if !held.context.matches(context) || context.blocked {
                    held.accepted = false;
                }
                return Decision {
                    consume: true,
                    ..Decision::default()
                };
            }
            if !enabled {
                return Decision::default();
            }
            *held = Held {
                owned: true,
                accepted: !context.blocked && anchored,
                context,
            };
            if slot < 2 {
                self.mask_alt = true;
            }
            return Decision {
                consume: true,
                ..Decision::default()
            };
        }
        let previous = *held;
        *held = Held::default();
        let release = previous.owned
            && previous.accepted
            && previous.context.matches(context)
            && !context.blocked;
        let mut delivery_context = context;
        if delivery_context.focus == 0 {
            delivery_context.focus = previous.context.focus;
        }
        Decision {
            consume: previous.owned,
            release,
            mask_alt: false,
            context: if release {
                delivery_context
            } else {
                Context::default()
            },
        }
    }
    pub fn owns(&self, slot: usize) -> bool {
        self.held[slot].owned
    }
    pub fn mouse_owned(&self) -> bool {
        self.held[2..].iter().any(|held| held.owned)
    }
    pub fn keyboard_owned(&self) -> bool {
        self.held[..2].iter().any(|held| held.owned)
    }
    pub fn can_recover_keyboard(&self, physical_held: u16) -> bool {
        // Async state alone cannot prove a suppressed suffix-up was delivered.
        // Keep ownership until the actual callback drains that release.
        physical_held == 0 && !self.keyboard_owned()
    }
    pub fn unrelated_key(&mut self) {
        self.mask_alt = false;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn matched_pair_is_consumed_and_fires_only_once_on_release() {
        let mut p = Policy::default();
        let c = Context {
            foreground: 100,
            ..Context::default()
        };
        p.alt_down(Alt::Left, c);
        assert_eq!(
            p.pair(0, true, true, c),
            Decision {
                consume: true,
                ..Decision::default()
            }
        );
        assert!(!p.pair(0, true, true, c).release);
        assert_eq!(
            p.pair(0, false, true, c),
            Decision {
                consume: true,
                release: true,
                mask_alt: false,
                context: c,
            }
        );
        assert!(!p.pair(0, false, true, c).consume);
        assert!(p.alt_up(Alt::Left));
        assert!(!p.alt_up(Alt::Left));
    }
    #[test]
    fn unbound_pairs_pass_and_a_late_binding_does_not_own_the_release() {
        let mut p = Policy::default();
        let c = Context::default();
        assert!(!p.pair(2, true, false, c).consume);
        assert!(!p.pair(2, false, true, c).consume);
    }
    #[test]
    fn context_change_keeps_owned_up_but_discards_action() {
        for c in [
            Context {
                foreground: 1,
                ..Context::default()
            },
            Context {
                generation: 1,
                ..Context::default()
            },
            Context {
                capture: 1,
                ..Context::default()
            },
            Context {
                recording: 2,
                ..Context::default()
            },
            Context {
                blocked: true,
                ..Context::default()
            },
        ] {
            let mut p = Policy::default();
            p.pair(3, true, true, Context::default());
            assert_eq!(
                p.pair(3, false, false, c),
                Decision {
                    consume: true,
                    ..Decision::default()
                }
            );
        }
    }
    #[test]
    fn settings_suppresses_actions_but_recording_context_can_pair() {
        let mut p = Policy::default();
        let c = Context {
            blocked: true,
            foreground: 100,
            ..Context::default()
        };
        p.alt_down(Alt::Left, c);
        p.pair(1, true, true, c);
        assert!(!p.pair(1, false, true, c).release);
        let c = Context {
            recording: 9,
            ..Context::default()
        };
        p.pair(2, true, true, c);
        assert!(p.pair(2, false, true, c).release);
    }
    #[test]
    fn unrelated_alt_chord_does_not_receive_a_menu_mask() {
        let mut p = Policy::default();
        let c = Context {
            foreground: 100,
            ..Context::default()
        };
        p.alt_down(Alt::Left, c);
        p.pair(0, true, true, c);
        p.unrelated_key();
        assert!(!p.alt_up(Alt::Left));
    }
}

#[cfg(test)]
mod next_intent_tests {
    use super::*;
    #[test]
    fn priority_keyboard_survives_an_older_capture_ending() {
        let mut p = Policy::default();
        let c = Context {
            foreground: 100,
            capture: 41,
            ..Context::default()
        };
        p.alt_down(Alt::Left, c);
        p.pair(1, true, true, c);
        assert!(p.pair(1, false, true, Context { capture: 0, ..c }).release);
    }
    #[test]
    fn mouse_ownership_drains_after_disabled_binding_release() {
        let mut p = Policy::default();
        p.pair(2, true, true, Context::default());
        assert!(p.mouse_owned());
        assert!(
            p.pair(
                2,
                false,
                false,
                Context {
                    generation: 1,
                    ..Context::default()
                }
            )
            .consume
        );
        assert!(!p.mouse_owned());
    }
}

#[cfg(test)]
mod focus_context_tests {
    use super::*;
    #[test]
    fn known_same_foreground_edit_focus_change_discards_the_pair() {
        let mut policy = Policy::default();
        let before = Context {
            foreground: 100,
            focus: 101,
            ..Context::default()
        };
        policy.alt_down(Alt::Left, before);
        policy.pair(0, true, true, before);
        assert!(
            !policy
                .pair(
                    0,
                    false,
                    true,
                    Context {
                        focus: 102,
                        ..before
                    }
                )
                .release
        );
    }
    #[test]
    fn unavailable_metadata_does_not_invent_focus_and_retains_known_anchor() {
        let mut policy = Policy::default();
        let before = Context {
            foreground: 100,
            focus: 101,
            ..Context::default()
        };
        policy.alt_down(Alt::Left, before);
        policy.pair(0, true, true, before);
        let up = policy.pair(0, false, true, Context { focus: 0, ..before });
        assert!(up.release);
        assert_eq!(up.context.focus, 101);
        assert!(!up.context.matches(Context {
            focus: 102,
            ..before
        }));
    }
}

#[cfg(test)]
mod recovery_tests {
    use super::*;
    #[test]
    fn owned_suffix_keeps_the_release_even_if_async_state_reports_up() {
        let mut p = Policy::default();
        let c = Context {
            foreground: 100,
            ..Context::default()
        };
        p.alt_down(Alt::Left, c);
        p.pair(0, true, true, c);
        assert!(!p.can_recover_keyboard(HELD_D));
        assert!(!p.can_recover_keyboard(0));
        assert!(p.keyboard_owned());
        assert!(p.pair(0, false, true, c).release);
    }
    #[test]
    fn modifier_release_does_not_discard_a_held_suffix() {
        let mut p = Policy::default();
        let c = Context {
            foreground: 100,
            ..Context::default()
        };
        p.alt_down(Alt::Left, c);
        p.pair(0, true, true, c);
        assert!(p.alt_up(Alt::Left));
        assert!(!p.can_recover_keyboard(0));
        assert!(p.pair(0, false, true, c).release);
        assert!(p.can_recover_keyboard(0));
    }
    #[test]
    fn only_keyboard_ownership_and_relevant_held_keys_defer_recovery() {
        let mut p = Policy::default();
        let c = Context::default();
        p.pair(2, true, true, c);
        assert!(p.can_recover_keyboard(0));
        assert!(!p.can_recover_keyboard(HELD_S));
        assert!(p.mouse_owned());
        assert!(p.pair(2, false, true, c).release);
    }
    #[test]
    fn release_hints_distinguish_both_sides_and_ignore_unrelated_keys() {
        for (generic, left, right, scan) in [
            (0x12, 0xa4, 0xa5, 0),
            (0x11, 0xa2, 0xa3, 0),
            (0x10, 0xa0, 0xa1, 0x36),
        ] {
            assert_ne!(
                recovery_key_bit(left, 0, false),
                recovery_key_bit(right, 0, false)
            );
            assert_eq!(
                recovery_key_bit(generic, 0, false),
                recovery_key_bit(left, 0, false)
            );
            assert_eq!(
                recovery_key_bit(generic, scan, true),
                recovery_key_bit(right, 0, false)
            );
        }
        assert_eq!(recovery_key_bit(0x41, 0, false), 0);
    }
}

#[cfg(test)]
mod alt_anchor_tests {
    use super::*;
    fn source() -> Context {
        Context {
            generation: 7,
            foreground: 100,
            focus: 101,
            recording: 0,
            ..Context::default()
        }
    }
    fn pair(p: &mut Policy, c: Context) -> Decision {
        assert!(p.pair(0, true, true, c).consume);
        let up = p.pair(0, false, true, c);
        assert!(up.consume);
        up
    }
    #[test]
    fn either_alt_side_anchors_a_single_source_action() {
        for side in [Alt::Left, Alt::Right] {
            let mut p = Policy::default();
            p.alt_down(side, source());
            assert!(pair(&mut p, source()).release);
            assert!(p.alt_up(side));
        }
    }
    #[test]
    fn repeat_and_second_alt_do_not_reanchor_after_a_source_change() {
        for second in [Alt::Left, Alt::Right] {
            let mut p = Policy::default();
            p.alt_down(Alt::Left, source());
            let changed = Context {
                foreground: 200,
                focus: 201,
                ..source()
            };
            p.alt_down(second, changed);
            assert!(!pair(&mut p, changed).release);
        }
    }
    #[test]
    fn first_alt_up_keeps_other_side_anchor_and_final_up_masks_once() {
        let mut p = Policy::default();
        p.alt_down(Alt::Left, source());
        p.alt_down(Alt::Right, source());
        assert!(!p.alt_up(Alt::Left));
        assert!(pair(&mut p, source()).release);
        assert!(p.alt_up(Alt::Right));
        assert!(!p.alt_up(Alt::Right));
    }
    #[test]
    fn final_alt_up_requires_a_new_anchor_for_the_next_suffix() {
        let mut p = Policy::default();
        p.alt_down(Alt::Left, source());
        assert!(!p.alt_up(Alt::Left));
        assert!(!pair(&mut p, source()).release);
    }
    #[test]
    fn alt_up_before_suffix_up_preserves_the_owned_release() {
        let mut p = Policy::default();
        p.alt_down(Alt::Right, source());
        p.pair(1, true, true, source());
        assert!(p.alt_up(Alt::Right));
        let up = p.pair(1, false, false, source());
        assert!(up.consume && up.release);
        assert!(!p.pair(1, false, false, source()).consume);
    }
    #[test]
    fn every_anchor_identity_field_is_checked_before_the_fresh_suffix() {
        for changed in [
            Context {
                foreground: 200,
                ..source()
            },
            Context {
                focus: 102,
                ..source()
            },
            Context {
                focus: 0,
                ..source()
            },
            Context {
                generation: 8,
                ..source()
            },
            Context {
                recording: 9,
                ..source()
            },
            Context {
                blocked: true,
                ..source()
            },
        ] {
            let mut p = Policy::default();
            p.alt_down(Alt::Left, source());
            assert!(p.pair(0, true, true, changed).consume);
            let up = p.pair(0, false, true, source());
            assert!(up.consume && !up.release);
        }
    }
    #[test]
    fn old_capture_ending_does_not_change_the_alt_anchor() {
        let mut p = Policy::default();
        p.alt_down(
            Alt::Left,
            Context {
                capture: 50,
                ..source()
            },
        );
        p.pair(
            1,
            true,
            true,
            Context {
                capture: 51,
                ..source()
            },
        );
        let up = p.pair(1, false, true, source());
        assert!(up.release);
        assert_eq!(up.context.capture, 0);
    }
    #[test]
    fn missing_alt_or_missing_foreground_consumes_without_an_action() {
        let mut p = Policy::default();
        assert!(!pair(&mut p, source()).release);
        p.alt_down(
            Alt::Left,
            Context {
                foreground: 0,
                ..source()
            },
        );
        assert!(!pair(&mut p, source()).release);
    }
    #[test]
    fn ordinary_or_extra_modifier_chords_are_not_claimed() {
        let mut p = Policy::default();
        p.alt_down(Alt::Left, source());
        assert!(!p.pair(0, true, false, source()).consume);
        assert!(!p.pair(0, false, true, source()).consume);
        p.unrelated_key();
        assert!(!p.alt_up(Alt::Left));
    }
    #[test]
    fn observed_focus_change_on_repeat_cannot_be_undone_before_release() {
        let mut p = Policy::default();
        p.alt_down(Alt::Left, source());
        p.pair(0, true, true, source());
        assert!(
            p.pair(
                0,
                true,
                true,
                Context {
                    focus: 102,
                    ..source()
                }
            )
            .consume
        );
        let up = p.pair(0, false, true, source());
        assert!(up.consume && !up.release);
    }
    #[test]
    fn recovery_reset_never_abandons_an_owned_suffix() {
        let mut p = Policy::default();
        p.alt_down(Alt::Left, source());
        p.pair(0, true, true, source());
        p.reset_alt_anchor();
        assert!(p.pair(0, false, true, source()).release);
        assert!(p.alt_up(Alt::Left));
        p.alt_down(Alt::Right, source());
        p.reset_alt_anchor();
        assert!(!pair(&mut p, source()).release);
    }
    #[test]
    fn alt_fallback_requires_the_same_observed_and_physical_side() {
        for side in [Alt::Left, Alt::Right] {
            let mut p = Policy::default();
            p.alt_down(side, source());
            let left = matches!(side, Alt::Left);
            assert!(p.tracked_alt_down(left, !left));
            assert!(!p.tracked_alt_down(!left, left));
            assert!(!p.tracked_alt_down(false, false));
        }
    }
    #[test]
    fn stale_alt_observation_cannot_claim_ordinary_d() {
        let mut p = Policy::default();
        p.alt_down(Alt::Right, source());
        let exact = p.tracked_alt_down(false, false);
        assert!(!p.pair(0, true, exact, source()).consume);
        assert!(!p.pair(0, false, exact, source()).consume);
    }
    #[test]
    fn physical_alt_without_an_observed_side_cannot_arm_fallback() {
        let mut p = Policy::default();
        assert!(!p.tracked_alt_down(true, true));
        p.alt_down(Alt::Left, source());
        p.alt_up(Alt::Left);
        assert!(!p.tracked_alt_down(true, false));
    }
    #[test]
    fn other_alt_release_keeps_the_live_side_and_original_source() {
        let mut p = Policy::default();
        p.alt_down(Alt::Left, source());
        p.alt_down(Alt::Right, source());
        assert!(!p.alt_up(Alt::Left));
        let exact = p.tracked_alt_down(false, true);
        assert!(exact);
        assert!(p.pair(0, true, exact, source()).consume);
        assert!(p.pair(0, false, exact, source()).release);
        assert!(p.alt_up(Alt::Right));
        assert!(!p.tracked_alt_down(false, true));
    }
    #[test]
    fn physical_alt_fallback_cannot_bypass_the_source_anchor() {
        let mut p = Policy::default();
        p.alt_down(Alt::Right, source());
        let changed = Context {
            foreground: 999,
            ..source()
        };
        let exact = p.tracked_alt_down(false, true);
        assert!(p.pair(0, true, exact, changed).consume);
        let up = p.pair(0, false, exact, changed);
        assert!(up.consume && !up.release);
    }
}
