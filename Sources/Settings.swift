import Foundation
import Carbon

final class Settings {
    static let shared = Settings()
    private static let defaultVolume: Float = 1.0
    private static let defaultHotkeyKeyCode: UInt32 = 35
    private static let defaultHotkeyModifiers = UInt32(cmdKey | shiftKey)
    private static let allowedHotkeyModifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    // Distinct from the app's bundle id (com.johncioni.codefm). macOS rejects a
    // suite whose name equals the bundle id ("does not make sense and will not
    // work"), causing UserDefaults(suiteName:) to return nil and silently fall
    // back to .standard.
    static let suiteName = "com.johncioni.codefm.preferences"
    private let defaults: UserDefaults = {
        UserDefaults(suiteName: Settings.suiteName) ?? .standard
    }()

    private enum Keys {
        static let volume = "volume"
        static let playAtStart = "playAtStart"
        static let globalHotkeyEnabled = "globalHotkeyEnabled"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let defaultStreamId = "defaultStreamId"      // nil = use catalog default; "random" = random
        static let lastNonRandomStreamId = "lastNonRandomStreamId"
    }

    func registerDefaults() {
        defaults.register(defaults: [
            Keys.volume: Self.defaultVolume,
            Keys.playAtStart: false,
            Keys.globalHotkeyEnabled: false,
            Keys.hotkeyKeyCode: Int(Self.defaultHotkeyKeyCode),
            Keys.hotkeyModifiers: Int(Self.defaultHotkeyModifiers),
            // defaultStreamId intentionally absent; missing = "use catalog's defaultStreamId"
        ])
    }

    var defaultStreamId: String? {
        get { defaults.string(forKey: Keys.defaultStreamId) }
        set {
            if let newValue { defaults.set(newValue, forKey: Keys.defaultStreamId) }
            else { defaults.removeObject(forKey: Keys.defaultStreamId) }
        }
    }

    /// Remembers the user's last specific (non-random) default so toggling
    /// "Play a random stream on launch" off can restore it. Spec §8.2.
    var lastNonRandomStreamId: String? {
        get { defaults.string(forKey: Keys.lastNonRandomStreamId) }
        set {
            if let newValue { defaults.set(newValue, forKey: Keys.lastNonRandomStreamId) }
            else { defaults.removeObject(forKey: Keys.lastNonRandomStreamId) }
        }
    }

    var volume: Float {
        get { Self.clampedVolume(defaults.float(forKey: Keys.volume)) }
        set { defaults.set(Self.clampedVolume(newValue), forKey: Keys.volume) }
    }

    var playAtStart: Bool {
        get { defaults.bool(forKey: Keys.playAtStart) }
        set { defaults.set(newValue, forKey: Keys.playAtStart) }
    }

    var globalHotkeyEnabled: Bool {
        get { defaults.bool(forKey: Keys.globalHotkeyEnabled) }
        set { defaults.set(newValue, forKey: Keys.globalHotkeyEnabled) }
    }

    var hotkeyKeyCode: UInt32 {
        get { uint32Value(forKey: Keys.hotkeyKeyCode, fallback: Self.defaultHotkeyKeyCode) }
        set { defaults.set(Int(newValue), forKey: Keys.hotkeyKeyCode) }
    }

    var hotkeyModifiers: UInt32 {
        get {
            let modifiers = uint32Value(forKey: Keys.hotkeyModifiers, fallback: Self.defaultHotkeyModifiers)
                & Self.allowedHotkeyModifiers
            return modifiers == 0 ? Self.defaultHotkeyModifiers : modifiers
        }
        set { defaults.set(Int(newValue & Self.allowedHotkeyModifiers), forKey: Keys.hotkeyModifiers) }
    }

    static func clampedVolume(_ value: Float) -> Float {
        guard value.isFinite else { return defaultVolume }
        return min(max(value, 0.0), 1.0)
    }

    private func uint32Value(forKey key: String, fallback: UInt32) -> UInt32 {
        let value = defaults.integer(forKey: key)
        guard value >= 0, value <= Int(UInt16.max) else { return fallback }
        return UInt32(value)
    }
}
