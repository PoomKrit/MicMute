// MicMuteApp.swift
// Build: swiftc MicMuteApp.swift -framework AppKit -framework CoreAudio -o MicMuteApp
// Run:   ./MicMuteApp

import AppKit
import CoreAudio

// MARK: - CoreAudio Utilities

func listInputDevices() -> [(id: AudioDeviceID, name: String)] {
    var prop = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil, &dataSize
    ) == noErr, dataSize > 0 else { return [] }

    var ids = [AudioDeviceID](repeating: 0, count: Int(dataSize) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil, &dataSize, &ids
    ) == noErr else { return [] }

    return ids.compactMap { id in
        // Filter to input-only devices
        var streamProp = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &streamProp, 0, nil, &streamSize) == noErr,
              streamSize > 0 else { return nil }

        var nameProp = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfName: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        AudioObjectGetPropertyData(id, &nameProp, 0, nil, &nameSize, &cfName)
        return (id: id, name: cfName as String)
    }
}

func getMuteState(_ deviceID: AudioDeviceID) -> Bool {
    var prop = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var muted: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    if AudioObjectGetPropertyData(deviceID, &prop, 0, nil, &size, &muted) == noErr {
        return muted == 1
    }
    // Fallback for devices that don't support hardware mute: treat near-zero volume as muted
    var volProp = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var volume: Float32 = 1.0
    var volSize = UInt32(MemoryLayout<Float32>.size)
    AudioObjectGetPropertyData(deviceID, &volProp, 0, nil, &volSize, &volume)
    return volume < 0.01
}

@discardableResult
func setMuteState(_ deviceID: AudioDeviceID, muted: Bool) -> OSStatus {
    var prop = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    // Check if hardware mute is supported and settable
    var settable: DarwinBoolean = false
    if AudioObjectIsPropertySettable(deviceID, &prop, &settable) == noErr, settable.boolValue {
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(
            deviceID, &prop, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
        )
    }
    // Fallback for external mics that don't support hardware mute: use volume scalar
    var volProp = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var volume: Float32 = muted ? 0.0 : 1.0
    return AudioObjectSetPropertyData(
        deviceID, &volProp, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume
    )
}

// MARK: - Menubar Controller

final class MenubarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var selectedDeviceID: AudioDeviceID?

    override init() {
        super.init()
        selectedDeviceID = listInputDevices().first?.id
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

    @objc private func toggleMenu(_ sender: Any?) {
        let menu = buildMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
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
        if devices.isEmpty {
            let none = NSMenuItem(title: "No input devices found", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }

        menu.addItem(.separator())

        // Mute toggle item
        let isMuted = selectedDeviceID.map { getMuteState($0) } ?? false
        let toggleTitle = isMuted ? "\u{F036D}  Muted — click to unmute" : "\u{F036C}  Unmuted — click to mute"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleMute), keyEquivalent: "")
        if selectedDeviceID != nil {
            toggleItem.target = self
        } else {
            toggleItem.isEnabled = false
        }
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
        if setMuteState(id, muted: newState) == noErr {
            updateIcon()
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menubarController: MenubarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menubarController = MenubarController()
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.activate(ignoringOtherApps: true)
app.run()
