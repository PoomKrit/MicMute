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
    AudioObjectGetPropertyData(deviceID, &prop, 0, nil, &size, &muted)
    return muted == 1
}

@discardableResult
func setMuteState(_ deviceID: AudioDeviceID, muted: Bool) -> OSStatus {
    var prop = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var value: UInt32 = muted ? 1 : 0
    return AudioObjectSetPropertyData(
        deviceID, &prop, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
    )
}

// MARK: - Circle Button

final class CircleButton: NSView {
    var isMuted = false { didSet { needsDisplay = true } }
    var onTap: (() -> Void)?

    private let greenColor = NSColor(calibratedRed: 0.46, green: 0.72, blue: 0.46, alpha: 1)
    private let redColor   = NSColor(calibratedRed: 0.78, green: 0.32, blue: 0.28, alpha: 1)

    override func draw(_ dirtyRect: NSRect) {
        let ovalRect = bounds.insetBy(dx: 4, dy: 4)
        let path = NSBezierPath(ovalIn: ovalRect)

        (isMuted ? redColor : greenColor).setFill()
        path.fill()

        NSColor.black.setStroke()
        path.lineWidth = 2.5
        path.stroke()

        let label = isMuted ? "󰍭" : "󰍬"
        let iconFont = NSFont(name: "MesloLGSNF-Bold", size: 72) ?? NSFont.boldSystemFont(ofSize: 72)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: iconFont,
            .foregroundColor: NSColor.black
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        // Horizontal: use glyph-path midX so the muted icon (whose ink is wider than
        // its advance width) is visually centred rather than shifted right.
        // Vertical: use sz.height/2 (full line-box) because the draw origin is the
        // bottom of the line box, not the baseline — gb.midY alone overshoots.
        let ctLine = CTLineCreateWithAttributedString(str)
        let gb = CTLineGetBoundsWithOptions(ctLine, .useGlyphPathBounds)
        let sz = str.size()
        str.draw(at: NSPoint(x: bounds.midX - gb.midX, y: bounds.midY - sz.height / 2))
    }

    override func mouseDown(with event: NSEvent) { onTap?() }

    // Clicks only register inside the circle
    override func hitTest(_ point: NSPoint) -> NSView? {
        // point is in the superview's coordinate space; convert to local before comparing
        let local = convert(point, from: superview)
        let dx = local.x - bounds.midX
        let dy = local.y - bounds.midY
        let r = min(bounds.width, bounds.height) / 2 - 4
        return dx * dx + dy * dy <= r * r ? self : nil
    }
}

// MARK: - Main View Controller

final class MainViewController: NSViewController {
    private let popup  = NSPopUpButton()
    private let circle = CircleButton()
    private var devices: [(id: AudioDeviceID, name: String)] = []

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 400))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.76, alpha: 1).cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupMicSelector()
        setupMuteCircle()
        loadDevices()
    }

    private func setupMicSelector() {
        // Blue pill container
        let pill = NSView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor(calibratedRed: 0.45, green: 0.75, blue: 0.95, alpha: 1).cgColor
        pill.layer?.cornerRadius = 22
        view.addSubview(pill)
        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pill.topAnchor.constraint(equalTo: view.topAnchor, constant: 60),
            pill.widthAnchor.constraint(equalToConstant: 280),
            pill.heightAnchor.constraint(equalToConstant: 44)
        ])

        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.isBordered = false
        popup.font = NSFont.boldSystemFont(ofSize: 14)
        popup.contentTintColor = .black
        popup.target = self
        popup.action = #selector(deviceChanged)
        pill.addSubview(popup)
        NSLayoutConstraint.activate([
            popup.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 12),
            popup.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -12),
            popup.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
        ])
    }

    private func setupMuteCircle() {
        circle.translatesAutoresizingMaskIntoConstraints = false
        circle.onTap = { [weak self] in self?.toggleMute() }
        view.addSubview(circle)
        NSLayoutConstraint.activate([
            circle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            circle.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 60),
            circle.widthAnchor.constraint(equalToConstant: 180),
            circle.heightAnchor.constraint(equalToConstant: 180)
        ])
    }

    private func loadDevices() {
        devices = listInputDevices()
        popup.removeAllItems()
        devices.forEach { popup.addItem(withTitle: $0.name) }
        syncButtonState()
    }

    private func syncButtonState() {
        let idx = popup.indexOfSelectedItem
        guard idx >= 0, idx < devices.count else { return }
        circle.isMuted = getMuteState(devices[idx].id)
    }

    @objc private func deviceChanged() { syncButtonState() }

    private func toggleMute() {
        let idx = popup.indexOfSelectedItem
        guard idx >= 0, idx < devices.count else { return }
        let newState = !getMuteState(devices[idx].id)
        setMuteState(devices[idx].id, muted: newState)
        // Re-read the actual hardware state so the button always reflects reality
        circle.isMuted = getMuteState(devices[idx].id)
    }
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
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
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
