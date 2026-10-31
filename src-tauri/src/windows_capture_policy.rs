//! Pure physical-coordinate capture policy, ported from the production C# oracle.
//! No OS handles, pixels, input injection, clipboard access or global state.
#![allow(dead_code)]

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Point {
    pub x: i32,
    pub y: i32,
}
impl Point {
    pub const fn new(x: i32, y: i32) -> Self {
        Self { x, y }
    }
}
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}
impl Rect {
    pub const fn new(x: i32, y: i32, width: i32, height: i32) -> Self {
        Self {
            x,
            y,
            width,
            height,
        }
    }
    pub fn right(self) -> i32 {
        self.x.saturating_add(self.width)
    }
    pub fn bottom(self) -> i32 {
        self.y.saturating_add(self.height)
    }
    pub fn is_empty(self) -> bool {
        self.width <= 0 || self.height <= 0
    }
    pub fn valid(self) -> bool {
        !self.is_empty()
            && self.x.checked_add(self.width).is_some()
            && self.y.checked_add(self.height).is_some()
    }
    pub fn contains(self, p: Point) -> bool {
        self.valid() && p.x >= self.x && p.x < self.right() && p.y >= self.y && p.y < self.bottom()
    }
    pub fn contains_rect(self, r: Rect) -> bool {
        self.valid()
            && r.valid()
            && r.x >= self.x
            && r.y >= self.y
            && r.right() <= self.right()
            && r.bottom() <= self.bottom()
    }
    pub fn from_ltrb(left: i32, top: i32, right: i32, bottom: i32) -> Self {
        match (right.checked_sub(left), bottom.checked_sub(top)) {
            (Some(w), Some(h)) if w > 0 && h > 0 => Self::new(left, top, w, h),
            _ => Self::default(),
        }
    }
    pub fn intersect(self, other: Self) -> Self {
        if self.is_empty() || other.is_empty() {
            return Self::default();
        }
        Self::from_ltrb(
            self.x.max(other.x),
            self.y.max(other.y),
            self.right().min(other.right()),
            self.bottom().min(other.bottom()),
        )
    }
    pub fn union(self, other: Self) -> Option<Self> {
        let result = Self::from_ltrb(
            self.x.min(other.x),
            self.y.min(other.y),
            self.right().max(other.right()),
            self.bottom().max(other.bottom()),
        );
        result.valid().then_some(result)
    }
}

/// F1 is additive: translation/OCR retain their drag-only selection contract.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum CapturePurpose {
    #[default]
    Region,
    Screenshot,
}

/// Scalar identity only; never contains titles, text, or window contents.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CaptureWindowTarget {
    pub window: usize,
    pub process: u32,
    pub thread: u32,
    pub frame: Rect,
}

#[derive(Clone, Debug)]
pub struct CaptureSelectionState {
    screens: Vec<Rect>,
    origin: Point,
    purpose: CapturePurpose,
    click_threshold: i32,
    drag_exceeded: bool,
    candidate: Option<CaptureWindowTarget>,
    pressed_window: Option<CaptureWindowTarget>,
    pub selected_window: Option<CaptureWindowTarget>,
    pub desktop: Rect,
    pub dragging: bool,
    pub finished: bool,
    pub cancelled: bool,
    pub highlighted: i32,
    pub selected: Rect,
}
impl CaptureSelectionState {
    pub fn new(screens: Vec<Rect>, pointer: Point) -> Result<Self, &'static str> {
        Self::with_purpose(screens, pointer, CapturePurpose::Region)
    }
    pub fn with_purpose(screens: Vec<Rect>, pointer: Point, purpose: CapturePurpose) -> Result<Self, &'static str> {
        let mut desktop = *screens.first().ok_or("CAPTURE: No display is available.")?;
        for screen in &screens {
            if !screen.valid() {
                return Err("CAPTURE: Invalid display geometry.");
            }
            desktop = desktop
                .union(*screen)
                .ok_or("CAPTURE: Invalid virtual desktop geometry.")?;
        }
        let mut state = Self {
            screens,
            origin: Point::default(),
            purpose,
            click_threshold: 4,
            drag_exceeded: false,
            candidate: None,
            pressed_window: None,
            selected_window: None,
            desktop,
            dragging: false,
            finished: false,
            cancelled: false,
            highlighted: -1,
            selected: Rect::default(),
        };
        state.move_to(pointer);
        Ok(state)
    }
    /// Supplied from a fresh native hit-test immediately before button down.
    pub fn set_window_candidate(&mut self, candidate: Option<CaptureWindowTarget>, dpi: u32) {
        if !self.dragging && !self.finished {
            self.candidate = candidate;
            // Four logical pixels of jitter on the display where the press began.
            self.click_threshold = ((4 * dpi.clamp(96, 768) + 95) / 96) as i32;
        }
    }
    pub fn note_drag_excursion(&mut self, dx: i32, dy: i32) {
        if self.dragging && !self.finished {
            self.drag_exceeded |= dx > self.click_threshold || dy > self.click_threshold;
        }
    }
    pub fn is_window_click(&self) -> bool {
        self.purpose == CapturePurpose::Screenshot && !self.drag_exceeded
    }
    fn clamp(&self, p: Point) -> Point {
        Point::new(
            p.x.clamp(self.desktop.x, self.desktop.right() - 1),
            p.y.clamp(self.desktop.y, self.desktop.bottom() - 1),
        )
    }
    pub fn move_to(&mut self, p: Point) {
        if self.finished {
            return;
        }
        self.highlighted = self
            .screens
            .iter()
            .position(|r| r.contains(p))
            .map_or(-1, |i| i as i32);
        if self.dragging {
            let end = self.clamp(p);
            // Sticky: moving away and returning must never turn a drag into a click.
            self.drag_exceeded |= (i64::from(p.x) - i64::from(self.origin.x)).abs() > i64::from(self.click_threshold)
                || (i64::from(p.y) - i64::from(self.origin.y)).abs() > i64::from(self.click_threshold);
            // Retain zero-width/height while dragging, just like Rectangle.FromLTRB.
            self.selected = Rect::new(
                self.origin.x.min(end.x),
                self.origin.y.min(end.y),
                (i64::from(end.x) - i64::from(self.origin.x)).unsigned_abs() as i32,
                (i64::from(end.y) - i64::from(self.origin.y)).unsigned_abs() as i32,
            );
        }
    }
    pub fn begin(&mut self, p: Point) {
        if self.finished || self.dragging {
            return;
        }
        self.move_to(p);
        if self.highlighted < 0 {
            return;
        }
        self.origin = self.clamp(p);
        self.drag_exceeded = false;
        self.pressed_window = self.candidate.filter(|target| target.frame.contains(p));
        self.selected_window = None;
        self.selected = Rect::default();
        self.dragging = true;
    }
    pub fn end(&mut self, p: Point) {
        if self.finished || !self.dragging {
            return;
        }
        self.move_to(p);
        self.dragging = false;
        self.finished = true;
        if self.is_window_click() {
            if let Some(target) = self.pressed_window {
                self.selected = target.frame.intersect(self.desktop);
                self.selected_window = Some(target);
            } else {
                self.selected = Rect::default();
            }
        }
        self.cancelled = self.selected.width < 3 || self.selected.height < 3;
    }
    pub fn cancel(&mut self) {
        if !self.finished {
            self.dragging = false;
            self.finished = true;
            self.cancelled = true;
        }
    }
    pub fn expire(&mut self, elapsed_ms: i64) {
        if elapsed_ms >= 120_000 {
            self.cancel();
        }
    }
}

#[derive(Clone, Debug)]
pub struct CaptureInputPolicy {
    initial_left: bool,
    initial_right: bool,
    initial_escape: bool,
    stopping_at: Option<i64>,
    pub armed: bool,
    pub left_swallowed: bool,
    pub right_swallowed: bool,
    pub escape_swallowed: bool,
    pub escape_cancelled: bool,
    pub release_grace_exceeded: bool,
}
impl Default for CaptureInputPolicy {
    fn default() -> Self {
        Self {
            initial_left: false,
            initial_right: false,
            initial_escape: false,
            stopping_at: None,
            armed: false,
            left_swallowed: false,
            right_swallowed: false,
            escape_swallowed: false,
            escape_cancelled: false,
            release_grace_exceeded: false,
        }
    }
}
impl CaptureInputPolicy {
    pub fn pending_release(&self) -> bool {
        self.left_swallowed || self.right_swallowed || self.escape_swallowed
    }
    pub fn plane_ready(&self, state: &CaptureSelectionState) -> bool {
        self.armed && !state.finished
    }
    pub fn resync_released_buttons(&mut self, left: bool, right: bool) {
        if self.armed || self.pending_release() {
            return;
        }
        self.initial_left = left;
        self.initial_right = right;
        self.armed = !left && !right;
    }
    pub fn resync_escape(&mut self, down: bool) {
        if self.escape_swallowed {
            return;
        }
        self.initial_escape = down;
        if down {
            self.escape_cancelled = true;
        }
    }
    pub fn escape(&mut self, down: bool, up: bool) -> bool {
        if self.initial_escape {
            if up {
                self.initial_escape = false;
            }
            return false;
        }
        if down {
            self.escape_swallowed = true;
            self.escape_cancelled = true;
            return true;
        }
        if up && self.escape_swallowed {
            self.escape_swallowed = false;
            return true;
        }
        false
    }
    pub fn mouse(&mut self, kind: u32, p: Point, state: &mut CaptureSelectionState) -> bool {
        if !self.armed {
            let fresh = kind == 0x201 || kind == 0x204;
            if kind == 0x201 || kind == 0x202 {
                self.initial_left = false;
            }
            if kind == 0x204 || kind == 0x205 {
                self.initial_right = false;
            }
            self.armed = !self.initial_left && !self.initial_right;
            if !self.armed || !fresh {
                return false;
            }
        }
        if kind == 0x202 && self.left_swallowed {
            self.left_swallowed = false;
            state.end(p);
            return true;
        }
        if kind == 0x205 && self.right_swallowed {
            self.right_swallowed = false;
            return true;
        }
        if state.finished {
            return false;
        }
        if kind == 0x201 {
            state.begin(p);
            self.left_swallowed = true;
            return true;
        }
        if kind == 0x204 {
            state.cancel();
            self.right_swallowed = true;
            return true;
        }
        state.move_to(p);
        false
    }
    pub fn abort_owned_mouse(&mut self, kind: u32, state: &mut CaptureSelectionState) {
        match kind {
            0x201 => self.left_swallowed = true,
            0x204 => self.right_swallowed = true,
            0x202 => self.left_swallowed = false,
            0x205 => self.right_swallowed = false,
            _ => {}
        }
        state.cancel();
    }
    pub fn may_stop(&mut self, finished: bool, elapsed_ms: i64) -> bool {
        if !finished {
            return false;
        }
        let start = *self.stopping_at.get_or_insert(elapsed_ms);
        if !self.pending_release() {
            return true;
        }
        if elapsed_ms.saturating_sub(start) < 500 {
            return false;
        }
        self.release_grace_exceeded = true;
        true
    }
}

pub const OUTLINE_THICKNESS: i32 = 2;
pub fn outline_edges(outline: Rect, display: Rect) -> [Rect; 4] {
    if outline.is_empty() {
        return [Rect::default(); 4];
    }
    let h = OUTLINE_THICKNESS.min(outline.height);
    let v = OUTLINE_THICKNESS.min(outline.width);
    [
        Rect::new(outline.x, outline.y, outline.width, h),
        Rect::new(outline.x, outline.bottom() - h, outline.width, h),
        Rect::new(outline.x, outline.y + h, v, (outline.height - h * 2).max(0)),
        Rect::new(
            outline.right() - v,
            outline.y + h,
            v,
            (outline.height - h * 2).max(0),
        ),
    ]
    .map(|r| r.intersect(display))
}
#[derive(Clone, Copy, Debug)]
pub struct CaptureMagnifierSample {
    pub bounds: Rect,
    pub grabbed: Rect,
    pub copy_offset: Point,
}
impl CaptureMagnifierSample {
    pub const SIDE: i32 = 52;
    pub fn new(pointer: Point, desktop: Rect) -> Self {
        let bounds = Rect::new(
            pointer.x.saturating_sub(Self::SIDE / 2),
            pointer.y.saturating_sub(Self::SIDE / 2),
            Self::SIDE,
            Self::SIDE,
        );
        let grabbed = bounds.intersect(desktop);
        let copy_offset = Point::new(
            grabbed.x.saturating_sub(bounds.x),
            grabbed.y.saturating_sub(bounds.y),
        );
        Self {
            bounds,
            grabbed,
            copy_offset,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn state() -> CaptureSelectionState {
        CaptureSelectionState::new(vec![Rect::new(0, 0, 800, 600)], Point::default()).unwrap()
    }
    #[test]
    fn selection_oracle_negative_gaps_cross_screen_completion_timeout() {
        let screens = vec![
            Rect::new(0, 0, 1920, 1080),
            Rect::new(-2560, -300, 2560, 1440),
            Rect::new(100, -1200, 1600, 900),
        ];
        let mut s = CaptureSelectionState::new(screens.clone(), Point::new(-2000, 20)).unwrap();
        assert_eq!(s.highlighted, 1);
        assert!(!s.dragging && !s.finished);
        s.move_to(Point::new(300, -900));
        assert_eq!(s.highlighted, 2);
        s.move_to(Point::new(-2000, -900));
        assert_eq!(s.highlighted, -1);
        s.begin(Point::new(-2000, -900));
        assert!(!s.dragging);
        s.begin(Point::new(-100, 100));
        s.move_to(Point::new(200, 300));
        s.end(Point::new(300, 350));
        assert!(s.finished && !s.cancelled);
        assert_eq!(s.selected, Rect::new(-100, 100, 400, 250));
        let selected = s.selected;
        s.begin(Point::new(10, 10));
        s.move_to(Point::new(20, 20));
        s.cancel();
        assert_eq!(s.selected, selected);
        assert!(!s.cancelled);
        let mut reverse = CaptureSelectionState::new(screens, Point::default()).unwrap();
        reverse.begin(Point::new(500, 400));
        reverse.end(Point::new(-200, -100));
        assert_eq!(reverse.selected, Rect::new(-200, -100, 700, 500));
        let mut tiny = state();
        tiny.begin(Point::new(10, 10));
        tiny.end(Point::new(11, 30));
        assert!(tiny.cancelled);
        let mut timeout = state();
        timeout.expire(119999);
        assert!(!timeout.finished);
        timeout.expire(120000);
        assert!(timeout.cancelled);
        let mut cancel = state();
        cancel.begin(Point::new(10, 10));
        cancel.cancel();
        assert!(cancel.cancelled && !cancel.dragging);
    }
    #[test]
    fn selection_rejects_invalid_geometry_and_clamps_only_to_virtual_desktop() {
        assert!(CaptureSelectionState::new(vec![], Point::default()).is_err());
        for r in [
            Rect::new(0, 0, 0, 1),
            Rect::new(0, 0, 1, -1),
            Rect::new(i32::MAX, 0, 1, 1),
        ] {
            assert!(CaptureSelectionState::new(vec![r], Point::default()).is_err());
        }
        assert!(CaptureSelectionState::new(
            vec![
                Rect::new(i32::MIN, 0, 1, 1),
                Rect::new(i32::MAX - 1, 0, 1, 1)
            ],
            Point::default()
        )
        .is_err());
        let mut s = state();
        s.begin(Point::new(20, 20));
        s.end(Point::new(i32::MAX, i32::MIN));
        assert_eq!(s.selected, Rect::new(20, 0, 779, 20));
        assert!(!Rect::new(0, 0, 10, 10).contains(Point::new(10, 9)));
    }
    #[test]
    fn escape_oracle_pair_ownership_and_preheld_release() {
        let mut e = CaptureInputPolicy::default();
        assert!(e.escape(true, false) && e.escape_cancelled);
        assert!(e.escape(true, false) && e.escape(false, true) && !e.pending_release());
        assert!(!e.escape(false, true));
        let mut startup = CaptureInputPolicy::default();
        startup.resync_escape(true);
        assert!(
            startup.escape_cancelled && !startup.escape(false, true) && !startup.pending_release()
        );
        let mut pending = CaptureInputPolicy::default();
        pending.escape(true, false);
        pending.resync_escape(true);
        assert!(pending.escape(false, true));
    }
    #[test]
    fn mouse_oracle_resync_gap_preheld_and_fresh_down() {
        let mut s = state();
        let mut gap = CaptureInputPolicy::default();
        gap.resync_released_buttons(true, false);
        gap.resync_released_buttons(false, false);
        assert!(gap.armed && gap.mouse(0x201, Point::new(10, 10), &mut s));
        assert!(
            gap.mouse(0x202, Point::new(40, 40), &mut s) && s.finished && !gap.pending_release()
        );
        let mut held = CaptureInputPolicy::default();
        held.resync_released_buttons(true, false);
        assert!(!held.mouse(0x202, Point::new(10, 10), &mut s) && held.armed);
        let mut missed = CaptureInputPolicy::default();
        missed.resync_released_buttons(true, false);
        let mut next = state();
        assert!(missed.mouse(0x201, Point::new(20, 20), &mut next) && next.dragging);
        let mut both = CaptureInputPolicy::default();
        both.resync_released_buttons(true, true);
        let mut next = state();
        assert!(!both.mouse(0x202, Point::default(), &mut next));
        assert!(!both.armed);
        assert!(!both.mouse(0x205, Point::default(), &mut next));
        assert!(both.armed);
    }
    #[test]
    fn input_oracle_release_grace_handoff_abort_and_right_cancel() {
        let mut grace = CaptureInputPolicy::default();
        grace.escape(true, false);
        assert!(!grace.may_stop(true, 120000) && !grace.may_stop(true, 120499));
        assert!(grace.may_stop(true, 120500) && grace.release_grace_exceeded);
        let mut handoff = CaptureInputPolicy::default();
        handoff.resync_released_buttons(false, false);
        let mut cross = CaptureSelectionState::new(
            vec![Rect::new(-800, 0, 800, 600), Rect::new(0, 0, 800, 600)],
            Point::default(),
        )
        .unwrap();
        assert!(handoff.mouse(0x201, Point::new(-100, 100), &mut cross) && cross.dragging);
        assert!(
            handoff.mouse(0x202, Point::new(100, 200), &mut cross)
                && cross.finished
                && !handoff.pending_release()
        );
        assert_eq!(cross.selected, Rect::new(-100, 100, 200, 100));
        assert!(!handoff.mouse(0x202, Point::new(500, 500), &mut cross));
        assert_eq!(cross.selected, Rect::new(-100, 100, 200, 100));
        let mut reverse = CaptureInputPolicy::default();
        reverse.resync_released_buttons(false, false);
        let mut s = state();
        assert!(reverse.mouse(0x201, Point::new(20, 20), &mut s) && s.dragging);
        assert!(reverse.mouse(0x202, Point::new(80, 60), &mut s));
        assert_eq!(s.selected, Rect::new(20, 20, 60, 40));
        let mut abort = CaptureInputPolicy::default();
        let mut s = state();
        abort.resync_released_buttons(false, false);
        abort.abort_owned_mouse(0x201, &mut s);
        assert!(s.cancelled && abort.pending_release() && !abort.plane_ready(&s));
        assert!(abort.mouse(0x202, Point::default(), &mut s) && !abort.pending_release());
        let mut before = CaptureInputPolicy::default();
        let mut s = state();
        before.resync_released_buttons(true, false);
        assert!(!before.plane_ready(&s));
        assert!(
            !before.mouse(0x202, Point::default(), &mut s) && before.plane_ready(&s) && !s.dragging
        );
        assert!(
            before.mouse(0x204, Point::new(10, 10), &mut s)
                && s.cancelled
                && before.mouse(0x205, Point::new(10, 10), &mut s)
                && !before.pending_release()
        );
    }
    fn area(edges: [Rect; 4]) -> i64 {
        edges
            .iter()
            .map(|r| i64::from(r.width) * i64::from(r.height))
            .sum()
    }
    #[test]
    fn outline_oracle_thin_edges_clipped_without_artificial_screen_seams() {
        let display = Rect::new(-3840, -300, 3840, 2160);
        let border = outline_edges(display, display);
        assert_eq!(area(border), 2 * 2 * (3840 + 2160 - 4));
        assert!(area(border) < 3840 * 2160 / 100);
        for edge in border {
            assert!(display.contains_rect(edge) && edge.width.min(edge.height) <= 2);
        }
        let selection = Rect::new(-120, -150, 300, 400);
        let left = Rect::new(-1920, -1080, 1920, 1080);
        let right = Rect::new(0, 0, 1920, 1080);
        let le = outline_edges(selection, left);
        let re = outline_edges(selection, right);
        for e in le {
            if !e.is_empty() {
                assert!(left.contains_rect(e));
            }
        }
        for e in re {
            if !e.is_empty() {
                assert!(right.contains_rect(e));
            }
        }
        assert_eq!(le[0].width, 120);
        assert_eq!(re[1].width, 180);
        assert_eq!(
            area(outline_edges(selection, Rect::new(500, 500, 800, 600))),
            0
        );
        assert_eq!(area(outline_edges(Rect::default(), display)), 0);
        for e in outline_edges(Rect::new(10, 10, 1, 1), Rect::new(0, 0, 800, 600)) {
            assert!(e.width >= 0 && e.height >= 0);
        }
    }
    #[test]
    fn magnifier_oracle_200_assertions_preserve_pointer_center_and_edge_padding() {
        let mut checks = 0;
        for desktop in [
            Rect::new(0, 0, 1920, 1080),
            Rect::new(-2560, -1200, 4480, 2640),
        ] {
            let xs = [
                desktop.x,
                desktop.x + 13,
                desktop.x + desktop.width / 2,
                desktop.right() - 14,
                desktop.right() - 1,
            ];
            let ys = [
                desktop.y,
                desktop.y + 13,
                desktop.y + desktop.height / 2,
                desktop.bottom() - 14,
                desktop.bottom() - 1,
            ];
            for x in xs {
                for y in ys {
                    let p = Point::new(x, y);
                    let sample = CaptureMagnifierSample::new(p, desktop);
                    assert_eq!((sample.bounds.width, sample.bounds.height), (52, 52));
                    checks += 1;
                    assert!(sample.grabbed.valid() && desktop.contains_rect(sample.grabbed));
                    checks += 1;
                    assert!(Rect::new(0, 0, 52, 52).contains_rect(Rect::new(
                        sample.copy_offset.x,
                        sample.copy_offset.y,
                        sample.grabbed.width,
                        sample.grabbed.height
                    )));
                    checks += 1;
                    assert_eq!(
                        (
                            p.x - sample.grabbed.x + sample.copy_offset.x,
                            p.y - sample.grabbed.y + sample.copy_offset.y
                        ),
                        (26, 26)
                    );
                    checks += 1;
                }
            }
        }
        assert_eq!(checks, 200);
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CaptureDisplaySnapshot {
    pub device: String,
    pub bounds: Rect,
    pub dpi: u32,
}
#[derive(Clone, Debug)]
pub struct CaptureTopologyPolicy {
    displays: Vec<CaptureDisplaySnapshot>,
    pub awareness: i32,
    pub invalid: bool,
    pub reason: i32,
    pub before_dpi: u32,
    pub after_dpi: u32,
    pub invalidation_phase: i32,
}
impl CaptureTopologyPolicy {
    pub fn new(
        mut displays: Vec<CaptureDisplaySnapshot>,
        awareness: i32,
    ) -> Result<Self, &'static str> {
        displays.sort_by(|a, b| a.device.encode_utf16().cmp(b.device.encode_utf16()));
        if displays.is_empty()
            || displays.iter().enumerate().any(|(i, d)| {
                d.device.is_empty()
                    || !d.bounds.valid()
                    || d.dpi == 0
                    || (i > 0 && displays[i - 1].device == d.device)
            })
        {
            return Err("CAPTURE_DISPLAY_CHANGED: Invalid capture display metadata.");
        }
        Ok(Self {
            displays,
            awareness,
            invalid: false,
            reason: 0,
            before_dpi: 0,
            after_dpi: 0,
            invalidation_phase: 0,
        })
    }
    pub fn displays(&self) -> &[CaptureDisplaySnapshot] {
        &self.displays
    }
    pub fn invalidate(&mut self, source: i32, expected: u32, actual: u32, phase: i32) {
        if self.invalid {
            return;
        }
        self.reason = source;
        self.before_dpi = expected;
        self.after_dpi = actual;
        self.invalidation_phase = phase;
        self.invalid = true;
    }
    pub fn dpi_message_changes(expected: u32, message: i64) -> bool {
        expected == 0
            || (message & 0xffff) as u32 != expected
            || ((message >> 16) & 0xffff) as u32 != expected
    }
    pub fn matches(&self, other: &Self) -> bool {
        !self.invalid
            && !other.invalid
            && self.awareness == 2
            && other.awareness == 2
            && self.displays == other.displays
    }
}
/// Skipping a throttled repaint is not a request to hide its last complete frame.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CaptureFrameAction {
    Hide,
    Retain,
    Render,
}
#[derive(Default, Debug)]
pub struct CaptureRedrawPolicy {
    presented: Option<i64>,
}
impl CaptureRedrawPolicy {
    pub fn frame_action(&self, armed: bool, finished: bool, elapsed: i64) -> CaptureFrameAction {
        if !armed || finished {
            CaptureFrameAction::Hide
        } else if self.is_due(elapsed) {
            CaptureFrameAction::Render
        } else {
            CaptureFrameAction::Retain
        }
    }
    pub fn is_due(&self, elapsed: i64) -> bool {
        elapsed >= 0
            && self
                .presented
                .is_none_or(|p| p < 0 || (elapsed >= p && elapsed - p >= 16))
    }
    pub fn presented(&mut self, elapsed: i64) {
        self.presented = Some(elapsed);
    }
    pub fn wait_milliseconds(&self, armed: bool, finished: bool, elapsed: i64) -> u32 {
        if !armed || finished || elapsed < 0 {
            return 16;
        }
        match self.presented {
            // The paint itself already consumed part (or all) of this frame.
            // Never append another whole frame interval after rendering.
            Some(start) if start >= 0 && elapsed >= start => 16 - (elapsed - start).min(16) as u32,
            None => 0,
            Some(start) if start < 0 => 0,
            _ => 16,
        }
    }
}
#[derive(Default, Debug)]
pub struct CaptureInputHealthPolicy {
    mismatch: i32,
    since: Option<i64>,
}
impl CaptureInputHealthPolicy {
    pub fn observe(
        &mut self,
        armed: bool,
        finished: bool,
        dragging: bool,
        swallowed: bool,
        physical_left: bool,
        elapsed: i64,
    ) -> i32 {
        let observed = i32::from(armed && !finished && !dragging && !swallowed && physical_left);
        if elapsed < 0 || observed == 0 {
            self.mismatch = 0;
            self.since = None;
            return 0;
        }
        if observed != self.mismatch || self.since.is_none_or(|s| elapsed < s) {
            self.mismatch = observed;
            self.since = Some(elapsed);
            return 0;
        }
        if elapsed - self.since.unwrap() >= 750 {
            self.mismatch
        } else {
            0
        }
    }
}
#[derive(Clone, Default, Debug)]
pub struct CaptureHoverCandidate {
    pub frame: Rect,
    pub class_name: String,
    pub root_known: bool,
    pub visible: bool,
    pub minimized: bool,
    pub cloak_known: bool,
    pub own_window: bool,
    pub shell_window: bool,
    pub excluded_from_capture: bool,
    pub cloaked: u32,
}
#[derive(Default, Debug)]
pub struct CaptureHoverPolicy {
    queried_at: Option<i64>,
    frame: Rect,
}
impl CaptureHoverPolicy {
    pub const QUERY_MILLISECONDS: i64 = 80;
    pub fn bounds(left: i32, top: i32, right: i32, bottom: i32) -> Rect {
        Rect::from_ltrb(left, top, right, bottom)
    }
    pub fn shell_class(name: &str) -> bool {
        matches!(
            name,
            "Progman"
                | "WorkerW"
                | "Shell_TrayWnd"
                | "Shell_SecondaryTrayWnd"
                | "SHELLDLL_DefView"
                | "SysListView32"
        )
    }
    pub fn known_overlay(window: usize, hints: &[usize], planes: &[usize]) -> bool {
        window != 0 && (hints.contains(&window) || planes.contains(&window))
    }
    pub fn candidate_frame(c: &CaptureHoverCandidate, p: Point) -> Rect {
        if c.root_known
            && c.visible
            && !c.minimized
            && c.cloak_known
            && c.cloaked == 0
            && !c.own_window
            && !c.shell_window
            && !c.excluded_from_capture
            && !c.class_name.is_empty()
            && !Self::shell_class(&c.class_name)
            && c.frame.contains(p)
        {
            c.frame
        } else {
            Rect::default()
        }
    }
    pub fn clear(&mut self) {
        self.frame = Rect::default();
    }
    pub fn begin_query(&mut self, elapsed: i64) -> bool {
        if elapsed < 0 || self.queried_at.is_some_and(|t| elapsed < t) {
            self.clear();
            return false;
        }
        if self
            .queried_at
            .is_some_and(|t| elapsed - t < Self::QUERY_MILLISECONDS)
        {
            return false;
        }
        self.queried_at = Some(elapsed);
        self.clear();
        true
    }
    pub fn set_frame(&mut self, value: Rect) {
        self.frame = value;
    }
    pub fn current(&mut self, p: Point, elapsed: i64, idle: bool) -> Rect {
        if !idle
            || self
                .queried_at
                .is_none_or(|t| elapsed < t || elapsed - t >= Self::QUERY_MILLISECONDS)
        {
            self.clear();
            return Rect::default();
        }
        if self.frame.contains(p) {
            self.frame
        } else {
            Rect::default()
        }
    }
}
/// Re-query at release and around pixel copy. Never retarget a stale click.
pub fn capture_window_is_current(expected: CaptureWindowTarget, current: Option<CaptureWindowTarget>) -> bool {
    expected.window != 0 && expected.process != 0 && expected.thread != 0
        && expected.frame.valid() && current == Some(expected)
}

/// Keep every hint above every input plane after EACH native positioning call.
/// render_hints returns the FIRST raised visible hint (bottom of the hint set).
/// Callers must propagate render failure without repairing input above absent hints.
pub struct CaptureZOrderPolicy;
impl CaptureZOrderPolicy {
    pub fn first_raised(first: usize, next: usize) -> usize {
        if first == 0 {
            next
        } else {
            first
        }
    }
    pub fn present(
        raise: bool,
        ensure_input: impl FnOnce() -> bool,
        render_hints: impl FnOnce() -> Result<usize, String>,
        repair_input: impl FnOnce(usize) -> bool,
    ) -> Result<bool, String> {
        if !ensure_input() {
            return Ok(false);
        }
        let bottom = render_hints()?;
        if raise {
            if bottom == 0 {
                return Err("CAPTURE_OVERLAY: No visible selection border could anchor the capture input windows; selection was cancelled.".into());
            }
            return Ok(repair_input(bottom));
        }
        Ok(true)
    }
}

#[cfg(test)]
mod supplemental_tests {
    use super::*;
    #[test]
    fn topology_oracle_and_invalid_metadata() {
        let left = CaptureDisplaySnapshot {
            device: "left".into(),
            bounds: Rect::new(-1600, 0, 1600, 1000),
            dpi: 144,
        };
        let main = CaptureDisplaySnapshot {
            device: "main".into(),
            bounds: Rect::new(0, 0, 1920, 1080),
            dpi: 96,
        };
        let fresh = || CaptureTopologyPolicy::new(vec![left.clone(), main.clone()], 2).unwrap();
        let mut expected = fresh();
        assert!(expected
            .matches(&CaptureTopologyPolicy::new(vec![main.clone(), left.clone()], 2).unwrap()));
        assert!(!expected.matches(&CaptureTopologyPolicy::new(vec![main.clone()], 2).unwrap()));
        for changed in [
            CaptureDisplaySnapshot {
                dpi: 192,
                ..left.clone()
            },
            CaptureDisplaySnapshot {
                bounds: Rect::new(-1600, -200, 1600, 1000),
                ..left.clone()
            },
        ] {
            assert!(!expected
                .matches(&CaptureTopologyPolicy::new(vec![changed, main.clone()], 2).unwrap()));
        }
        assert!(!expected
            .matches(&CaptureTopologyPolicy::new(vec![left.clone(), main.clone()], 1).unwrap()));
        let mut selection =
            CaptureSelectionState::new(vec![main.bounds], Point::default()).unwrap();
        selection.begin(Point::new(10, 10));
        selection.end(Point::new(20, 20));
        expected.invalidate(1, 0, 0, 0);
        assert!(selection.finished && !expected.matches(&fresh()));
        assert!(expected.invalid && !expected.matches(&fresh()));
        assert!(!CaptureTopologyPolicy::dpi_message_changes(
            144,
            (144 << 16) | 144
        ));
        assert!(CaptureTopologyPolicy::dpi_message_changes(
            144,
            (192 << 16) | 192
        ));
        assert!(CaptureTopologyPolicy::dpi_message_changes(
            144,
            (192 << 16) | 144
        ));
        let mut t = fresh();
        t.invalidate(4, 144, 192, 3);
        t.invalidate(2, 96, 96, 1);
        assert_eq!(
            (t.reason, t.before_dpi, t.after_dpi, t.invalidation_phase),
            (4, 144, 192, 3)
        );
        assert!(fresh().matches(&fresh()));
        assert!(CaptureTopologyPolicy::new(vec![], 2).is_err());
        assert!(CaptureTopologyPolicy::new(vec![left.clone(), left.clone()], 2).is_err());
        for bad in [
            CaptureDisplaySnapshot {
                dpi: 0,
                ..left.clone()
            },
            CaptureDisplaySnapshot {
                device: String::new(),
                ..left.clone()
            },
            CaptureDisplaySnapshot {
                bounds: Rect::default(),
                ..left
            },
        ] {
            assert!(CaptureTopologyPolicy::new(vec![bad], 2).is_err());
        }
    }
    #[test]
    fn redraw_and_one_way_input_health_oracle() {
        let mut r = CaptureRedrawPolicy::default();
        assert!(r.is_due(0));
        r.presented(0);
        assert!(!r.is_due(15) && r.is_due(16));
        r.presented(16);
        assert!(!r.is_due(20) && r.is_due(32));
        assert!(!r.is_due(-1) && !r.is_due(15));
        assert!(r.is_due(5000));
        let mut h = CaptureInputHealthPolicy::default();
        for t in [0, 2000] {
            assert_eq!(h.observe(false, false, false, false, true, t), 0);
        }
        for t in [2100, 2849] {
            assert_eq!(h.observe(true, false, false, false, true, t), 0);
        }
        assert_eq!(h.observe(true, false, false, false, true, 2850), 1);
        assert_eq!(h.observe(true, false, true, true, true, 2860), 0);
        for t in [3000, 3749, 3750] {
            assert_eq!(h.observe(true, false, true, true, false, t), 0);
        }
        assert_eq!(h.observe(true, true, false, false, false, 3760), 0);
        for t in [4000, 3900] {
            assert_eq!(h.observe(true, false, true, true, false, t), 0);
        }
        assert_eq!(h.observe(true, false, true, true, true, 5000), 0);
        for t in [6000, 120000] {
            assert_eq!(h.observe(true, false, true, true, false, t), 0);
        }
    }
    #[test]
    fn frame_wait_consumes_only_the_budget_remaining_after_rendering() {
        let mut redraw = CaptureRedrawPolicy::default();
        assert_eq!(redraw.wait_milliseconds(true, false, 0), 0);
        redraw.presented(100);
        for render_cost in [0_i64, 1, 8, 15, 16, 25, 46] {
            let wait = redraw.wait_milliseconds(true, false, 100 + render_cost);
            assert_eq!(i64::from(wait), (16 - render_cost).max(0));
            assert_eq!(render_cost + i64::from(wait), render_cost.max(16));
        }
        // Inactive/closing loops still yield for their existing bounded input
        // handshake, and malformed/regressing clocks cannot produce a spin.
        for elapsed in [-1, 99, 100, 116, 146] {
            assert_eq!(redraw.wait_milliseconds(false, false, elapsed), 16);
            assert_eq!(redraw.wait_milliseconds(true, true, elapsed), 16);
        }
        assert_eq!(redraw.wait_milliseconds(true, false, -1), 16);
        assert_eq!(redraw.wait_milliseconds(true, false, 99), 16);
        // Sustained expensive rendering must not be capped at cost + 16 ms.
        let mut redraw = CaptureRedrawPolicy::default();
        let mut elapsed = 0;
        for _ in 0..24 {
            assert_eq!(
                redraw.frame_action(true, false, elapsed),
                CaptureFrameAction::Render
            );
            redraw.presented(elapsed);
            elapsed += 25;
            elapsed += i64::from(redraw.wait_milliseconds(true, false, elapsed));
        }
        assert_eq!(elapsed, 600);
    }
    #[test]
    fn magnifier_retains_every_throttled_frame_until_disarmed_or_finished() {
        let mut redraw = CaptureRedrawPolicy::default();
        let mut visible = false;
        let mut renders = 0;
        let mut retained = 0;
        assert_eq!(
            redraw.frame_action(false, false, 0),
            CaptureFrameAction::Hide
        );
        // Frequent pointer/mailbox events wake the loop between its 16 ms
        // paints. Every one of those ticks must retain the last visible frame.
        for elapsed in 0..=1000 {
            match redraw.frame_action(true, false, elapsed) {
                CaptureFrameAction::Render => {
                    redraw.presented(elapsed);
                    visible = true;
                    renders += 1;
                }
                CaptureFrameAction::Retain => retained += 1,
                CaptureFrameAction::Hide => visible = false,
            }
            assert!(visible, "armed frame disappeared at {elapsed} ms");
        }
        assert_eq!(renders, 63);
        assert_eq!(retained, 938);
        // Same-time/reordered notifications cannot erase a complete frame.
        for elapsed in [1000, 999, -1] {
            assert_eq!(
                redraw.frame_action(true, false, elapsed),
                CaptureFrameAction::Retain
            );
        }
        for elapsed in [1000, 1008, 2000] {
            assert_eq!(
                redraw.frame_action(false, false, elapsed),
                CaptureFrameAction::Hide
            );
            assert_eq!(
                redraw.frame_action(true, true, elapsed),
                CaptureFrameAction::Hide
            );
            assert_eq!(
                redraw.frame_action(false, true, elapsed),
                CaptureFrameAction::Hide
            );
        }
        // Re-arming after suspension renders afresh when due, then retains.
        assert_eq!(
            redraw.frame_action(true, false, 2000),
            CaptureFrameAction::Render
        );
        redraw.presented(2000);
        assert_eq!(
            redraw.frame_action(true, false, 2001),
            CaptureFrameAction::Retain
        );
    }
    #[test]
    fn hover_oracle_exact_metadata_throttle_and_no_stale_frame() {
        let bounds = CaptureHoverPolicy::bounds(-1400, -200, 200, 700);
        assert_eq!(bounds, Rect::new(-1400, -200, 1600, 900));
        assert!(CaptureHoverPolicy::bounds(4, 0, 4, 100).is_empty());
        assert!(CaptureHoverPolicy::bounds(i32::MIN, 0, i32::MAX, 100).is_empty());
        let p = Point::new(-300, 100);
        let valid = CaptureHoverCandidate {
            frame: bounds,
            class_name: "GeneratedWindow".into(),
            root_known: true,
            visible: true,
            cloak_known: true,
            ..Default::default()
        };
        assert_eq!(CaptureHoverPolicy::candidate_frame(&valid, p), bounds);
        let mut bads = vec![];
        macro_rules! bad {
            ($f:ident,$v:expr) => {{
                let mut c = valid.clone();
                c.$f = $v;
                bads.push(c);
            }};
        }
        bad!(visible, false);
        bad!(minimized, true);
        bad!(cloak_known, false);
        bad!(cloaked, 1);
        bad!(own_window, true);
        bad!(shell_window, true);
        bad!(excluded_from_capture, true);
        bad!(root_known, false);
        bad!(class_name, String::new());
        for name in [
            "Progman",
            "WorkerW",
            "Shell_TrayWnd",
            "Shell_SecondaryTrayWnd",
            "SHELLDLL_DefView",
            "SysListView32",
        ] {
            bad!(class_name, name.into());
        }
        for bad in bads {
            assert!(CaptureHoverPolicy::candidate_frame(&bad, p).is_empty());
        }
        assert!(CaptureHoverPolicy::candidate_frame(&valid, Point::new(200, 100)).is_empty());
        for handle in [0, 20, 30] {
            assert!(!CaptureHoverPolicy::known_overlay(handle, &[40], &[50]));
        }
        for handle in [40, 50] {
            assert!(CaptureHoverPolicy::known_overlay(handle, &[40], &[50]));
        }
        let mut h = CaptureHoverPolicy::default();
        assert!(h.begin_query(0));
        h.set_frame(bounds);
        assert_eq!(h.current(p, 0, true), bounds);
        assert!(!h.begin_query(79));
        assert!(h.current(p, 80, true).is_empty());
        assert!(h.begin_query(80));
        assert!(h.current(p, 80, true).is_empty());
        h.set_frame(bounds);
        assert!(h.current(p, 81, false).is_empty());
        assert!(h.current(p, 82, true).is_empty());
        assert!(!h.begin_query(20));
        assert!(h.current(p, 20, true).is_empty());
    }
    #[test]
    fn zorder_oracle_checks_every_native_step_not_only_final_order() {
        use std::cell::{Cell, RefCell};
        let order = RefCell::new(vec![90usize]);
        let visible = RefCell::new(vec![1usize, 2, 3, 4]);
        let shown = Cell::new(false);
        let repairs = Cell::new(0);
        let renders = Cell::new(0);
        let invariant = |o: &[usize]| {
            for edge in [1, 2, 3, 4] {
                for plane in [11, 12] {
                    if let (Some(e), Some(p)) = (
                        o.iter().position(|x| *x == edge),
                        o.iter().position(|x| *x == plane),
                    ) {
                        assert!(
                            e < p,
                            "edge must remain above plane after every positioning call"
                        );
                    }
                }
            }
        };
        let position = |window: usize, after: usize| {
            let mut o = order.borrow_mut();
            o.retain(|w| *w != window);
            let i = if after == 0 {
                0
            } else {
                o.iter().position(|w| *w == after).unwrap() + 1
            };
            o.insert(i, window);
            invariant(&o);
        };
        let ensure = || {
            if !shown.replace(true) {
                for p in [11, 12] {
                    position(p, 0);
                }
            }
            true
        };
        let render = || {
            renders.set(renders.get() + 1);
            let mut first = 0;
            order
                .borrow_mut()
                .retain(|w| ![1, 2, 3, 4].contains(w) || visible.borrow().contains(w));
            for e in visible.borrow().iter() {
                position(*e, 0);
                first = CaptureZOrderPolicy::first_raised(first, *e);
            }
            Ok(first)
        };
        let repair = |bottom| {
            repairs.set(repairs.get() + 1);
            for p in [11, 12] {
                position(p, bottom);
            }
            true
        };
        assert_eq!(
            CaptureZOrderPolicy::present(true, ensure, render, repair),
            Ok(true)
        );
        let above_foreign = || {
            let o = order.borrow();
            for p in [11, 12] {
                assert!(o.iter().position(|w| *w == p) < o.iter().position(|w| *w == 90));
            }
        };
        above_foreign();
        position(90, 0);
        assert_eq!(
            CaptureZOrderPolicy::present(true, ensure, render, repair),
            Ok(true)
        );
        above_foreign();
        *visible.borrow_mut() = vec![3, 4];
        assert_eq!(
            CaptureZOrderPolicy::present(true, ensure, render, repair),
            Ok(true)
        );
        assert!(!order.borrow().contains(&1) && !order.borrow().contains(&2));
        let before = repairs.get();
        assert_eq!(
            CaptureZOrderPolicy::present(false, ensure, render, repair),
            Ok(true)
        );
        assert_eq!(repairs.get(), before);
        let before_render = renders.get();
        assert_eq!(
            CaptureZOrderPolicy::present(true, || false, render, repair),
            Ok(false)
        );
        assert_eq!(renders.get(), before_render);
        assert_eq!(repairs.get(), before);
        assert_eq!(
            CaptureZOrderPolicy::present(true, ensure, render, |_| false),
            Ok(false)
        );
        assert!(CaptureZOrderPolicy::present(true, ensure, || Ok(0), repair)
            .unwrap_err()
            .starts_with("CAPTURE_OVERLAY:"));
        assert_eq!(repairs.get(), before);
        assert_eq!(
            CaptureZOrderPolicy::present(
                true,
                ensure,
                || Err("synthetic edge failure".into()),
                repair
            ),
            Err("synthetic edge failure".into())
        );
        assert_eq!(repairs.get(), before);
        assert!(
            std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| position(11, 0))).is_err(),
            "oracle must reject the old plane-first repair"
        );
    }
}

/// Physical 3× loupe placement. `area` is the pointer's monitor, NOT the
/// virtual-desktop union: the loupe must not jump into a monitor gap.
pub fn magnifier_place(pointer: Point, sample: Rect, area: Rect) -> Rect {
    const VIEW: i64 = 156;
    const HEIGHT: i64 = 174;
    const GAP: i64 = 16;
    if !area.valid() || !sample.valid() {
        return Rect::default();
    }
    let mut x = i64::from(sample.right()) + GAP;
    let mut y = i64::from(sample.y);
    if x + VIEW > i64::from(area.right()) {
        x = i64::from(sample.x) - GAP - VIEW;
    }
    if y + HEIGHT > i64::from(area.bottom()) {
        y = i64::from(area.bottom()) - HEIGHT;
    }
    x = x.max(i64::from(area.x));
    y = y.max(i64::from(area.y));
    let rect = |x: i64, y: i64| {
        Rect::new(
            x.clamp(i64::from(i32::MIN), i64::from(i32::MAX)) as i32,
            y.clamp(i64::from(i32::MIN), i64::from(i32::MAX)) as i32,
            VIEW as i32,
            HEIGHT as i32,
        )
    };
    let placed = rect(x, y);
    if !placed.intersect(sample).is_empty() || placed.contains(pointer) {
        let left = i64::from(pointer.x) < i64::from(area.x) + i64::from(area.width) / 2;
        let above = i64::from(pointer.y) < i64::from(area.y) + i64::from(area.height) / 2;
        x = if left {
            i64::from(area.right()) - VIEW
        } else {
            i64::from(area.x)
        };
        y = if above {
            i64::from(area.bottom()) - HEIGHT
        } else {
            i64::from(area.y)
        };
        return rect(x, y);
    }
    placed
}
#[cfg(test)]
mod magnifier_placement_tests {
    use super::*;
    #[test]
    fn loupe_retains_physical_size_and_avoids_sample_across_monitor_edges() {
        for area in [
            Rect::new(0, 0, 1920, 1080),
            Rect::new(-2560, -300, 2560, 1440),
            Rect::new(100, -1200, 1600, 900),
        ] {
            for x in [
                area.x,
                area.x + 1,
                area.x + area.width / 2,
                area.right() - 2,
                area.right() - 1,
            ] {
                for y in [
                    area.y,
                    area.y + 1,
                    area.y + area.height / 2,
                    area.bottom() - 2,
                    area.bottom() - 1,
                ] {
                    let p = Point::new(x, y);
                    let sample = CaptureMagnifierSample::new(p, area).bounds;
                    let placed = magnifier_place(p, sample, area);
                    assert_eq!((placed.width, placed.height), (156, 174));
                    assert!(area.contains_rect(placed));
                    assert!(!placed.contains(p));
                    assert!(placed.intersect(sample).is_empty());
                }
            }
        }
    }
    #[test]
    fn loupe_oracle_right_first_then_left_and_opposite_corner_fallback() {
        let area = Rect::new(-1000, -500, 1000, 800);
        assert_eq!(
            magnifier_place(Point::new(-500, -100), Rect::new(-526, -126, 52, 52), area),
            Rect::new(-458, -126, 156, 174)
        );
        assert_eq!(
            magnifier_place(Point::new(-1, 299), Rect::new(-27, 273, 52, 52), area),
            Rect::new(-199, 126, 156, 174)
        );
        // Narrow screen forces overlap after ordinary horizontal placement: choose
        // the diagonally opposite corner, rather than covering pointer/sample.
        let narrow = Rect::new(-300, -600, 200, 600);
        assert_eq!(
            magnifier_place(
                Point::new(-280, -500),
                Rect::new(-306, -526, 52, 52),
                narrow
            ),
            Rect::new(-256, -174, 156, 174)
        );
        assert_eq!(
            magnifier_place(
                Point::new(-120, -100),
                Rect::new(-146, -126, 52, 52),
                narrow
            ),
            Rect::new(-300, -600, 156, 174)
        );
    }
}

/// Linearizable Escape ownership shared by the hook and UI shutdown path.
/// Closing blocks NEW pairs; an already owned pair must still drain its real up.
#[derive(Default, Debug)]
pub struct EscOwnership(std::sync::atomic::AtomicU32);
impl EscOwnership {
    const CLOSING: u32 = 1;
    const OWNED: u32 = 2;
    pub fn request_close(&self) {
        self.0
            .fetch_or(Self::CLOSING, std::sync::atomic::Ordering::SeqCst);
    }
    pub fn down(&self) -> bool {
        use std::sync::atomic::Ordering::SeqCst;
        let mut state = self.0.load(SeqCst);
        loop {
            if state & Self::OWNED != 0 {
                return true;
            }
            if state & Self::CLOSING != 0 {
                return false;
            }
            match self
                .0
                .compare_exchange(state, state | Self::OWNED, SeqCst, SeqCst)
            {
                Ok(_) => return true,
                Err(current) => state = current,
            }
        }
    }
    pub fn up(&self) -> bool {
        use std::sync::atomic::Ordering::SeqCst;
        let mut state = self.0.load(SeqCst);
        loop {
            if state & Self::OWNED == 0 {
                return false;
            }
            match self
                .0
                .compare_exchange(state, state & !Self::OWNED, SeqCst, SeqCst)
            {
                Ok(_) => return true,
                Err(current) => state = current,
            }
        }
    }
    pub fn owned(&self) -> bool {
        self.0.load(std::sync::atomic::Ordering::SeqCst) & Self::OWNED != 0
    }
    pub fn may_exit(&self) -> bool {
        self.0.load(std::sync::atomic::Ordering::SeqCst) == Self::CLOSING
    }
}
#[cfg(test)]
mod escape_ownership_tests {
    use super::EscOwnership;
    #[test]
    fn close_before_new_down_preserves_foreign_pair() {
        let gate = EscOwnership::default();
        assert!(!gate.may_exit());
        gate.request_close();
        assert!(gate.may_exit());
        assert!(!gate.down());
        assert!(!gate.up());
        assert!(!gate.owned());
        assert!(gate.may_exit());
    }
    #[test]
    fn down_before_close_drains_owned_repeat_and_actual_up() {
        let gate = EscOwnership::default();
        assert!(!gate.up());
        assert!(gate.down());
        gate.request_close();
        assert!(gate.owned());
        assert!(!gate.may_exit());
        assert!(gate.down());
        assert!(gate.down());
        assert!(gate.up());
        assert!(!gate.up());
        assert!(gate.may_exit());
        assert!(!gate.down());
    }
    #[test]
    fn lost_inbox_and_repeated_shutdown_never_fabricate_release() {
        let gate = EscOwnership::default();
        assert!(gate.down());
        // Failed posting, UI timeout, and repeated shutdown cannot clear ownership.
        // There deliberately is no force-clear API; only a physical matching up can.
        for _ in 0..100 {
            gate.request_close();
            assert!(gate.owned());
            assert!(!gate.may_exit());
        }
        assert!(gate.up());
        assert!(gate.may_exit());
    }
    #[test]
    fn open_gate_can_accept_next_pair_without_closing() {
        let gate = EscOwnership::default();
        for _ in 0..100 {
            assert!(gate.down());
            assert!(gate.owned());
            assert!(gate.up());
            assert!(!gate.owned());
            assert!(!gate.may_exit());
        }
    }
}

/// WM_CANCELMODE/WM_CAPTURECHANGED belong to the input surface, not decorative
/// windows: disabling the noninteractive magnifier itself sends WM_CANCELMODE.
pub fn capture_window_cancels(input_plane: bool, message: u32) -> bool {
    input_plane && matches!(message, 0x001f | 0x0215)
}
#[cfg(test)]
mod window_cancellation_tests {
    use super::*;
    #[test]
    fn disabled_decoration_is_not_input_cancellation() {
        for input_plane in [false, true] {
            for message in [0x001f, 0x0215, 0x000a, 0x000f, 0x0200] {
                assert_eq!(
                    capture_window_cancels(input_plane, message),
                    input_plane && (message == 0x001f || message == 0x0215)
                );
            }
        }
        assert!(!capture_window_cancels(false, 0x001f)); // EnableWindow(loupe,false)
        assert!(capture_window_cancels(true, 0x001f)); // genuine input cancellation
        assert!(capture_window_cancels(true, 0x0215)); // never activate to recapture
    }
}

#[cfg(test)]
mod screenshot_window_tests {
    use super::*;
    fn target() -> CaptureWindowTarget {
        CaptureWindowTarget { window: 41, process: 42, thread: 43, frame: Rect::new(-200, -100, 500, 300) }
    }
    fn screenshot() -> CaptureSelectionState {
        let mut state = CaptureSelectionState::with_purpose(vec![Rect::new(-300, -200, 1000, 800)], Point::new(0, 0), CapturePurpose::Screenshot).unwrap();
        state.set_window_candidate(Some(target()), 96);
        state
    }
    #[test]
    fn screenshot_click_keeps_button_down_candidate_with_jitter() {
        let mut state = screenshot();
        state.begin(Point::new(0, 0));
        state.set_window_candidate(None, 96); // cannot replace a pressed ticket
        state.end(Point::new(4, -3));
        assert!(!state.cancelled);
        assert_eq!(state.selected, target().frame);
        assert_eq!(state.selected_window, Some(target()));
    }
    #[test]
    fn screenshot_drag_takes_precedence_even_after_returning_to_anchor() {
        let mut state = screenshot();
        state.begin(Point::new(0, 0));
        state.move_to(Point::new(40, 10));
        state.end(Point::new(2, 2));
        assert!(state.cancelled);
        assert_eq!(state.selected_window, None);
        let mut state = screenshot();
        state.begin(Point::new(0, 0));
        state.end(Point::new(-150, 120));
        assert_eq!(state.selected, Rect::new(-150, 0, 150, 120));
        assert_eq!(state.selected_window, None);
    }
    #[test]
    fn screenshot_click_without_candidate_never_captures_a_small_jitter_rect() {
        let mut state = screenshot();
        state.set_window_candidate(None, 96);
        state.begin(Point::new(0, 0)); state.end(Point::new(4, 4));
        assert!(state.cancelled);
    }
    #[test]
    fn region_click_semantics_are_unchanged() {
        let mut state = CaptureSelectionState::new(vec![Rect::new(-300, -200, 1000, 800)], Point::new(0, 0)).unwrap();
        state.set_window_candidate(Some(target()), 96);
        state.begin(Point::new(0, 0)); state.end(Point::new(0, 0));
        assert!(state.cancelled); assert_eq!(state.selected_window, None);
    }
    #[test]
    fn screenshot_threshold_scales_and_window_is_clipped_to_visible_desktop() {
        let mut state = screenshot();
        let partly_offscreen = CaptureWindowTarget { frame: Rect::new(-400, -300, 500, 500), ..target() };
        state.set_window_candidate(Some(partly_offscreen), 192);
        state.begin(Point::new(0, 0)); state.end(Point::new(8, 8));
        assert_eq!(state.selected, Rect::new(-300, -200, 400, 400));
        assert_eq!(state.selected_window, Some(partly_offscreen));
    }
    #[test]
    fn window_identity_geometry_and_permission_loss_fail_closed() {
        let expected = target();
        assert!(capture_window_is_current(expected, Some(expected)));
        for current in [None, Some(CaptureWindowTarget { window: 9, ..expected }),
            Some(CaptureWindowTarget { process: 9, ..expected }), Some(CaptureWindowTarget { thread: 9, ..expected }),
            Some(CaptureWindowTarget { frame: Rect::new(-199, -100, 500, 300), ..expected })] {
            assert!(!capture_window_is_current(expected, current));
        }
    }
    #[test]
    fn coalesced_drag_excursion_cannot_turn_into_window_click() {
        let mut state = screenshot(); state.begin(Point::new(0, 0));
        state.note_drag_excursion(50, 10); state.end(Point::new(3, 3));
        assert_eq!(state.selected, Rect::new(0, 0, 3, 3));
        assert_eq!(state.selected_window, None);
    }
    #[test]
    fn screenshot_cancel_cannot_be_reactivated_by_late_release() {
        let mut state = screenshot(); state.begin(Point::new(0, 0)); state.cancel(); state.end(Point::new(1, 1));
        assert!(state.finished && state.cancelled); assert_eq!(state.selected_window, None);
    }
}
