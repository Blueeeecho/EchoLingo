//! Scalar policy for Windows priority keyboard and opt-in side-button pairs.
//! The native callback owns this state; actions run only after a paired release.

pub const PRIORITY_D: u8 = 1;
pub const PRIORITY_S: u8 = 2;
pub const MOUSE_X1: u8 = 4;
pub const MOUSE_X2: u8 = 8;
pub const MOUSE_X1_ID: u32 = 0x8000_0001;
pub const MOUSE_X2_ID: u32 = 0x8000_0002;

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
}
impl Policy {
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
        let held = &mut self.held[slot];
        if down {
            if held.owned {
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
                accepted: !context.blocked,
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
    pub fn alt_release(&mut self) -> bool {
        std::mem::take(&mut self.mask_alt)
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
        let c = Context::default();
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
                ..Decision::default()
            }
        );
        assert!(!p.pair(0, false, true, c).consume);
        assert!(p.alt_release());
        assert!(!p.alt_release());
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
            ..Context::default()
        };
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
        p.pair(0, true, true, Context::default());
        p.unrelated_key();
        assert!(!p.alt_release());
    }
}

#[cfg(test)]
mod next_intent_tests {
    use super::*;
    #[test]
    fn priority_keyboard_survives_an_older_capture_ending() {
        let mut p = Policy::default();
        p.pair(
            1,
            true,
            true,
            Context {
                capture: 41,
                ..Context::default()
            },
        );
        assert!(p.pair(1, false, true, Context::default()).release);
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
            focus: 101,
            ..Context::default()
        };
        policy.pair(0, true, true, before);
        let up = policy.pair(0, false, true, Context::default());
        assert!(up.release);
        assert_eq!(up.context.focus, 101);
        assert!(!up.context.matches(Context {
            focus: 102,
            ..Context::default()
        }));
    }
}
