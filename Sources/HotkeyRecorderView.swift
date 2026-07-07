import AppKit
import Carbon

/// Compact key-capture widget for the Settings window's General section.
/// Click the button → it becomes first responder; the next modified key combo is
/// written to `Settings.shared.hotkeyKeyCode/hotkeyModifiers` and a
/// `.codeFMHotkeyConfigChanged` notification is posted.
final class HotkeyRecorderView: NSView {
    private let label = NSTextField(labelWithString: "Global Hotkey:")
    private let shortcutButton = NSButton()
    private var isRecording = false
    private let settings: Settings

    var isEnabled: Bool = true {
        didSet { shortcutButton.isEnabled = isEnabled }
    }

    init(settings: Settings) {
        self.settings = settings
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 30))

        label.font = .systemFont(ofSize: 13)
        addSubview(label)

        shortcutButton.bezelStyle = .roundRect
        shortcutButton.font = .systemFont(ofSize: 13)
        shortcutButton.target = self
        shortcutButton.action = #selector(shortcutButtonClicked)
        addSubview(shortcutButton)

        refreshTitle()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 360, height: 30) }

    override func layout() {
        super.layout()
        let labelWidth: CGFloat = 110
        label.frame = NSRect(x: 0, y: (bounds.height - 20) / 2, width: labelWidth, height: 20)
        let buttonX = labelWidth + 8
        shortcutButton.frame = NSRect(
            x: buttonX, y: (bounds.height - 26) / 2,
            width: max(0, bounds.width - buttonX), height: 26
        )
    }

    private func refreshTitle() {
        if isRecording {
            shortcutButton.title = "Type shortcut..."
        } else {
            let mods = settings.hotkeyModifiers
            let key = settings.hotkeyKeyCode
            shortcutButton.title = HotkeyManager.modifierFlagsDescription(for: mods)
                + HotkeyManager.keyCodeDescription(for: key)
        }
    }

    @objc private func shortcutButtonClicked() {
        isRecording = true
        refreshTitle()
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }

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

        settings.hotkeyKeyCode = keyCode
        settings.hotkeyModifiers = carbonMods

        isRecording = false
        refreshTitle()
        NotificationCenter.default.post(name: .codeFMHotkeyConfigChanged, object: nil)
    }
}

extension Notification.Name {
    static let codeFMHotkeyConfigChanged = Notification.Name("CodeFMHotkeyConfigChanged")
}
