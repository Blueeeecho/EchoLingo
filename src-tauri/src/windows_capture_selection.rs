//! Bounded, scalar deferred screenshot protocol. No handles are dereferenced here.
use crate::policy::{CaptureWindowTarget, Rect};
use serde_json::Value;

pub const MAX_REQUEST_BYTES: usize = 65_536;
fn invalid() -> String {
    "CAPTURE_ARGUMENT: Invalid deferred screenshot request.".into()
}
pub fn rect(value: &Value) -> Result<Rect, String> {
    let number = |key: &str| -> Result<i32, String> {
        i32::try_from(value[key].as_i64().ok_or_else(invalid)?).map_err(|_| invalid())
    };
    let r = Rect::new(
        number("x")?,
        number("y")?,
        number("width")?,
        number("height")?,
    );
    if value.as_object().is_none_or(|o| o.len() != 4) || !r.valid() {
        return Err(invalid());
    }
    Ok(r)
}
pub fn rect_json(r: Rect) -> Value {
    serde_json::json!({"x":r.x,"y":r.y,"width":r.width,"height":r.height})
}
pub fn source(value: &Value) -> Result<Option<CaptureWindowTarget>, String> {
    if value.is_null() {
        return Ok(None);
    }
    let window =
        usize::try_from(value["window"].as_u64().ok_or_else(invalid)?).map_err(|_| invalid())?;
    let process =
        u32::try_from(value["process"].as_u64().ok_or_else(invalid)?).map_err(|_| invalid())?;
    let thread =
        u32::try_from(value["thread"].as_u64().ok_or_else(invalid)?).map_err(|_| invalid())?;
    if window == 0 || process == 0 || thread == 0 || value.as_object().is_none_or(|o| o.len() != 4)
    {
        return Err(invalid());
    }
    Ok(Some(CaptureWindowTarget {
        window,
        process,
        thread,
        frame: rect(&value["frame"])?,
    }))
}
pub fn request(bytes: &[u8], owner: u32) -> Result<(Value, Rect), String> {
    if bytes.len() > MAX_REQUEST_BYTES || owner == 0 {
        return Err(invalid());
    }
    let value: Value = serde_json::from_slice(bytes).map_err(|_| invalid())?;
    let plan = &value["plan"];
    if value.as_object().is_none_or(|o| o.len() != 2)
        || plan["version"] != 1
        || plan["owner"] != owner
        || plan["displays"]
            .as_array()
            .is_none_or(|v| v.is_empty() || v.len() > 32)
    {
        return Err(invalid());
    }
    let selected = rect(&value["rect"])?;
    let viewport = rect(&plan["viewport"])?;
    source(&plan["source"])?;
    if selected.width < 3
        || selected.height < 3
        || i64::from(selected.width) * i64::from(selected.height) > 32_000_000
        || !viewport.contains_rect(selected)
    {
        return Err(invalid());
    }
    Ok((plan.clone(), selected))
}
#[cfg(test)]
mod tests {
    use super::*;
    fn input() -> Value {
        serde_json::json!({"plan":{"version":1,"owner":7,"displays":[{}],"source":null,
            "viewport":{"x":-1920,"y":-100,"width":3840,"height":1180}},
            "rect":{"x":-1800,"y":-50,"width":800,"height":600}})
    }
    #[test]
    fn negative_physical_coordinates_survive_without_scale_conversion() {
        let (_, r) = request(input().to_string().as_bytes(), 7).unwrap();
        assert_eq!(r, Rect::new(-1800, -50, 800, 600));
    }
    #[test]
    fn rejects_wrong_owner_overflow_outside_and_small_regions() {
        assert!(request(input().to_string().as_bytes(), 8).is_err());
        for (key, number) in [("x", i64::MAX), ("width", 2), ("height", 999999)] {
            let mut v = input();
            v["rect"][key] = number.into();
            assert!(request(v.to_string().as_bytes(), 7).is_err());
        }
        assert!(request(&vec![b' '; MAX_REQUEST_BYTES + 1], 7).is_err());
    }
    #[test]
    fn rejects_non_integer_and_unknown_rect_fields() {
        let mut v = input();
        v["rect"]["x"] = (-1.5).into();
        assert!(request(v.to_string().as_bytes(), 7).is_err());
        let mut v = input();
        v["rect"]["extra"] = true.into();
        assert!(request(v.to_string().as_bytes(), 7).is_err());
    }
}
