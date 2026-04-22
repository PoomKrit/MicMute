![Mic Mute Button](20260305_121607247_iOS%20Small.png)

# Mic Mute Button

A minimal native macOS menubar app to toggle microphone mute with a single click. No Xcode required — just a single Swift source file compiled with `swiftc`.

## Features

- Lives in the menubar — no Dock icon, no window
- Click the menubar icon to open a popover panel
- Select input device with visual checkmark highlight
- Mute / unmute toggle with red/green indicator
- Reads and sets hardware mute state via CoreAudio
- Falls back to volume scalar for devices without hardware mute support

## Requirements

- macOS 12 or later
- Xcode Command Line Tools (`xcode-select --install`)
- [MesloLGS NF](https://github.com/romkatv/powerlevel10k#meslo-nerd-font-patched-for-powerlevel10k) font (optional — used for mic icons; falls back to system font)

## Build & Run

```bash
chmod +x build.sh
./build.sh
```

This compiles `MicMuteApp.swift`, assembles `MicMuteApp.app` with an icon and `Info.plist`, ad-hoc signs it, and prints the path.

You can then drag `MicMuteApp.app` to `/Applications` or double-click it from Finder.

To compile manually without building an `.app` bundle:

```bash
swiftc MicMuteApp.swift -framework AppKit -framework CoreAudio -o MicMuteApp
./MicMuteApp
```

## Files

| File | Description |
|------|-------------|
| `MicMuteApp.swift` | Full app source (CoreAudio + AppKit) |
| `build.sh` | Builds `.app` bundle, copies icon, signs with ad-hoc identity |
| `AppIcon.icns` | App icon |

## How It Works

- **CoreAudio** is used directly (no AVFoundation) to enumerate input devices and read/write `kAudioDevicePropertyMute` on the input scope.
- **NSStatusItem** places the app in the macOS menubar with a Nerd Font mic glyph icon.
- **NSPopover** shows a floating panel on click — stays open while interacting, closes on click-outside.
- **PopoverViewController** builds the device list and mute toggle using `NSStackView` and `NSButton`.

## Known Limitations

- Devices that don't support hardware mute fall back to volume scalar (set to 0.0 for mute).

---

## Release Notes

### v2.2.0 — 2026-04-22

**Menubar icon color**

- Icon turns red when muted, white when unmuted

### v2.1.0 — 2026-04-22

**Popover layout refinement**

- Moved mute toggle button to top of popover for faster access
- Moved input device list below the toggle

### v2.0.0 — 2026-04-21

**Menubar-only redesign**

- Converted from a floating window app to a menubar-only app (no Dock icon)
- Replaced window + CircleButton UI with an `NSPopover` panel
- Popover stays open while interacting; closes when clicking outside
- Device list shows checkmark + accent color + semibold font on selected device
- Mute toggle button shows green (unmuted) / red (muted) with Nerd Font icons
- Removed `MainViewController` and `CircleButton` classes

### v1.1.0 — 2026-03-06

**External mic support**

- Added volume scalar fallback for devices that don't support hardware mute (`kAudioDevicePropertyMute`)
- Fixes mute toggle being silently ignored on USB/external microphones

### v1.0.0 — 2026-03-05

**Initial release**

- Single-window app with circle button UI (green = unmuted, red = muted)
- Dropdown to select between multiple input devices
- CoreAudio hardware mute via `kAudioDevicePropertyMute`
- Single-file build with `swiftc`, no Xcode required
