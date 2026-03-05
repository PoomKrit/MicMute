![Mic Mute Button](20260305_121607247_iOS%20Small.png)

# Mic Mute Button

A minimal native macOS app to toggle microphone mute with a single click. No Xcode required — just a single Swift source file compiled with `swiftc`.

## Features

- Circle button UI: green (unmuted) / red (muted)
- Dropdown to select between multiple input devices
- Reads and sets hardware mute state via CoreAudio
- Keyboard shortcut: Cmd+Q to quit

## Requirements

- macOS 12 or later
- Xcode Command Line Tools (`xcode-select --install`)
- [MesloLGS NF](https://github.com/romkatv/powerlevel10k#meslo-nerd-font-patched-for-powerlevel10k) font (optional — used for mic icons; falls back to system bold font)

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
- **CircleButton** is a custom `NSView` subclass with a circular hit-test so clicks outside the circle are ignored.
- The app runs as a regular (dock-visible) application via `NSApplication`.

## Known Limitations

- Devices that don't support hardware mute (`kAudioDevicePropertyMute`) will silently ignore mute toggle calls. No software volume fallback is implemented.
