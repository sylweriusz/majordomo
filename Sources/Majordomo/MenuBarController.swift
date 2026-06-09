import AppKit
import Carbon

enum ModelStatus {
    case ready
    case missing
    case downloading
    case error(String)

    var title: String {
        switch self {
        case .ready: L10n.text("common.ready")
        case .missing: L10n.text("common.missing")
        case .downloading: L10n.text("common.downloading")
        case .error(let message): L10n.text("common.error", message)
        }
    }

}

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private weak var appDelegate: AppDelegate?

    private let primaryDictationItem = NSMenuItem(title: L10n.text("menu.start_dictation", ""), action: #selector(toggleDictationAction), keyEquivalent: "")
    private let cancelDictationItem = NSMenuItem(title: L10n.text("menu.cancel_dictation"), action: #selector(cancelDictationAction), keyEquivalent: "")
    private let statusDetailItem = NSMenuItem(title: L10n.text("menu.status_row", L10n.text("common.ready")), action: nil, keyEquivalent: "")
    private let copyTranscriptItem = NSMenuItem(title: L10n.text("menu.copy_last_transcript"), action: #selector(copyLastTranscript), keyEquivalent: "")
    private let transcribeAudioFileItem = NSMenuItem(title: L10n.text("menu.transcribe_audio_file"), action: #selector(showAudioFileTranscriptionPanel), keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: L10n.text("menu.settings"), action: #selector(showSettings), keyEquivalent: ",")
    private let launchAtLoginItem = NSMenuItem(title: L10n.text("menu.launch_at_login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let aboutItem = NSMenuItem(title: L10n.text("menu.about"), action: #selector(showAboutPanel), keyEquivalent: "")

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        configureMenu()
        refreshLaunchAtLoginMenu()
    }

    func update(state: DictationState) {
        let hotkey = appDelegate?.hotkeyDisplayName ?? ""
        switch state {
        case .idle, .error:
            primaryDictationItem.title = L10n.text("menu.start_dictation", hotkey)
            primaryDictationItem.isEnabled = true
        case .recording:
            primaryDictationItem.title = L10n.text("menu.stop_dictation", hotkey)
            primaryDictationItem.isEnabled = true
        case .downloading:
            primaryDictationItem.title = L10n.text("menu.preparing_model")
            primaryDictationItem.isEnabled = false
        case .transcribing:
            primaryDictationItem.title = L10n.text("menu.transcribing_item")
            primaryDictationItem.isEnabled = false
        }
        cancelDictationItem.isEnabled = state.isDictationActive
        statusItem.button?.toolTip = state.menuTitle
        statusItem.button?.image = AppIcon.makeStatusBarImage(badge: Self.badgeColor(for: state))
    }

    private static func badgeColor(for state: DictationState) -> NSColor? {
        switch state {
        case .idle: nil
        case .recording: .systemRed
        case .downloading: .systemOrange
        case .transcribing: .systemBlue
        case .error: .systemYellow
        }
    }

    func updateStatusMessage(_ message: String?) {
        statusDetailItem.title = L10n.text("menu.status_row", message ?? L10n.text("common.ready"))
    }

    func updateLastTranscript(_ text: String?) {
        let hasTranscript = text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        copyTranscriptItem.isEnabled = hasTranscript
    }

    func refreshLaunchAtLoginMenu() {
        launchAtLoginItem.state = appDelegate?.isLaunchAtLoginEnabled() == true ? .on : .off
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = AppIcon.makeStatusBarImage()
        button.imagePosition = .imageOnly
        button.toolTip = "Majordomo"
    }

    private func configureMenu() {
        let menu = NSMenu()

        primaryDictationItem.target = self
        menu.addItem(primaryDictationItem)

        cancelDictationItem.target = self
        cancelDictationItem.isEnabled = false
        menu.addItem(cancelDictationItem)

        menu.addItem(.separator())

        statusDetailItem.isEnabled = false
        menu.addItem(statusDetailItem)

        copyTranscriptItem.target = self
        copyTranscriptItem.isEnabled = false
        menu.addItem(copyTranscriptItem)

        menu.addItem(.separator())

        transcribeAudioFileItem.target = self
        menu.addItem(transcribeAudioFileItem)

        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: L10n.text("menu.quit", "Majordomo"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleDictationAction() {
        appDelegate?.toggleDictation()
    }

    @objc private func cancelDictationAction() {
        appDelegate?.cancelDictationFromMenu()
    }

    @objc private func copyLastTranscript() {
        appDelegate?.copyLastTranscriptToClipboard()
    }

    @objc private func showAudioFileTranscriptionPanel() {
        appDelegate?.showAudioFileTranscriptionPanel()
    }

    @objc private func showSettings() {
        appDelegate?.showSettings()
    }

    @objc private func showAboutPanel() {
        appDelegate?.showAboutPanel()
    }

    @objc private func toggleLaunchAtLogin() {
        appDelegate?.toggleLaunchAtLogin()
        refreshLaunchAtLoginMenu()
    }

    @objc private func quit() {
        appDelegate?.quit()
    }
}

struct TranscriptionLanguageOption: CaseIterable {
    let code: String
    let displayName: String

    static let allCases: [TranscriptionLanguageOption] = [
        TranscriptionLanguageOption(code: "auto", displayName: "🌐 Auto"),
        TranscriptionLanguageOption(code: "en", displayName: "🇬🇧 English"),
        TranscriptionLanguageOption(code: "pl", displayName: "🇵🇱 Polski"),
        TranscriptionLanguageOption(code: "de", displayName: "🇩🇪 Deutsch"),
        TranscriptionLanguageOption(code: "fr", displayName: "🇫🇷 Français"),
        TranscriptionLanguageOption(code: "es", displayName: "🇪🇸 Español"),
        TranscriptionLanguageOption(code: "it", displayName: "🇮🇹 Italiano"),
        TranscriptionLanguageOption(code: "pt", displayName: "🇵🇹 Português"),
        TranscriptionLanguageOption(code: "nl", displayName: "🇳🇱 Nederlands"),
        TranscriptionLanguageOption(code: "uk", displayName: "🇺🇦 Українська"),
        TranscriptionLanguageOption(code: "ru", displayName: "🗣️ Русский"),
        TranscriptionLanguageOption(code: "cs", displayName: "🇨🇿 Čeština"),
        TranscriptionLanguageOption(code: "sk", displayName: "🇸🇰 Slovenčina"),
        TranscriptionLanguageOption(code: "sl", displayName: "🇸🇮 Slovenščina"),
        TranscriptionLanguageOption(code: "hr", displayName: "🇭🇷 Hrvatski"),
        TranscriptionLanguageOption(code: "sr", displayName: "🇷🇸 Српски"),
        TranscriptionLanguageOption(code: "bg", displayName: "🇧🇬 Български"),
        TranscriptionLanguageOption(code: "ro", displayName: "🇷🇴 Română"),
        TranscriptionLanguageOption(code: "hu", displayName: "🇭🇺 Magyar"),
        TranscriptionLanguageOption(code: "el", displayName: "🇬🇷 Ελληνικά"),
        TranscriptionLanguageOption(code: "tr", displayName: "🇹🇷 Türkçe"),
        TranscriptionLanguageOption(code: "da", displayName: "🇩🇰 Dansk"),
        TranscriptionLanguageOption(code: "sv", displayName: "🇸🇪 Svenska"),
        TranscriptionLanguageOption(code: "no", displayName: "🇳🇴 Norsk"),
        TranscriptionLanguageOption(code: "fi", displayName: "🇫🇮 Suomi"),
        TranscriptionLanguageOption(code: "et", displayName: "🇪🇪 Eesti"),
        TranscriptionLanguageOption(code: "lv", displayName: "🇱🇻 Latviešu"),
        TranscriptionLanguageOption(code: "lt", displayName: "🇱🇹 Lietuvių"),
        TranscriptionLanguageOption(code: "ca", displayName: "🏴 Català"),
        TranscriptionLanguageOption(code: "eu", displayName: "🏴 Euskara"),
        TranscriptionLanguageOption(code: "gl", displayName: "🏴 Galego"),
        TranscriptionLanguageOption(code: "ga", displayName: "🇮🇪 Gaeilge"),
        TranscriptionLanguageOption(code: "cy", displayName: "🏴 Cymraeg"),
        TranscriptionLanguageOption(code: "ar", displayName: "🇸🇦 العربية"),
        TranscriptionLanguageOption(code: "he", displayName: "🇮🇱 עברית"),
        TranscriptionLanguageOption(code: "hi", displayName: "🇮🇳 हिन्दी"),
        TranscriptionLanguageOption(code: "zh", displayName: "🇨🇳 中文"),
        TranscriptionLanguageOption(code: "ja", displayName: "🇯🇵 日本語"),
        TranscriptionLanguageOption(code: "ko", displayName: "🇰🇷 한국어"),
        TranscriptionLanguageOption(code: "vi", displayName: "🇻🇳 Tiếng Việt"),
        TranscriptionLanguageOption(code: "id", displayName: "🇮🇩 Bahasa Indonesia")
    ]

    static func displayName(for code: String) -> String {
        allCases.first { $0.code == code }?.displayName ?? code
    }
}

struct HotkeyPreset {
    let label: String
    let keyCode: UInt32
    let modifiers: UInt32

    static let all: [HotkeyPreset] = [
        HotkeyPreset(label: "⌥ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)),
        HotkeyPreset(label: "Fn", keyCode: UInt32(kVK_Function), modifiers: 0),
        HotkeyPreset(label: "F5", keyCode: UInt32(kVK_F5), modifiers: 0),
        HotkeyPreset(label: "F6", keyCode: UInt32(kVK_F6), modifiers: 0),
        HotkeyPreset(label: "F7", keyCode: UInt32(kVK_F7), modifiers: 0),
        HotkeyPreset(label: "F8", keyCode: UInt32(kVK_F8), modifiers: 0),
        HotkeyPreset(label: "⌃ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey)),
        HotkeyPreset(label: "⌃⌥ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)),
        HotkeyPreset(label: "⇧⌘K", keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(shiftKey | cmdKey)),
    ]
}
