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

// MARK: - Popover View Controller

final class PopoverViewController: NSViewController {
    var onDeviceSelected: ((AudioDeviceID) -> Void)?
    var onMuteToggled: (() -> Void)?
    var onQuit: (() -> Void)?

    private var selectedDeviceID: AudioDeviceID?
    private var devices: [(id: AudioDeviceID, name: String)] = []

    private let stackView = NSStackView()
    private let muteButton = NSButton()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 0))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 4
        stackView.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        rebuild()
    }

    func update(devices: [(id: AudioDeviceID, name: String)], selectedDeviceID: AudioDeviceID?) {
        self.devices = devices
        self.selectedDeviceID = selectedDeviceID
        if isViewLoaded { rebuild() }
    }

    private func rebuild() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Mute button
        let isMuted = selectedDeviceID.map { getMuteState($0) } ?? false
        let muteTitle = isMuted ? "\u{F036D}  Muted — click to unmute" : "\u{F036C}  Unmuted — click to mute"
        muteButton.title = muteTitle
        muteButton.bezelStyle = .roundRect
        muteButton.setButtonType(.momentaryPushIn)
        muteButton.font = NSFont.systemFont(ofSize: 13)
        muteButton.contentTintColor = isMuted ? .systemRed : .systemGreen
        muteButton.target = self
        muteButton.action = #selector(muteClicked)
        muteButton.isEnabled = selectedDeviceID != nil
        muteButton.translatesAutoresizingMaskIntoConstraints = false
        muteButton.widthAnchor.constraint(equalToConstant: 228).isActive = true
        stackView.addArrangedSubview(muteButton)

        // Divider
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 228).isActive = true
        stackView.addArrangedSubview(divider)

        // Section label
        let label = NSTextField(labelWithString: "INPUT DEVICE")
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(label)

        // Device buttons
        if devices.isEmpty {
            let none = NSTextField(labelWithString: "No input devices found")
            none.font = NSFont.systemFont(ofSize: 13)
            none.textColor = .secondaryLabelColor
            stackView.addArrangedSubview(none)
        } else {
            for device in devices {
                let isSelected = device.id == selectedDeviceID
                let title = isSelected ? "✓  \(device.name)" : "     \(device.name)"
                let btn = NSButton(title: title, target: self, action: #selector(deviceClicked(_:)))
                btn.tag = Int(device.id)
                btn.bezelStyle = .roundRect
                btn.setButtonType(.momentaryPushIn)
                btn.font = NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular)
                btn.contentTintColor = isSelected ? .controlAccentColor : .labelColor
                btn.translatesAutoresizingMaskIntoConstraints = false
                btn.widthAnchor.constraint(equalToConstant: 228).isActive = true
                stackView.addArrangedSubview(btn)
            }
        }

        // Divider
        let divider2 = NSBox()
        divider2.boxType = .separator
        divider2.translatesAutoresizingMaskIntoConstraints = false
        divider2.widthAnchor.constraint(equalToConstant: 228).isActive = true
        stackView.addArrangedSubview(divider2)

        // Quit button
        let quitBtn = NSButton(title: "Quit Mic Mute", target: self, action: #selector(quitClicked))
        quitBtn.bezelStyle = .roundRect
        quitBtn.setButtonType(.momentaryPushIn)
        quitBtn.font = NSFont.systemFont(ofSize: 13)
        quitBtn.translatesAutoresizingMaskIntoConstraints = false
        quitBtn.widthAnchor.constraint(equalToConstant: 228).isActive = true
        stackView.addArrangedSubview(quitBtn)

        view.layoutSubtreeIfNeeded()
    }

    @objc private func deviceClicked(_ sender: NSButton) {
        let id = AudioDeviceID(sender.tag)
        onDeviceSelected?(id)
    }

    @objc private func muteClicked() {
        onMuteToggled?()
    }

    @objc private func quitClicked() {
        onQuit?()
    }
}

// MARK: - Menubar Controller

final class MenubarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let popoverVC = PopoverViewController()
    private var selectedDeviceID: AudioDeviceID?

    override init() {
        super.init()
        selectedDeviceID = listInputDevices().first?.id

        popoverVC.onDeviceSelected = { [weak self] id in
            self?.selectedDeviceID = id
            self?.refreshPopover()
            self?.updateIcon()
        }
        popoverVC.onMuteToggled = { [weak self] in
            guard let self, let id = self.selectedDeviceID else { return }
            let newState = !getMuteState(id)
            if setMuteState(id, muted: newState) == noErr {
                self.refreshPopover()
                self.updateIcon()
            }
        }
        popoverVC.onQuit = {
            NSApplication.shared.terminate(nil)
        }

        popover.contentViewController = popoverVC
        popover.behavior = .transient
        popover.animates = true

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        updateIcon()
    }

    // MARK: Icon

    private func makeIcon(muted: Bool) -> NSImage? {
        let glyph = muted ? "\u{F036D}" : "\u{F036C}"
        let font = NSFont(name: "MesloLGSNF-Bold", size: 16) ?? NSFont.systemFont(ofSize: 16)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: muted ? NSColor.systemRed : NSColor.white
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
        let muted = selectedDeviceID.map { getMuteState($0) } ?? false
        statusItem.button?.image = makeIcon(muted: muted)
    }

    private func refreshPopover() {
        popoverVC.update(devices: listInputDevices(), selectedDeviceID: selectedDeviceID)
    }

    // MARK: Actions

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            refreshPopover()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
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
