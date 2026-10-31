//! Scalar protocol shared by the owned input host and native capture child.
pub const REFRESH: u32 = 0x8380;
pub const READY: u32 = 0x8381;
pub const ARM: u32 = 0x8382;
pub const MOVE_ACK: u32 = 0x8383;
pub const STOP: u32 = 0x8384;
pub const PING: u32 = 0x8385;
pub const END: u32 = 0x8386;
pub const READY_ACK: u32 = 0x8390;
pub const ARM_ACK: u32 = 0x8391;
pub const MOVE: u32 = 0x8392;
pub const LEFT_DOWN: u32 = 0x8393;
pub const LEFT_UP: u32 = 0x8394;
pub const RIGHT_DOWN: u32 = 0x8395;
pub const RIGHT_UP: u32 = 0x8396;
pub const STOP_ACK: u32 = 0x8397;
pub const FAILURE: u32 = 0x8398;
pub const PING_ACK: u32 = 0x8399;
// Max absolute movement since left down, sent before left up; survives coalesced MOVE.
pub const DRAG_EXCURSION: u32 = 0x839a;
