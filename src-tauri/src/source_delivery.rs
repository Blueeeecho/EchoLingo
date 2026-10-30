//! One unacknowledged capture, in process memory only. No text is logged or saved.
pub struct Delivery<T> {
    pub id: u64,
    pub epoch: u64,
    pub payload: T,
}

pub struct SourceDeliveries<T> {
    epoch: u64,
    next_id: u64,
    pending: Option<Delivery<T>>,
}

impl<T> Default for SourceDeliveries<T> {
    fn default() -> Self {
        Self {
            epoch: 0,
            next_id: 0,
            pending: None,
        }
    }
}

impl<T: Clone> SourceDeliveries<T> {
    pub fn advance(&mut self, epoch: u64) {
        if epoch > self.epoch {
            self.epoch = epoch;
            self.pending = None;
        }
    }

    pub fn publish(&mut self, epoch: u64, payload: T) -> Result<Delivery<T>, String> {
        if epoch != self.epoch {
            return Err("CANCELLED: Source presentation was superseded".into());
        }
        let id = self
            .next_id
            .checked_add(1)
            .filter(|id| *id <= 9_007_199_254_740_991)
            .ok_or("捕获交付编号已用尽，请重新启动应用")?;
        self.next_id = id;
        self.pending = Some(Delivery {
            id,
            epoch,
            payload: payload.clone(),
        });
        Ok(Delivery { id, epoch, payload })
    }

    pub fn peek(&self, epoch: u64) -> Option<Delivery<T>> {
        self.pending
            .as_ref()
            .filter(|item| item.epoch == epoch && epoch == self.epoch)
            .map(|item| Delivery {
                id: item.id,
                epoch: item.epoch,
                payload: item.payload.clone(),
            })
    }

    pub fn retry(&self, id: u64, epoch: u64, current_epoch: u64) -> Option<Delivery<T>> {
        if current_epoch != epoch {
            return None;
        }
        self.peek(epoch).filter(|delivery| delivery.id == id)
    }

    pub fn acknowledge(&mut self, id: u64) -> bool {
        if self.pending.as_ref().is_some_and(|item| item.id == id) {
            self.pending = None;
            true
        } else {
            false
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_result_before_any_listener_is_available_until_matching_ack() {
        let mut queue = SourceDeliveries::default();
        queue.advance(3);
        let sent = queue.publish(3, ("generated source", true)).unwrap();
        assert_eq!(queue.peek(3).unwrap().payload, ("generated source", true));
        assert_eq!(queue.peek(3).unwrap().id, sent.id);
        assert!(queue.acknowledge(sent.id));
        assert!(queue.peek(3).is_none());
        assert!(!queue.acknowledge(sent.id));
    }

    #[test]
    fn stale_ack_and_old_task_cannot_remove_or_replace_a_newer_result() {
        let mut queue = SourceDeliveries::default();
        queue.advance(1);
        let old = queue.publish(1, "old").unwrap();
        queue.advance(2);
        let new = queue.publish(2, "new").unwrap();
        assert!(new.id > old.id);
        assert!(!queue.acknowledge(old.id));
        assert!(queue.publish(1, "late old").is_err());
        assert_eq!(queue.peek(2).unwrap().payload, "new");
        assert!(queue.peek(1).is_none());
    }

    #[test]
    fn management_hide_or_new_task_invalidates_the_unacknowledged_source() {
        let mut queue = SourceDeliveries::default();
        queue.advance(4);
        queue.publish(4, "generated").unwrap();
        queue.advance(5);
        queue.advance(4);
        assert!(queue.peek(4).is_none());
        assert!(queue.publish(4, "stale").is_err());
        assert!(queue.publish(6, "unannounced future").is_err());
    }

    #[test]
    fn runtime_retry_reuses_identity_and_stops_after_ack_hide_or_newer_delivery() {
        let mut queue = SourceDeliveries::default();
        queue.advance(4);
        let old = queue.publish(4, "old").unwrap();
        let retry = queue.retry(old.id, 4, 4).unwrap();
        assert_eq!(retry.id, old.id);
        assert_eq!(retry.payload, "old");
        assert!(queue.retry(old.id, 4, 5).is_none());
        let new = queue.publish(4, "new").unwrap();
        assert!(queue.retry(old.id, 4, 4).is_none());
        assert!(queue.retry(new.id, 4, 4).is_some());
        assert!(queue.acknowledge(new.id));
        assert!(queue.retry(new.id, 4, 4).is_none());
        let last = queue.publish(4, "last").unwrap();
        queue.advance(5);
        assert!(queue.retry(last.id, 4, 5).is_none());
    }

    #[test]
    fn delivery_ids_never_wrap_or_exceed_javascript_safe_integer_range() {
        let mut queue = SourceDeliveries::<&str>::default();
        queue.next_id = 9_007_199_254_740_990;
        let last = queue.publish(0, "last").unwrap();
        assert_eq!(last.id, 9_007_199_254_740_991);
        assert!(queue.publish(0, "overflow").is_err());
        assert_eq!(queue.peek(0).unwrap().id, last.id);
    }
}
