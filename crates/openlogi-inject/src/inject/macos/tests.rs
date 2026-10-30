use core_graphics::event::{CGEventFlags, EventField};
use openlogi_core::binding::Shortcut;

use super::{LOCK_SCREEN_CHORD, combo, held_key_event, hid_usage_to_macos, key_event};
use crate::inject::{HeldKey, HeldModifiers, KeyPhase, parse_shortcut};

#[test]
fn hid_usages_map_to_macos_virtual_keys() {
    assert_eq!(hid_usage_to_macos(0x04), Some(0x00));
    assert_eq!(hid_usage_to_macos(0x13), Some(0x23));
    assert_eq!(hid_usage_to_macos(0x50), Some(0x7b));
    assert_eq!(hid_usage_to_macos(0x3a), Some(0x7a));
    assert_eq!(hid_usage_to_macos(0x6f), Some(0x5a));
    assert_eq!(hid_usage_to_macos(0xff), None);
}

/// Pin a handful of representative `Shortcut -> KeyCombo` rows so an
/// edit to the table can't silently change what ⌘C sends. macOS and
/// Linux only overlap on the letter-key chords: both `BrowserBack` and
/// `Redo` differ across the three backends by design (see the module
/// doc on `combo`), so each backend pins its own rows independently.
#[test]
fn combo_table_pins_representative_shortcuts() {
    assert_eq!(combo(Shortcut::Copy).rendered_label(), "Cmd+C");
    assert_eq!(combo(Shortcut::Redo).rendered_label(), "Cmd+Shift+Z");
    assert_eq!(combo(Shortcut::BrowserBack).rendered_label(), "Cmd+[");
    assert_eq!(combo(Shortcut::NextTab).rendered_label(), "Ctrl+Tab");
    // hid_usage_to_macos must actually resolve every table entry, or a
    // `Shortcut` silently no-ops instead of pressing anything (see
    // `press_combo`'s warn-and-drop path). Iterates `Shortcut::ALL`
    // rather than a hand-copied list, so a newly added `Shortcut`
    // variant is checked here automatically instead of depending on
    // someone remembering to extend a second, independent list.
    for &shortcut in Shortcut::ALL {
        let key = combo(shortcut).key().code();
        assert!(
            hid_usage_to_macos(key).is_some(),
            "{shortcut:?} table entry has no macOS virtual-key mapping"
        );
    }
}

/// Lock Screen is the one chord outside the `combo` table, so the table loop
/// above never parses it. Pin it the same way: it must parse to the chord the
/// Apple menu shows, and its key must resolve to a macOS virtual key.
#[test]
fn lock_screen_chord_parses_and_resolves() {
    let chord = parse_shortcut(LOCK_SCREEN_CHORD);
    assert_eq!(chord.rendered_label(), "Cmd+Ctrl+Q");
    assert!(
        hid_usage_to_macos(chord.key().code()).is_some(),
        "the Lock Screen chord has no macOS virtual-key mapping"
    );
}

#[test]
fn held_edges_carry_the_aggregate_modifier_state() {
    let mut modifiers = HeldModifiers::default();
    let (_, flags) = held_key_event(HeldKey::Command, KeyPhase::Down, &mut modifiers)
        .expect("Command has a macOS virtual-key mapping");
    assert!(flags.contains(CGEventFlags::CGEventFlagCommand));

    let (_, flags) = held_key_event(HeldKey::Control, KeyPhase::Down, &mut modifiers)
        .expect("Control has a macOS virtual-key mapping");
    assert!(flags.contains(CGEventFlags::CGEventFlagCommand));
    assert!(flags.contains(CGEventFlags::CGEventFlagControl));

    let key = combo(Shortcut::Copy).key();
    let (_, flags) = held_key_event(HeldKey::Key(key), KeyPhase::Up, &mut modifiers)
        .expect("Copy's key has a macOS virtual-key mapping");
    assert!(flags.contains(CGEventFlags::CGEventFlagCommand));
    assert!(flags.contains(CGEventFlags::CGEventFlagControl));

    let (_, flags) = held_key_event(HeldKey::Command, KeyPhase::Up, &mut modifiers)
        .expect("Command has a macOS virtual-key mapping");
    assert!(!flags.contains(CGEventFlags::CGEventFlagCommand));
    assert!(flags.contains(CGEventFlags::CGEventFlagControl));
}

/// The hook skips a key edge only by this tag, so every edge the backend
/// posts must carry it.
#[test]
fn posted_key_edges_carry_the_synthetic_tag() {
    for phase in [KeyPhase::Down, KeyPhase::Up] {
        let event =
            key_event(0x0c, CGEventFlags::CGEventFlagCommand, phase).expect("a keyboard event");
        assert_eq!(
            event.get_integer_value_field(EventField::EVENT_SOURCE_USER_DATA),
            crate::SYNTHETIC_EVENT_USER_DATA
        );
    }
}

#[test]
fn screenflare_actions_open_the_app_url() {
    // The URL is the whole contract with ScreenflareX: one scheme, the id as the host.
    assert_eq!(
        super::screenflare_url("capture-window"),
        "screenflarex://capture-window"
    );
    assert_eq!(super::screenflare_url("toggle"), "screenflarex://toggle");
    assert_eq!(
        super::screenflare_url("stop-recording"),
        "screenflarex://stop-recording"
    );
}

#[test]
fn screenflare_fallback_spawns_ctl_detached_with_the_mapped_arguments() {
    use std::os::unix::fs::PermissionsExt;

    let dir = std::env::temp_dir().join(format!("openlogi-screenflare-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("create temp dir");
    let args_file = dir.join("args");
    let script = dir.join("screenflare-ctl");
    std::fs::write(
        &script,
        format!(
            "#!/bin/sh\nprintf '%s\\n' \"$@\" > '{}'\n",
            args_file.display()
        ),
    )
    .expect("write fake ctl");
    std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).expect("chmod +x");

    super::spawn_screenflare(&script, "capture-window");

    // The child is detached on purpose; wait for its side effect instead of it.
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    while std::time::Instant::now() < deadline && !args_file.exists() {
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    let recorded = std::fs::read_to_string(&args_file).expect("screenflare-ctl did not run");
    assert_eq!(
        recorded.lines().collect::<Vec<_>>(),
        ["action", "capture-window", "--no-wait", "--json"]
    );
    let _ = std::fs::remove_dir_all(&dir);
}
