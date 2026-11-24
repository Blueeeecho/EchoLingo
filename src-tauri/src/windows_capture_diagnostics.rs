//! Opt-in, bounded scalar diagnostics. No identifiers, input data or coordinates.
#[derive(Default)]
pub struct HostDiagnostics {
    pub enabled: bool,
    pub first: u32,
    pub first_error: u32,
    pub cleanup: u32,
    pub cleanup_error: u32,
    pub events: u32,
    pub cleaning: bool,
}
impl HostDiagnostics {
    pub fn event(&mut self, bit: u32) {
        if self.enabled {
            self.events |= bit;
        }
    }
    pub fn fail(&mut self, stage: u32, error: u32) {
        if !self.enabled {
            return;
        }
        let (reason, code) = if self.cleaning {
            (&mut self.cleanup, &mut self.cleanup_error)
        } else {
            (&mut self.first, &mut self.first_error)
        };
        if *reason == 0 {
            *reason = stage;
            *code = error;
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn cleanup_and_later_errors_never_replace_first_failure() {
        let mut d = HostDiagnostics {
            enabled: true,
            ..Default::default()
        };
        d.fail(1, 5);
        d.fail(2, 0);
        d.cleaning = true;
        d.fail(7, 0);
        d.fail(1, 6);
        assert_eq!(
            (d.first, d.first_error, d.cleanup, d.cleanup_error),
            (1, 5, 7, 0)
        );
    }
    #[test]
    fn disabled_diagnostics_remain_empty() {
        let mut d = HostDiagnostics::default();
        d.event(1);
        d.fail(1, 5);
        d.cleaning = true;
        d.fail(7, 0);
        assert_eq!(
            (d.first, d.first_error, d.cleanup, d.cleanup_error, d.events),
            (0, 0, 0, 0, 0)
        );
    }
    #[test]
    fn observations_are_bounded_and_cleanup_only_is_distinct() {
        let mut d = HostDiagnostics {
            enabled: true,
            ..Default::default()
        };
        for _ in 0..10000 {
            d.event(1);
            d.event(2);
        }
        d.cleaning = true;
        d.fail(7, 0);
        assert_eq!((d.events, d.first, d.cleanup), (3, 0, 7));
    }
}
