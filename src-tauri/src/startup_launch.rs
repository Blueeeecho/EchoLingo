//! Keep the most recent explicit relaunch until application setup is complete.
//! Readiness and the pending request share the caller's mutex, avoiding a
//! check-then-store race between single-instance delivery and setup completion.
#[derive(Default)]
pub struct Requests {
    ready: bool,
    pending: Option<Vec<String>>,
}

impl Requests {
    pub fn submit(&mut self, args: Vec<String>) -> Option<Vec<String>> {
        if self.ready {
            Some(args)
        } else {
            self.pending = Some(args);
            None
        }
    }

    pub fn mark_ready(&mut self) -> Option<Vec<String>> {
        self.ready = true;
        self.pending.take()
    }
}

#[cfg(test)]
mod tests {
    use super::Requests;

    fn args(flag: &str) -> Vec<String> {
        vec!["EchoLingo".into(), flag.into()]
    }

    #[test]
    fn cold_start_stays_silent_without_an_explicit_relaunch() {
        let mut requests = Requests::default();
        assert!(requests.mark_ready().is_none());
        assert!(requests.mark_ready().is_none());
    }

    #[test]
    fn early_relaunch_is_delivered_once_after_setup() {
        let mut requests = Requests::default();
        assert!(requests.submit(args("--configure-shortcuts")).is_none());
        assert_eq!(requests.mark_ready(), Some(args("--configure-shortcuts")));
        assert!(requests.mark_ready().is_none());
    }

    #[test]
    fn relaunches_are_bounded_and_the_latest_intent_wins() {
        let mut requests = Requests::default();
        assert!(requests.submit(args("--permission-diagnostics")).is_none());
        assert!(requests.submit(args("--configure-shortcuts")).is_none());
        assert_eq!(requests.mark_ready(), Some(args("--configure-shortcuts")));
    }

    #[test]
    fn ready_relaunches_are_dispatched_without_queueing() {
        let mut requests = Requests::default();
        requests.mark_ready();
        assert_eq!(
            requests.submit(args("--configure-shortcuts")),
            Some(args("--configure-shortcuts"))
        );
        assert!(requests.mark_ready().is_none());
    }
}
