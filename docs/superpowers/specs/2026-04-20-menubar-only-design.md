# Menubar-Only Mic Mute — Design Spec

**Date:** 2026-04-20

## Summary

Convert MicMuteApp from a main-window app to a menubar-only app. The main window, `MainViewController`, and `CircleButton` are removed. A new `MenubarController` class adds an `NSStatusItem` with a dropdown menu for device selection and mute toggling.

## Decisions

| Topic | Decision |
|---|---|
| App style | Menubar-only (`NSApp.setActivationPolicy(.accessory)`) |
| Interaction | Click icon → native `NSMenu` dropdown |
| Icon | Nerd Font glyphs `󰍬` (unmuted) / `󰍭` (muted) via MesloLGSNF-Bold, fallback to system font |
| Scope | Single file (`MicMuteApp.swift`), no new files |
| Build | Unchanged: `swiftc MicMuteApp.swift -framework AppKit -framework CoreAudio -o MicMuteApp` |

## Architecture

All changes stay in `MicMuteApp.swift`.

**Removed:**
- `CircleButton` class
- `MainViewController` class
- Window creation and `applicationShouldTerminateAfterLastWindowClosed` in `AppDelegate`

**Added:**
- `MenubarController` — owns `NSStatusItem`, builds and updates `NSMenu`, handles mute toggle and device selection
- Icon rendering via `NSImage` drawn from `NSAttributedString` (same Nerd Font approach as existing `CircleButton`)

**Unchanged:**
- `listInputDevices()` — CoreAudio device enumeration
- `getMuteState(_:)` — hardware mute + volume fallback
- `setMuteState(_:muted:)` — hardware mute + volume fallback
- `AppDelegate` structure (minus window code)

## Menu Structure

```
[Input Device]          ← section label (disabled)
  ✓ MacBook Pro Mic     ← checkmark on selected device
    External USB Mic    ← other devices
──────────────────
󰍬 Unmuted — click to mute   (or 󰍭 Muted — click to unmute)
──────────────────
Quit Mic Mute
```

- Device list rebuilt on every menu open (handles hot-plug)
- Selecting a device updates the mute state display immediately
- Mute toggle item shows current state and action

## Out of Scope

- Keyboard shortcut for mute toggle
- Persisting selected device across restarts
- Notifications / sound feedback on mute change
