# Menubar-Only Mic Mute Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert MicMuteApp from a floating window app to a menubar-only app with device selection and mute toggle in a dropdown menu.

**Architecture:** Single file `MicMuteApp.swift`. Remove `CircleButton` and `MainViewController`. Add `MenubarController` that owns an `NSStatusItem` and rebuilds its `NSMenu` on every open. `AppDelegate` switches to `.accessory` activation policy.

**Tech Stack:** Swift, AppKit (`NSStatusItem`, `NSMenu`, `NSImage`), CoreAudio — no new dependencies.

---

### Task 1: Remove CircleButton and MainViewController

**Files:**
- Modify: `MicMuteApp.swift`

- [ ] **Step 1: Delete `CircleButton` class**

Remove lines 101–147 (the entire `// MARK: - Circle Button` section and `CircleButton` class).

- [ ] **Step 2: Delete `MainViewController` class**

Remove lines 149–233 (the entire `// MARK: - Main View Controller` section and `MainViewController` class).

- [ ] **Step 3: Verify file compiles (will fail at AppDelegate — that's expected)**

```bash
swiftc MicMuteApp.swift -framework AppKit -framework CoreAudio -o /tmp/test_build 2>&1 | head -20
```

Expected: errors about `MainViewController` not found inside `AppDelegate` — that's fine, next task fixes it.

- [ ] **Step 4: Commit**

```bash
git add MicMuteApp.swift
git commit -m "Remove CircleButton and MainViewController"
```

---

### Task 2: Rewrite AppDelegate to menubar-only

**Files:**
- Modify: `MicMuteApp.swift` — `AppDelegate` section

- [ ] **Step 1: Replace the entire `AppDelegate` class** with this:

```swift
// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menubarController: MenubarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menubarController = MenubarController()
    }
}
```

- [ ] **Step 2: Verify file compiles (will fail — MenubarController not defined yet)**

```bash
swiftc MicMuteApp.swift -framework AppKit -framework CoreAudio -o /tmp/test_build 2>&1 | head -20
```

Expected: error `cannot find type 'MenubarController'` — correct, next task adds it.

- [ ] **Step 3: Commit**

```bash
git add MicMuteApp.swift
git commit -m "Rewrite AppDelegate for menubar-only"
```

---

### Task 3: Add MenubarController

**Files:**
- Modify: `MicMuteApp.swift` — add new class before `AppDelegate`

- [ ] **Step 1: Add `MenubarController` class** — insert this block before `// MARK: - App Delegate`:

```swift
// MARK: - Menubar Controller

final class MenubarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var selectedDeviceID: AudioDeviceID?

    override init() {
        super.init()
        updateIcon()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggleMenu(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    // MARK: Icon

    private func makeIcon(muted: Bool) -> NSImage? {
        let glyph = muted ? "\u{F036D}" : "\u{F036C}"  // 󰍭 / 󰍬
        let font = NSFont(name: "MesloLGSNF-Bold", size: 16) ?? NSFont.systemFont(ofSize: 16)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let str = NSAttributedString(string: glyph, attributes: attrs)
        let size = str.size()
        let image = NSImage(size: size)
        image.lockFocus()
        str.draw(at: .zero)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func updateIcon() {
        let muted: Bool
        if let id = selectedDeviceID {
            muted = getMuteState(id)
        } else {
            muted = false
        }
        statusItem.button?.image = makeIcon(muted: muted)
    }

    // MARK: Menu

    @objc private func toggleMenu(_ sender: NSStatusBarButton) {
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Device section label
        let label = NSMenuItem(title: "Input Device", action: nil, keyEquivalent: "")
        label.isEnabled = false
        menu.addItem(label)

        // Device list
        let devices = listInputDevices()
        if selectedDeviceID == nil {
            selectedDeviceID = devices.first?.id
        }
        for device in devices {
            let item = NSMenuItem(
                title: device.name,
                action: #selector(selectDevice(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device.id as AnyObject
            item.state = device.id == selectedDeviceID ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // Mute toggle item
        let isMuted = selectedDeviceID.map { getMuteState($0) } ?? false
        let toggleTitle = isMuted ? "\u{F036D}  Muted — click to unmute" : "\u{F036C}  Unmuted — click to mute"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleMute), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        // Quit
        let quit = NSMenuItem(
            title: "Quit Mic Mute",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        return menu
    }

    // MARK: Actions

    @objc private func selectDevice(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? AudioDeviceID else { return }
        selectedDeviceID = id
        updateIcon()
    }

    @objc private func toggleMute() {
        guard let id = selectedDeviceID else { return }
        let newState = !getMuteState(id)
        setMuteState(id, muted: newState)
        updateIcon()
    }
}
```

- [ ] **Step 2: Build and verify it compiles cleanly**

```bash
swiftc MicMuteApp.swift -framework AppKit -framework CoreAudio -o /tmp/test_build 2>&1
```

Expected: no errors, binary produced at `/tmp/test_build`.

- [ ] **Step 3: Quick smoke test — run the binary**

```bash
/tmp/test_build &
sleep 2
kill %1
```

Expected: menubar icon appears briefly, no crash.

- [ ] **Step 4: Commit**

```bash
git add MicMuteApp.swift
git commit -m "Add MenubarController with NSStatusItem and dropdown menu"
```

---

### Task 4: Build app bundle and verify end-to-end

**Files:**
- No code changes — run `build.sh` and manually test

- [ ] **Step 1: Build the app bundle**

```bash
bash build.sh
```

Expected output:
```
Compiling...
Building app bundle...
Done! MicMuteApp.app is ready.
```

- [ ] **Step 2: Launch the app**

```bash
open MicMuteApp.app
```

Expected: menubar icon appears (mic glyph), no Dock icon, no window.

- [ ] **Step 3: Verify dropdown menu**

Click the menubar icon. Expected menu:
- "Input Device" label (greyed, unclickable)
- One or more mic devices listed with checkmark on active
- Separator
- Mute toggle item showing current state
- Separator
- "Quit Mic Mute"

- [ ] **Step 4: Toggle mute**

Click the mute/unmute item. Expected: icon updates to reflect new state, clicking again restores original state.

- [ ] **Step 5: Switch device (if multiple mics available)**

Click a different device in the menu. Expected: checkmark moves, mute item reflects the new device's state.

- [ ] **Step 6: Quit via menu**

Click "Quit Mic Mute". Expected: app exits, icon removed from menubar.

- [ ] **Step 7: Final commit**

```bash
git add MicMuteApp.swift
git commit -m "Menubar-only conversion complete"
```
