//! Canonical shortcut input shared by settings validation and registration.
//! Parsing constructs bindings only; it never registers OS shortcuts.
use crate::model::Shortcuts;
use std::collections::HashSet;
use tauri_plugin_global_shortcut::Shortcut;

const NAMED_KEYS: &[&str] = &[
    "Escape",
    "Enter",
    "Space",
    "Tab",
    "Backspace",
    "Delete",
    "Insert",
    "Home",
    "End",
    "PageUp",
    "PageDown",
    "ArrowUp",
    "ArrowDown",
    "ArrowLeft",
    "ArrowRight",
    "Equal",
    "Minus",
    "Comma",
    "Period",
    "Slash",
    "Semicolon",
    "Quote",
    "BracketLeft",
    "BracketRight",
    "Backslash",
    "Backquote",
    "Pause",
    "CapsLock",
    "PrintScreen",
    "ScrollLock",
    "NumLock",
    "NumpadAdd",
    "NumpadSubtract",
    "NumpadMultiply",
    "NumpadDivide",
    "NumpadDecimal",
    "NumpadEnter",
    "NumpadEqual",
    "AudioVolumeUp",
    "AudioVolumeDown",
    "AudioVolumeMute",
    "MediaPlay",
    "MediaPause",
    "MediaPlayPause",
    "MediaStop",
    "MediaTrackNext",
    "MediaTrackPrevious",
];

fn modifier(token: &str, mac: bool) -> Option<usize> {
    match token {
        "CTRL" | "CONTROL" => Some(0),
        "ALT" | "OPTION" => Some(1),
        "SHIFT" => Some(2),
        "SUPER" | "META" | "WIN" | "WINDOWS" | "COMMAND" | "CMD" => Some(3),
        "CMDORCTRL" | "COMMANDORCONTROL" | "COMMANDORCTRL" | "CMDORCONTROL" => {
            Some(if mac { 3 } else { 0 })
        }
        _ => None,
    }
}

fn function_key(token: &str) -> bool {
    token.strip_prefix('F').is_some_and(|number| {
        number
            .parse::<u8>()
            .is_ok_and(|value| (1..=24).contains(&value) && number == value.to_string())
    })
}

fn key(token: &str) -> Option<String> {
    let letter = token.strip_prefix("KEY").unwrap_or(token).as_bytes();
    if letter.len() == 1 && letter[0].is_ascii_uppercase() {
        return Some(String::from_utf8(letter.to_vec()).unwrap());
    }
    let digit = token.strip_prefix("DIGIT").unwrap_or(token).as_bytes();
    if digit.len() == 1 && digit[0].is_ascii_digit() {
        return Some(String::from_utf8(digit.to_vec()).unwrap());
    }
    if function_key(token) {
        return Some(token.into());
    }
    if token
        .strip_prefix("NUMPAD")
        .is_some_and(|number| number.len() == 1 && number.as_bytes()[0].is_ascii_digit())
    {
        return Some(format!("Numpad{}", &token[6..]));
    }
    let alias = match token {
        "ESC" => Some("Escape"),
        "RETURN" => Some("Enter"),
        "SPACEBAR" => Some("Space"),
        "UP" => Some("ArrowUp"),
        "DOWN" => Some("ArrowDown"),
        "LEFT" => Some("ArrowLeft"),
        "RIGHT" => Some("ArrowRight"),
        "=" => Some("Equal"),
        "-" => Some("Minus"),
        "," => Some("Comma"),
        "." => Some("Period"),
        "/" => Some("Slash"),
        ";" => Some("Semicolon"),
        "'" => Some("Quote"),
        "[" => Some("BracketLeft"),
        "]" => Some("BracketRight"),
        "\\" => Some("Backslash"),
        "`" => Some("Backquote"),
        _ => None,
    };
    alias
        .or_else(|| {
            NAMED_KEYS
                .iter()
                .copied()
                .find(|name| name.eq_ignore_ascii_case(token))
        })
        .map(str::to_owned)
}

fn normalize_one(value: &str, mac: bool) -> Result<String, String> {
    // Count as UTF-16 to agree with the frontend's80-code-unit input limit.
    // Check before trim so surrounding newlines cannot hide invalid input.
    if value.encode_utf16().count() > 80 || value.contains(['\r', '\n', '\0']) {
        return Err("快捷键过长或包含无效字符".into());
    }
    let value = value.trim();
    if value.is_empty() {
        return Ok(String::new());
    }
    let mut modifiers = [false; 4];
    let mut main_key = None;
    for part in value.split('+') {
        let token = part.trim().to_ascii_uppercase();
        if token.is_empty() {
            return Err("请用 + 分隔修饰键与一个按键；加号键可写 Shift+Equal".into());
        }
        if let Some(index) = modifier(&token, mac) {
            if modifiers[index] {
                return Err("同一修饰键不能重复填写".into());
            }
            modifiers[index] = true;
        } else {
            if main_key.is_some() {
                return Err("一个快捷键只能包含一个普通按键".into());
            }
            main_key = Some(key(&token).ok_or_else(|| {
                "不支持该按键；请使用字母、数字、F1–F24 或 Enter、Space 等键名".to_string()
            })?);
        }
    }
    let main_key = main_key.ok_or("请再按一个普通按键，不能只设置修饰键")?;
    if !modifiers[0] && !modifiers[1] && !modifiers[3] && !function_key(&main_key) {
        return Err("请搭配 Ctrl、Alt 或 Win/Command；F1–F24 可以单独使用".into());
    }
    let mut parts = Vec::new();
    for (index, name) in ["Ctrl", "Alt", "Shift", "Super"].into_iter().enumerate() {
        if modifiers[index] {
            parts.push(name.to_owned());
        }
    }
    parts.push(main_key);
    Ok(parts.join("+"))
}

fn prepare(shortcuts: &Shortcuts) -> Result<(Shortcuts, Vec<(String, Shortcut)>), String> {
    let mac = cfg!(target_os = "macos");
    let canonical = Shortcuts {
        selection: normalize_one(&shortcuts.selection, mac)?,
        capture: normalize_one(&shortcuts.capture, mac)?,
        ocr: normalize_one(&shortcuts.ocr, mac)?,
        silent_ocr: normalize_one(&shortcuts.silent_ocr, mac)?,
        input: normalize_one(&shortcuts.input, mac)?,
    };
    let mut parsed = Vec::new();
    let mut ids = HashSet::new();
    for (action, value) in canonical.pairs() {
        if value.is_empty() {
            continue;
        }
        // A frontend key-name whitelist cannot guarantee support in the real
        // pinned native parser. Its accepted ID also owns conflict detection.
        let binding: Shortcut = value.parse().map_err(|_| format!("快捷键无效：{value}"))?;
        if !ids.insert(binding.id()) {
            return Err("不同操作不能使用相同的快捷键".into());
        }
        parsed.push((action.to_owned(), binding));
    }
    Ok((canonical, parsed))
}

pub fn normalized(shortcuts: &Shortcuts) -> Result<Shortcuts, String> {
    prepare(shortcuts).map(|(canonical, _)| canonical)
}

pub fn parsed(shortcuts: &Shortcuts) -> Result<Vec<(String, Shortcut)>, String> {
    let (_, parsed) = prepare(shortcuts)?;
    // Windows reserves F12 for the debugger at all times. Keep canonical
    // parsing available to the installer's read-only reserved-key report, but
    // never let any runtime registration path acquire that key.
    #[cfg(target_os = "windows")]
    if parsed
        .iter()
        .any(|(_, binding)| binding.key == tauri_plugin_global_shortcut::Code::F12)
    {
        return Err("Windows 为调试器保留 F12，请选择其他按键".into());
    }
    Ok(parsed)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn only(value: &str) -> Shortcuts {
        Shortcuts {
            selection: value.into(),
            capture: String::new(),
            ocr: String::new(),
            silent_ocr: String::new(),
            input: String::new(),
        }
    }

    #[test]
    fn f12_is_canonical_for_reserved_key_reporting_but_not_windows_registration() {
        for value in ["F12", "Ctrl+Alt+F12"] {
            assert_eq!(normalized(&only(value)).unwrap().selection, value);
            if cfg!(target_os = "windows") {
                assert!(parsed(&only(value)).unwrap_err().contains("F12"));
            } else {
                assert!(parsed(&only(value)).is_ok());
            }
        }
        assert!(parsed(&only("Ctrl+Alt+F11")).is_ok());
    }

    #[test]
    fn normalizes_modifier_order_case_and_aliases_before_real_parsing() {
        let value = normalized(&only("  cmd + shift + option + control + keya  ")).unwrap();
        assert_eq!(value.selection, "Ctrl+Alt+Shift+Super+A");
        let bindings = parsed(&value).unwrap();
        assert_eq!(bindings.len(), 1);
        assert_eq!(bindings[0].0, "selection");
        assert_eq!(
            bindings[0].1.id(),
            "Ctrl+Alt+Shift+Super+A".parse::<Shortcut>().unwrap().id()
        );
    }

    #[test]
    fn platform_command_or_control_aliases_are_explicit() {
        for name in [
            "CmdOrCtrl",
            "CommandOrControl",
            "CommandOrCtrl",
            "CmdOrControl",
        ] {
            assert_eq!(
                normalize_one(&format!("{name}+A"), true).unwrap(),
                "Super+A"
            );
            assert_eq!(
                normalize_one(&format!("{name}+A"), false).unwrap(),
                "Ctrl+A"
            );
        }
        assert_eq!(
            normalized(&only("CmdOrCtrl+A")).unwrap().selection,
            if cfg!(target_os = "macos") {
                "Super+A"
            } else {
                "Ctrl+A"
            }
        );
    }

    #[test]
    fn windows_meta_and_command_names_resolve_to_same_super_binding() {
        for alias in ["Win", "Windows", "Meta", "Cmd", "Command", "Super"] {
            assert_eq!(
                normalized(&only(&format!("{alias}+S"))).unwrap().selection,
                "Super+S"
            );
        }
    }

    #[test]
    fn rejects_repeated_alias_modifiers_and_missing_or_multiple_keys() {
        for invalid in [
            "Ctrl+Control+A",
            "Win+Meta+A",
            "Alt+Option+A",
            "Shift+Shift+A",
            "Ctrl",
            "Ctrl+Alt+Shift+Super",
            "Ctrl+A+B",
            "Ctrl++A",
            "+Ctrl+A",
            "Ctrl+A+",
        ] {
            assert!(normalized(&only(invalid)).is_err(), "{invalid}");
        }
        let duplicate = if cfg!(target_os = "macos") {
            "CmdOrCtrl+Cmd+A"
        } else {
            "CmdOrCtrl+Ctrl+A"
        };
        assert!(normalized(&only(duplicate)).is_err());
    }

    #[test]
    fn does_not_let_bare_typing_or_shift_only_ordinary_keys_become_global_shortcuts() {
        for invalid in [
            "A",
            "KeyZ",
            "3",
            "Space",
            "Shift+A",
            "Shift+Enter",
            "Shift+Equal",
            "Escape",
            "MediaPlay",
        ] {
            assert!(normalized(&only(invalid)).is_err(), "{invalid}");
        }
        assert_eq!(
            normalized(&only("Ctrl+Shift+Equal")).unwrap().selection,
            "Ctrl+Shift+Equal"
        );
    }

    #[test]
    fn all_function_keys_from_f1_to_f24_can_be_used_without_other_modifiers() {
        for number in 1..=24 {
            let value = format!("F{number}");
            assert_eq!(normalized(&only(&value)).unwrap().selection, value);
            assert_eq!(parsed(&only(&value)).unwrap().len(), 1);
        }
        for invalid in ["F0", "F25", "F01", "F001", "Ctrl+F100"] {
            assert!(normalized(&only(invalid)).is_err(), "{invalid}");
        }
    }

    #[test]
    fn empty_fields_disable_actions_and_defaults_stay_compatible() {
        let all_empty = Shortcuts {
            selection: "  ".into(),
            ..only("")
        };
        assert!(parsed(&all_empty).unwrap().is_empty());
        let defaults = normalized(&Shortcuts::default()).unwrap();
        assert_eq!(defaults.selection, "Alt+D");
        assert_eq!(defaults.silent_ocr, "Alt+S");
        assert_eq!(defaults.ocr, "Alt+Shift+S");
        assert_eq!(defaults.input, "Alt+A");
        assert!(defaults.capture.is_empty());
        assert_eq!(parsed(&defaults).unwrap().len(), 4);
    }

    #[test]
    fn normalizes_every_field_without_changing_action_identity() {
        let input = Shortcuts {
            selection: "control+keyd".into(),
            capture: "alt+digit1".into(),
            ocr: "shift+alt+S".into(),
            silent_ocr: "alt+s".into(),
            input: "meta+return".into(),
        };
        let value = normalized(&input).unwrap();
        assert_eq!(value.selection, "Ctrl+D");
        assert_eq!(value.capture, "Alt+1");
        assert_eq!(value.ocr, "Alt+Shift+S");
        assert_eq!(value.silent_ocr, "Alt+S");
        assert_eq!(value.input, "Super+Enter");
        assert_eq!(
            parsed(&input)
                .unwrap()
                .iter()
                .map(|(action, _)| action.as_str())
                .collect::<Vec<_>>(),
            ["selection", "capture", "ocr", "silentOcr", "input"]
        );
    }

    #[test]
    fn conflicts_use_real_shortcut_ids_across_all_five_fields() {
        for field in 0..4 {
            let mut values = only("Ctrl+KeyA");
            let slot = match field {
                0 => &mut values.capture,
                1 => &mut values.ocr,
                2 => &mut values.silent_ocr,
                _ => &mut values.input,
            };
            *slot = "Control+A".into();
            assert!(normalized(&values).unwrap_err().contains("相同"));
            assert!(parsed(&values).is_err());
        }
        let alias = Shortcuts {
            selection: "Win+S".into(),
            input: "Meta+KeyS".into(),
            ..only("")
        };
        assert!(parsed(&alias).is_err());
    }

    #[test]
    fn top_row_and_numpad_keys_remain_distinct_real_bindings() {
        let values = Shortcuts {
            selection: "Ctrl+Digit1".into(),
            capture: "Ctrl+Numpad1".into(),
            ..only("")
        };
        let bindings = parsed(&values).unwrap();
        assert_eq!(bindings.len(), 2);
        assert_ne!(bindings[0].1.id(), bindings[1].1.id());
    }

    #[test]
    fn canonical_named_keys_are_validated_by_the_pinned_real_parser() {
        for name in NAMED_KEYS {
            let value = normalized(&only(&format!("Ctrl+{name}"))).unwrap();
            assert_eq!(value.selection, format!("Ctrl+{name}"));
        }
        for (alias, canonical) in [
            ("/", "Slash"),
            ("=", "Equal"),
            ("return", "Enter"),
            ("spacebar", "Space"),
            ("[", "BracketLeft"),
            ("`", "Backquote"),
        ] {
            assert_eq!(
                normalized(&only(&format!("Ctrl+{alias}")))
                    .unwrap()
                    .selection,
                format!("Ctrl+{canonical}")
            );
        }
    }

    #[test]
    fn normalizes_key_after_modifier_even_when_the_input_order_is_unusual() {
        assert_eq!(
            normalized(&only("a+Alt+Ctrl")).unwrap().selection,
            "Ctrl+Alt+A"
        );
        assert_eq!(normalized(&only("shift+F2")).unwrap().selection, "Shift+F2");
    }

    #[test]
    fn rejects_control_characters_excess_length_and_unknown_keys_before_registration() {
        for invalid in [
            "\nCtrl+A",
            "Ctrl+A\r",
            "Ctrl+\0A",
            "Ctrl+AltGraph",
            "Ctrl+Dead",
            "Ctrl+键",
            "Ctrl+LaunchMail",
        ] {
            assert!(normalized(&only(invalid)).is_err(), "{invalid:?}");
        }
        assert!(normalized(&only(&format!("{}Ctrl+A", " ".repeat(75)))).is_err());
        assert_eq!(
            normalized(&only(&format!("{}Ctrl+A", " ".repeat(74))))
                .unwrap()
                .selection,
            "Ctrl+A"
        );
    }
}
