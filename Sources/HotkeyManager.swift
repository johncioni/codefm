import AppKit
import Carbon

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onTrigger: (() -> Void)?

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        unregister()
        onTrigger = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onTrigger?()
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &handlerRef
        )
        guard handlerStatus == noErr else {
            onTrigger = nil
            return false
        }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("CDFM"), id: 1)

        let hotkeyStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        guard hotkeyStatus == noErr else {
            unregister()
            return false
        }

        return true
    }

    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
        onTrigger = nil
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    static func modifierFlagsDescription(for carbonMods: UInt32) -> String {
        var parts: [String] = []
        if carbonMods & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonMods & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonMods & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbonMods & UInt32(cmdKey) != 0 { parts.append("⌘") }
        return parts.joined()
    }

    private static let keyCodeMap: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K",
        41: ";", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    static func keyCodeDescription(for keyCode: UInt32) -> String {
        keyCodeMap[keyCode] ?? "Key\(keyCode)"
    }
}

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for char in string.utf8.prefix(4) {
        result = (result << 8) | OSType(char)
    }
    return result
}
