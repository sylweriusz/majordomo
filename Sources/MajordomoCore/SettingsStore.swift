import Foundation

/// App-wide constants that aren't user-configurable.
public enum AppInfo {
    /// Fallback bundle identifier used when `Bundle.main.bundleIdentifier` is
    /// unavailable (e.g. test hosts). Matches the stable channel.
    public static let fallbackBundleIdentifier = "pl.wild-matrix.majordomo"
}

/// Single registry of every `UserDefaults` key the app persists.
///
/// Previously these string literals were scattered across six files with three
/// different persistence idioms. Centralizing them here removes typo risk and
/// gives one place to audit what the app stores. The string values must never
/// change — they are the on-disk contract with existing installs.
public enum DefaultsKey {
    public static let dictationLanguage = "dictationLanguage"
    public static let transcriptionBackend = "transcriptionBackend"
    /// Legacy key for the selected model profile, superseded by
    /// ``transcriptionBackend``. Read once during migration, then cleared.
    public static let legacyWhisperModelProfile = "whisperModelProfile"
    public static let indicatorEnabled = "indicatorEnabled"
    public static let indicatorVisualStyle = "indicatorVisualStyle"
    public static let indicatorPlacement = "indicatorPlacement"
    public static let indicatorColorPalette = "indicatorColorPalette"
    public static let dictationSoundProfile = "dictationSoundProfile"
    public static let appUILanguage = "appUILanguage"
    public static let hotkeyKeyCode = "hotkeyKeyCode"
    public static let hotkeyModifiers = "hotkeyModifiers"
}

/// Typed, dependency-injectable wrapper over `UserDefaults` for the settings the
/// app delegate owns directly. Injecting the `UserDefaults` instance makes the
/// persistence logic (notably the legacy-key migration) unit-testable without
/// AppKit or the app's real defaults domain.
public final class SettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: Dictation language

    /// Spoken-language code for transcription. `"auto"` when unset.
    public var dictationLanguage: String {
        get { defaults.string(forKey: DefaultsKey.dictationLanguage) ?? "auto" }
        set { defaults.set(newValue, forKey: DefaultsKey.dictationLanguage) }
    }

    // MARK: Indicator

    /// Whether the on-screen waveform indicator is shown. Defaults to `true`.
    public var indicatorEnabled: Bool {
        get { defaults.object(forKey: DefaultsKey.indicatorEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: DefaultsKey.indicatorEnabled) }
    }

    // MARK: Transcription backend

    /// Raw value of the selected transcription backend, or `nil` if unset.
    ///
    /// Reads/writes only the current key. Run ``migrateLegacyBackendKeyIfNeeded()``
    /// once at launch to carry forward the old `whisperModelProfile` value.
    public var transcriptionBackendRawValue: String? {
        get { defaults.string(forKey: DefaultsKey.transcriptionBackend) }
        set { defaults.set(newValue, forKey: DefaultsKey.transcriptionBackend) }
    }

    /// One-time migration. If the current key is unset but the legacy
    /// `whisperModelProfile` key holds a value, copy it across and clear the
    /// legacy key. Idempotent: a no-op once the current key exists. This
    /// replaces the previous permanent dual-write of both keys on every change.
    public func migrateLegacyBackendKeyIfNeeded() {
        guard defaults.string(forKey: DefaultsKey.transcriptionBackend) == nil,
              let legacy = defaults.string(forKey: DefaultsKey.legacyWhisperModelProfile) else {
            return
        }
        defaults.set(legacy, forKey: DefaultsKey.transcriptionBackend)
        defaults.removeObject(forKey: DefaultsKey.legacyWhisperModelProfile)
    }
}
