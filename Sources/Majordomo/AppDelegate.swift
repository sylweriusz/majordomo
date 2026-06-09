import AppKit
import Carbon
import MajordomoCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, DictationCoordinatorHost {
    private let settings = SettingsStore(defaults: .standard)
    private var menuBarController: MenuBarController?
    private let overlayController = DictationOverlayWindowController()
    private var settingsWindowController: SettingsWindowController?
    private lazy var hotkeySettingsWindowController: HotkeySettingsWindowController = {
        let controller = HotkeySettingsWindowController()
        controller.onCaptureCompleted = { [weak self] keyCode, modifiers in
            self?.applyHotkeyChange(keyCode: keyCode, modifiers: modifiers)
        }
        return controller
    }()
    private let audioRecorder = AudioRecorder()
    private let modelManagers = Dictionary(
        uniqueKeysWithValues: TranscriptionBackendKind.allCases.map { ($0, ModelManager(kind: $0)) }
    )
    private let runtimeDependencyManager = RuntimeDependencyManager()
    private lazy var audioFileTranscriber = AudioFileTranscriber()
    private let textInsertionService = TextInsertionService()
    private let launchAtLoginManager = LaunchAtLoginManager()
    private var hotkeyController: HotkeyController?
    private lazy var escapeCancelMonitor = DoubleEscapeCancelMonitor { [weak self] in
        self?.dictationCoordinator.cancel()
    }
    private lazy var dictationCoordinator = DictationCoordinator(
        audioRecorder: audioRecorder,
        overlay: overlayController,
        textInsertion: textInsertionService,
        host: self
    )
    private var modelDownloadTasks: [TranscriptionBackendKind: Task<URL, Error>] = [:]
    private lazy var audioFileTranscriptionWindowController = AudioFileTranscriptionWindowController(
        initialBackend: currentBackendKind,
        initialLanguage: currentLanguage,
        transcribeHandler: { [weak self] (audioURL: URL, backend: TranscriptionBackendKind, language: String) in
            guard let self else { throw CancellationError() }
            return try await self.transcribeAudioFile(audioURL, backend: backend, language: language)
        },
        modelSelectionHandler: { [weak self] backend in
            self?.selectAudioFileBackend(backend)
        }
    )
    private lazy var aboutWindowController = AboutWindowController()
    private lazy var onboardingWindowController: OnboardingWindowController = {
        let controller = OnboardingWindowController()
        controller.onFinish = { [weak self] in
            guard let self else { return }
            self.startModelDownloadIfNeeded(for: self.currentBackendKind)
        }
        controller.onUseRecommendedHotkey = { [weak self] in
            self?.applyRecommendedHotkey()
        }
        return controller
    }()

    private var currentHotkeyIsBareFn: Bool {
        currentHotkeyKeyCode == UInt32(kVK_Function) && currentHotkeyModifiers == 0
    }

    private func applyRecommendedHotkey() {
        applyHotkeyChange(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    }

    var shouldPreserveRecordedAudio: Bool {
        // Raw-audio preservation writes WAVs of the user's voice to Application
        // Support and never auto-deletes them — a debugging aid only. The
        // `MAJORDOMO_PRESERVE_RECORDINGS` env var is honored in DEBUG builds
        // only, so a stray env var on a shipped release can never silently
        // accumulate recordings. The QA-only `.test` channel still preserves.
        #if DEBUG
        if ProcessInfo.processInfo.environment["MAJORDOMO_PRESERVE_RECORDINGS"] == "1" {
            return true
        }
        #endif
        return Bundle.main.bundleIdentifier?.hasSuffix(".test") == true
    }

    var currentHotkeyKeyCode: UInt32 { hotkeyController?.currentKeyCode ?? 0 }
    var currentHotkeyModifiers: UInt32 { hotkeyController?.currentModifiers ?? 0 }
    var hotkeyDisplayName: String {
        guard let hc = hotkeyController else { return "⌥ Space" }
        return hc.hotkeyDisplayName(keyCode: hc.currentKeyCode, modifiers: hc.currentModifiers)
    }

    private var modelStatuses: [TranscriptionBackendKind: ModelStatus] = Dictionary(
        uniqueKeysWithValues: TranscriptionBackendKind.allCases.map { ($0, .missing) }
    ) {
        didSet {
            refreshSettingsWindowIfLoaded()
        }
    }
    private var runtimeDependencyStatuses: [RuntimeDependencyKind: RuntimeDependencyStatus] = [
        .whisperCLI: .missing,
        .whisperDictate: .missing
    ] {
        didSet {
            refreshSettingsWindowIfLoaded()
        }
    }
    var lastTranscript: String? {
        didSet {
            menuBarController?.updateLastTranscript(lastTranscript)
        }
    }
    private var lastStatusMessage: String? {
        didSet {
            menuBarController?.updateStatusMessage(lastStatusMessage)
        }
    }
    var currentLanguage: String {
        get { settings.dictationLanguage }
        set {
            settings.dictationLanguage = newValue
            if audioFileTranscriptionWindowController.window?.isVisible == true {
                audioFileTranscriptionWindowController.updateSelectedLanguage(newValue)
            }
            refreshSettingsWindowIfLoaded()
        }
    }
    var currentAppLanguagePreference: AppUILanguage {
        AppUILanguage.selectedPreference
    }
    var currentBackendKind: TranscriptionBackendKind {
        get {
            let raw = settings.transcriptionBackendRawValue ?? TranscriptionBackendKind.largeV3TurboQ8.rawValue
            return TranscriptionBackendKind(rawValue: raw) ?? .largeV3TurboQ8
        }
        set {
            settings.transcriptionBackendRawValue = newValue.rawValue
            if audioFileTranscriptionWindowController.window?.isVisible == true {
                audioFileTranscriptionWindowController.updateSelectedBackend(newValue)
            }
            refreshSettingsWindowIfLoaded()
        }
    }
    var isIndicatorEnabled: Bool {
        get { settings.indicatorEnabled }
        set {
            settings.indicatorEnabled = newValue
            if !newValue {
                overlayController.hide()
            }
            refreshSettingsWindowIfLoaded()
        }
    }
    var currentIndicatorVisualStyle: IndicatorVisualStyle {
        get { IndicatorVisualStyle.load() }
        set {
            newValue.save()
            overlayController.visualStyle = newValue
            refreshSettingsWindowIfLoaded()
        }
    }
    var currentIndicatorColorPalette: IndicatorColorPalette {
        get { IndicatorColorPalette.load() }
        set {
            newValue.save()
            overlayController.colorPalette = newValue
            refreshSettingsWindowIfLoaded()
        }
    }
    var currentIndicatorPlacement: IndicatorPlacement {
        get { IndicatorPlacement.load() }
        set {
            newValue.save()
            overlayController.placement = newValue
            refreshSettingsWindowIfLoaded()
        }
    }
    var currentSoundProfile: DictationSoundProfile {
        get { DictationSoundProfile.load() }
        set {
            newValue.save()
            refreshSettingsWindowIfLoaded()
        }
    }
    private var state: DictationState = .idle {
        didSet {
            menuBarController?.update(state: state)
            updateEscapeCancelMonitor(for: state)
        }
    }

    // MARK: - DictationCoordinatorHost

    var dictationState: DictationState {
        get { state }
        set { state = newValue }
    }

    func isLiveDictationReady() -> Bool {
        runtimeStatus(for: .whisperDictate).isReady
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.migrateLegacyBackendKeyIfNeeded()
        loadSavedHotkey()
        overlayController.visualStyle = currentIndicatorVisualStyle
        overlayController.colorPalette = currentIndicatorColorPalette
        overlayController.placement = currentIndicatorPlacement
        refreshRuntimeDependencyStatuses()
        refreshModelStatuses()
        menuBarController = MenuBarController(appDelegate: self)
        lastTranscript = nil
        lastStatusMessage = nil
        menuBarController?.update(state: state)
        updateRuntimeStatusMessage()
        registerDefaultHotkey()
        showOnboardingIfNeeded()
    }

    private func showOnboardingIfNeeded() {
        guard !OnboardingWindowController.hasCompleted else { return }
        showOnboarding()
    }

    func showOnboarding() {
        onboardingWindowController.hotkeyDisplayName = hotkeyDisplayName
        onboardingWindowController.isCurrentHotkeyBareFn = currentHotkeyIsBareFn
        onboardingWindowController.showWindow(self)
    }

    func presentAccessibilityNeededAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("alert.accessibility_title")
        alert.informativeText = L10n.text("alert.accessibility_message")
        alert.addButton(withTitle: L10n.text("onboarding.open_settings"))
        alert.addButton(withTitle: L10n.text("settings.relaunch_later"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func toggleDictation() {
        dictationCoordinator.toggle()
    }

    func showSettings() {
        let controller = settingsWindowController ?? SettingsWindowController(appDelegate: self)
        settingsWindowController = controller
        controller.reloadLocalizedText()
        controller.refreshFromAppState()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showHotkeySettings() {
        hotkeySettingsWindowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showAudioFileTranscriptionPanel() {
        audioFileTranscriptionWindowController.reloadLocalizedText()
        audioFileTranscriptionWindowController.updateSelectedBackend(currentBackendKind)
        audioFileTranscriptionWindowController.updateSelectedLanguage(currentLanguage)
        audioFileTranscriptionWindowController.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showAboutPanel() {
        aboutWindowController.reloadLocalizedText()
        aboutWindowController.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applyAppLanguagePreference(_ language: AppUILanguage) {
        AppUILanguage.persistPreference(language)
    }

    func promptForAppLanguageRelaunch() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("settings.app_language_relaunch_title")
        alert.informativeText = L10n.text("settings.app_language_relaunch_message")
        alert.addButton(withTitle: L10n.text("settings.relaunch_now"))
        alert.addButton(withTitle: L10n.text("settings.relaunch_later"))

        if alert.runModal() == .alertFirstButtonReturn {
            relaunchApplication()
        }
    }

    func applyHotkeyChange(keyCode: UInt32, modifiers: UInt32) {
        guard let hotkeyController else { return }
        do {
            try hotkeyController.registerHotkey(keyCode: keyCode, modifiers: modifiers)
            let displayName = hotkeyController.hotkeyDisplayName(keyCode: keyCode, modifiers: modifiers)
            setStatusMessage(L10n.text("status.hotkey_changed", displayName))
            menuBarController?.update(state: state)
            refreshSettingsWindowIfLoaded()
            AppLog.info("hotkey changed to \(displayName)")
        } catch {
            setStatusMessage(L10n.text("status.hotkey_change_failed", error.localizedDescription))
            AppLog.error("hotkey change failed: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    func selectBackend(_ backend: TranscriptionBackendKind) {
        guard canSelectBackend(backend) else {
            setStatusMessage(L10n.text("status.helpers_missing"))
            NSSound.beep()
            return
        }
        currentBackendKind = backend
        setStatusMessage(L10n.text("status.model_selected", backend.shortDisplayName))
        AppLog.info("Whisper model changed to \(backend.displayName)")
        startModelDownloadIfNeeded(for: backend)
    }

    func selectAudioFileBackend(_ backend: TranscriptionBackendKind) {
        startModelDownloadIfNeeded(for: backend)
    }

    func toggleIndicatorEnabled() {
        isIndicatorEnabled.toggle()
        AppLog.info("indicator \(isIndicatorEnabled ? "enabled" : "disabled")")
    }

    func selectIndicatorVisualStyle(_ style: IndicatorVisualStyle) {
        currentIndicatorVisualStyle = style
        AppLog.info("indicator visual style changed to \(style.displayName)")
    }

    func selectIndicatorColorPalette(_ palette: IndicatorColorPalette) {
        currentIndicatorColorPalette = palette
        AppLog.info("indicator color palette changed to \(palette.displayName)")
    }

    func selectIndicatorPlacement(_ placement: IndicatorPlacement) {
        currentIndicatorPlacement = placement
        AppLog.info("indicator placement changed to \(placement.displayName)")
    }

    func selectSoundProfile(_ profile: DictationSoundProfile) {
        currentSoundProfile = profile
        AppLog.info("dictation sound profile changed to \(profile.displayName)")
    }

    func modelStatus(for backend: TranscriptionBackendKind) -> ModelStatus {
        modelStatuses[backend] ?? .missing
    }

    func runtimeStatus(for dependency: RuntimeDependencyKind) -> RuntimeDependencyStatus {
        runtimeDependencyStatuses[dependency] ?? .missing
    }

    func canSelectBackend(_ backend: TranscriptionBackendKind) -> Bool {
        // Backend is selectable when at least whisper-cli is ready (file transcription).
        // Live dictation requires whisper-dictate separately, checked in DictationCoordinator.
        runtimeStatus(for: .whisperCLI).isReady
    }

    func canLiveDictate() -> Bool {
        runtimeStatus(for: .whisperDictate).isReady
    }

    func copyLastTranscriptToClipboard() {
        guard let transcript = lastTranscript?.trimmingCharacters(in: .whitespacesAndNewlines),
              !transcript.isEmpty else {
            setStatusMessage(L10n.text("status.no_transcript_to_copy"))
            NSSound.beep()
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        setStatusMessage(L10n.text("status.transcript_copied"))
        AppLog.info("copied last transcript to clipboard")
    }

    func isLaunchAtLoginEnabled() -> Bool {
        launchAtLoginManager.isEnabled
    }

    func toggleLaunchAtLogin() {
        let shouldEnable = !launchAtLoginManager.isEnabled

        do {
            try launchAtLoginManager.setEnabled(shouldEnable)
            setStatusMessage(shouldEnable ? L10n.text("status.launch_enabled") : L10n.text("status.launch_disabled"))
            menuBarController?.refreshLaunchAtLoginMenu()
            AppLog.info("launch at login \(shouldEnable ? "enabled" : "disabled")")
        } catch {
            setStatusMessage(L10n.text("status.launch_failed", error.localizedDescription))
            AppLog.error("launch at login change failed: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func relaunchApplication() {
        let bundleURL = Bundle.main.bundleURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [bundleURL.path]

        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            setStatusMessage(error.localizedDescription)
            NSSound.beep()
        }
    }

    private func refreshSettingsWindowIfLoaded() {
        settingsWindowController?.refreshFromAppState()
    }

    private func updateRuntimeStatusMessage() {
        if canLiveDictate() {
            setStatusMessage(L10n.text("status.runtime_ready"))
        } else if runtimeStatus(for: .whisperCLI).isReady {
            setStatusMessage(L10n.text("status.runtime_file_only"))
        } else {
            setStatusMessage(L10n.text("status.runtime_missing"))
        }
    }

    private func refreshRuntimeDependencyStatuses() {
        runtimeDependencyStatuses = [
            .whisperCLI: runtimeDependencyManager.status(for: .whisperCLI),
            .whisperDictate: runtimeDependencyManager.status(for: .whisperDictate)
        ]
    }

    private func refreshModelStatuses() {
        modelStatuses = Dictionary(
            uniqueKeysWithValues: TranscriptionBackendKind.allCases.map { profile in
                (profile, modelManager(for: profile).hasModel() ? .ready : .missing)
            }
        )
    }

    func modelManager(for backend: TranscriptionBackendKind) -> ModelManager {
        modelManagers[backend] ?? ModelManager(kind: backend)
    }

    private var lastReportedDownloadPercent = -1

    private func reportDownloadProgress(backend: TranscriptionBackendKind, fraction: Double) {
        let percent = Int((fraction * 100).rounded())
        guard percent != lastReportedDownloadPercent else { return }
        lastReportedDownloadPercent = percent
        setStatusMessage(L10n.text("status.model_downloading", backend.shortDisplayName, percent))
    }



    private func startModelDownloadIfNeeded(for backend: TranscriptionBackendKind) {
        guard !modelManager(for: backend).hasModel() else {
            modelStatuses[backend] = .ready
            return
        }

        Task { @MainActor in
            do {
                let url = try await ensureModelAvailable(for: backend)
                setStatusMessage(L10n.text("status.model_ready", backend.shortDisplayName))
                AppLog.info("\(backend.displayName) model ready: \(url.path)")
            } catch where Self.isCancellation(error) {
                // ensureModelAvailable already reported the cancel; stay quiet.
            } catch {
                setStatusMessage(L10n.text("status.model_download_failed", error.localizedDescription))
                AppLog.error("\(backend.displayName) model download failed: \(error.localizedDescription)")
                NSSound.beep()
            }
        }
    }

    func ensureModelAvailable(for backend: TranscriptionBackendKind) async throws -> URL {
        let manager = modelManager(for: backend)
        if manager.hasModel() {
            modelStatuses[backend] = .ready
            return manager.modelURL
        }

        if let existingTask = modelDownloadTasks[backend] {
            state = .downloading
            do {
                let url = try await existingTask.value
                modelStatuses[backend] = .ready
                if state == .downloading {
                    state = .idle
                }
                return url
            } catch {
                modelStatuses[backend] = .error(error.localizedDescription)
                if state == .downloading {
                    state = .error
                }
                throw error
            }
        }

        modelStatuses[backend] = .downloading
        state = .downloading
        lastReportedDownloadPercent = -1

        // Bridge the background download's progress to the MainActor via an
        // AsyncStream (the progress closure is @Sendable and can't capture self).
        let (progressStream, progressContinuation) = AsyncStream<Double>.makeStream()
        let progressConsumer = Task { @MainActor in
            for await fraction in progressStream {
                self.reportDownloadProgress(backend: backend, fraction: fraction)
            }
        }
        let task = Task.detached(priority: .utility) {
            defer { progressContinuation.finish() }
            return try await manager.downloadModelIfMissing(onProgress: { progressContinuation.yield($0) })
        }
        modelDownloadTasks[backend] = task
        defer {
            modelDownloadTasks[backend] = nil
            progressConsumer.cancel()
        }

        do {
            let url = try await task.value
            modelStatuses[backend] = .ready
            if state == .downloading {
                state = .idle
            }
            return url
        } catch where Self.isCancellation(error) {
            // User-initiated cancel: return to a clean idle/missing state, not error.
            modelStatuses[backend] = .missing
            if state == .downloading {
                state = .idle
            }
            setStatusMessage(L10n.text("status.download_canceled"))
            AppLog.info("model download canceled for \(backend.rawValue)")
            throw error
        } catch {
            modelStatuses[backend] = .error(error.localizedDescription)
            if state == .downloading {
                state = .error
            }
            throw error
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    func cancelModelDownload(for backend: TranscriptionBackendKind) {
        modelDownloadTasks[backend]?.cancel()
    }

    func deleteModel(for backend: TranscriptionBackendKind) {
        do {
            try modelManager(for: backend).deleteModel()
            modelStatuses[backend] = .missing
            setStatusMessage(L10n.text("status.model_deleted", backend.shortDisplayName))
            AppLog.info("deleted model \(backend.rawValue)")
        } catch {
            setStatusMessage(L10n.text("status.model_delete_failed", error.localizedDescription))
            AppLog.error("failed to delete model \(backend.rawValue): \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    private func transcribeAudioFile(_ audioURL: URL, backend: TranscriptionBackendKind, language: String) async throws -> TranscriptionResult {
        guard runtimeStatus(for: .whisperCLI).isReady else {
            throw RuntimeDependencyError.bundledHelperMissing(.whisperCLI)
        }
        _ = try await ensureModelAvailable(for: backend)
        state = .transcribing
        defer {
            if state == .transcribing {
                state = .idle
            }
        }
        let result = try await audioFileTranscriber.transcribe(audioURL: audioURL, backend: backend, language: language)
        lastTranscript = result.text
        // Deliberately omits the source filename — it's user data, not needed for diagnostics.
        AppLog.info("audio file transcribed with \(backend.displayName) (\(String(format: "%.2f", result.duration))s)")
        return result
    }

    private func loadSavedHotkey() {
        hotkeyController = HotkeyController { [weak self] in
            self?.toggleDictation()
        }
    }

    private func registerDefaultHotkey() {
        guard let controller = hotkeyController else { return }

        do {
            try controller.registerDefaultHotkey()
            AppLog.info("hotkey registered: \(controller.hotkeyDisplayName(keyCode: controller.currentKeyCode, modifiers: controller.currentModifiers))")
        } catch {
            state = .error
            setStatusMessage(L10n.text("status.hotkey_registration_failed", error.localizedDescription))
            AppLog.error("hotkey registration failed: \(error.localizedDescription)")
        }
    }

    /// Menu-facing cancel. Same effect as the double-Escape gesture; no-op when
    /// no dictation is active (the menu item is disabled in that case anyway).
    func cancelDictationFromMenu() {
        dictationCoordinator.cancel()
    }

    func setStatusMessage(_ message: String?) {
        lastStatusMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateEscapeCancelMonitor(for state: DictationState) {
        if state.isDictationActive {
            escapeCancelMonitor.start()
        } else {
            escapeCancelMonitor.stop()
        }
    }
}

enum DictationState: String {
    case idle
    case recording
    case downloading
    case transcribing
    case error

    var isDictationActive: Bool {
        switch self {
        case .recording, .transcribing: true
        case .idle, .downloading, .error: false
        }
    }

    var menuTitle: String {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Majordomo"
        return switch self {
        case .idle: L10n.text("state.idle", appName)
        case .recording: L10n.text("state.recording", appName)
        case .downloading: L10n.text("state.downloading", appName)
        case .transcribing: L10n.text("state.transcribing", appName)
        case .error: L10n.text("state.error", appName)
        }
    }
}

