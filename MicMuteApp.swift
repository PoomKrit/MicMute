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

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Minimal menu (enables Cmd+Q)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit Mic Mute",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mic Mute"
        window.contentViewController = MainViewController()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Entry Point

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
