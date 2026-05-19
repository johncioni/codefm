import AppKit
import Carbon

final class HotkeyRecorderWindow: NSWindow, NSWindowDelegate {
    private let shortcutButton = NSButton()
    private let enableCheckbox = NSButton(checkboxWithTitle: "Enable global hotkey", target: nil, action: nil)
    private var isRecording = false
    var onSettingsChanged: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 110),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "Global hotkey"
        isReleasedWhenClosed = false
        delegate = self
        center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 110))

        // Row 1: "Global Hotkey:" label + Record Shortcut button
        let label = NSTextField(labelWithString: "Global Hotkey:")
        label.font = .systemFont(ofSize: 13)
        label.frame = NSRect(x: 20, y: 60, width: 110, height: 20)
        content.addSubview(label)

        shortcutButton.bezelStyle = .roundRect
        shortcutButton.font = .systemFont(ofSize: 13)
        shortcutButton.target = self
        shortcutButton.action = #selector(shortcutButtonClicked)
        shortcutButton.frame = NSRect(x: 135, y: 55, width: 220, height: 30)
        updateShortcutButtonTitle()
        content.addSubview(shortcutButton)

        // Row 2: Enable checkbox
        enableCheckbox.target = self
        enableCheckbox.action = #selector(enableToggled)
        enableCheckbox.state = Settings.shared.globalHotkeyEnabled ? .on : .off
        enableCheckbox.font = .systemFont(ofSize: 13)
        enableCheckbox.frame = NSRect(x: 20, y: 18, width: 250, height: 20)
        content.addSubview(enableCheckbox)

        self.contentView = content
    }

    private func updateShortcutButtonTitle() {
        if isRecording {
            shortcutButton.title = "Type shortcut..."
        } else {
            let mods = Settings.shared.hotkeyModifiers
            let key = Settings.shared.hotkeyKeyCode
            let desc = HotkeyManager.modifierFlagsDescription(for: mods) + HotkeyManager.keyCodeDescription(for: key)
            shortcutButton.title = desc
        }
    }

    @objc private func shortcutButtonClicked() {
        isRecording = true
        updateShortcutButtonTitle()
        makeFirstResponder(self)
    }

    @objc private func enableToggled() {
        Settings.shared.globalHotkeyEnabled = (enableCheckbox.state == .on)
        onSettingsChanged?()
        // Hotkey registration can fail (collision with an OS-reserved shortcut),
        // in which case the controller flips the setting back off — reflect that
        // in the checkbox so the UI doesn't lie about the actual state.
        enableCheckbox.state = Settings.shared.globalHotkeyEnabled ? .on : .off
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !modifiers.intersection([.command, .option, .control, .shift]).isEmpty else {
            NSSound.beep()
            return
        }

        let carbonMods = HotkeyManager.carbonModifiers(from: modifiers)
        let keyCode = UInt32(event.keyCode)

        Settings.shared.hotkeyKeyCode = keyCode
        Settings.shared.hotkeyModifiers = carbonMods

        isRecording = false
        updateShortcutButtonTitle()
        onSettingsChanged?()
        // The controller may have flipped `globalHotkeyEnabled` off if the new
        // shortcut collided with an OS-reserved hotkey; mirror that into the
        // checkbox so it doesn't claim "enabled" while no hotkey is registered.
        enableCheckbox.state = Settings.shared.globalHotkeyEnabled ? .on : .off
    }

    func windowWillClose(_ notification: Notification) {
        isRecording = false
    }
}
