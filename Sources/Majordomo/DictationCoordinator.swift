import AppKit
import MajordomoCore

/// Cross-cutting services the dictation coordinator needs from the app. Keeps
/// the coordinator focused on the live-dictation state machine while shared
/// state (the app-wide `DictationState`, model availability, status messaging)
/// stays owned by the app delegate.
@MainActor
protocol DictationCoordinatorHost: AnyObject {
    var dictationState: DictationState { get set }
    var currentBackendKind: TranscriptionBackendKind { get }
    var currentLanguage: String { get }
    var isIndicatorEnabled: Bool { get }
    var currentSoundProfile: DictationSoundProfile { get }
    var shouldPreserveRecordedAudio: Bool { get }
    var lastTranscript: String? { get set }

    func isLiveDictationReady() -> Bool
    func modelManager(for backend: TranscriptionBackendKind) -> ModelManager
    func ensureModelAvailable(for backend: TranscriptionBackendKind) async throws -> URL
    func setStatusMessage(_ message: String?)
    func presentAccessibilityNeededAlert()
}

/// Owns the live-dictation lifecycle extracted from the app delegate: the
/// start/stop/cancel state machine, the streaming Whisper session, the
/// recording, overlay, and text insertion. Session-scoped state lives here;
/// app-wide state is reached through ``DictationCoordinatorHost``.
@MainActor
final class DictationCoordinator {
    private weak var host: DictationCoordinatorHost?
    private let audioRecorder: AudioRecorder
    private let overlay: DictationOverlayWindowController
    private let textInsertion: TextInsertionService

    private var sessionID = UUID()
    private var liveSession: WhisperLiveDictationSession?
    private var pendingStopAfterRecordingStart = false
    private var transcriptionTask: Task<Void, Never>?
    private var targetApplication: NSRunningApplication?

    /// Peak amplitude (0…1) below which a capture is treated as silent. Real
    /// speech peaks well above 0.1; dead silence (muted/idle input) sits near 0.
    private static let silenceThreshold: Float = 0.01

    init(audioRecorder: AudioRecorder,
         overlay: DictationOverlayWindowController,
         textInsertion: TextInsertionService,
         host: DictationCoordinatorHost) {
        self.audioRecorder = audioRecorder
        self.overlay = overlay
        self.textInsertion = textInsertion
        self.host = host
    }

    func toggle() {
        guard let host else { return }
        switch host.dictationState {
        case .idle, .error:
            start()
        case .recording:
            stop()
        case .downloading, .transcribing:
            break
        }
    }

    func start() {
        guard let host else { return }
        let sessionID = UUID()
        self.sessionID = sessionID
        liveSession?.cancel()
        liveSession = nil
        pendingStopAfterRecordingStart = false
        transcriptionTask?.cancel()
        transcriptionTask = nil
        targetApplication = Self.currentInsertionTarget()
        if audioRecorder.needsMicrophonePermissionPrompt {
            NSApp.activate(ignoringOtherApps: true)
        }

        Task { @MainActor in
            do {
                let profile = host.currentBackendKind
                guard host.isLiveDictationReady() else {
                    throw RuntimeDependencyError.bundledHelperMissing(.whisperDictate)
                }
                if !host.modelManager(for: profile).hasModel() {
                    host.dictationState = .downloading
                }
                _ = try await host.ensureModelAvailable(for: profile)

                let liveSession = try WhisperCppBackend(modelManager: host.modelManager(for: profile))
                    .startLiveDictation(language: host.currentLanguage)
                self.liveSession = liveSession

                SoundFeedback.playStart(for: host.currentSoundProfile)
                host.dictationState = .recording
                if host.isIndicatorEnabled {
                    self.overlay.showRecording()
                }

                try await self.audioRecorder.start(
                    levelsHandler: { [weak self] levels in
                        if self?.host?.isIndicatorEnabled == true {
                            self?.overlay.updateLevels(levels)
                        }
                    },
                    sampleHandler: { data in
                        liveSession.appendPCM(data)
                    },
                    captureAudio: host.shouldPreserveRecordedAudio
                )

                guard self.sessionID == sessionID, host.dictationState == .recording else {
                    let capture = self.audioRecorder.stop()
                    liveSession.cancel()
                    if self.liveSession === liveSession {
                        self.liveSession = nil
                    }
                    self.cleanupRecording(capture, reason: "abandoned dictation start")
                    return
                }

                AppLog.info("recording started via live Whisper pipe")

                if self.pendingStopAfterRecordingStart {
                    self.pendingStopAfterRecordingStart = false
                    self.stop(playFeedback: false)
                }
            } catch {
                guard self.sessionID == sessionID else { return }
                let capture = self.audioRecorder.stop()
                self.pendingStopAfterRecordingStart = false
                self.overlay.hide()
                self.liveSession?.cancel()
                self.liveSession = nil
                self.cleanupRecording(capture, reason: "failed dictation start")
                host.dictationState = .error
                host.setStatusMessage(L10n.text("status.dictation_start_failed", error.localizedDescription))
                AppLog.error("recording failed: \(error.localizedDescription)")
                NSSound.beep()
            }
        }
    }

    func stop(playFeedback: Bool = true) {
        guard let host else { return }
        let sessionID = self.sessionID

        guard audioRecorder.isRecording else {
            pendingStopAfterRecordingStart = true
            if playFeedback {
                SoundFeedback.playStop(for: host.currentSoundProfile)
            }
            AppLog.info("stop requested before recorder was ready; waiting for recording start")
            return
        }

        guard let liveSession = liveSession else {
            let capture = audioRecorder.stop()
            pendingStopAfterRecordingStart = false
            overlay.hide()
            cleanupRecording(capture, reason: "missing live helper session")
            host.dictationState = .error
            host.setStatusMessage(L10n.text("status.helper_session_missing"))
            AppLog.error("live dictation helper session missing while stopping recording")
            NSSound.beep()
            return
        }

        let capture = audioRecorder.stop()
        let inputPeak = audioRecorder.lastSessionPeak
        let inputDescription = audioRecorder.lastInputDescription
        pendingStopAfterRecordingStart = false
        if playFeedback {
            SoundFeedback.playStop(for: host.currentSoundProfile)
        }

        if host.isIndicatorEnabled {
            overlay.showTranscribing()
        }
        host.dictationState = .transcribing
        AppLog.info("recording stopped; finalizing live Whisper transcript")

        transcriptionTask?.cancel()
        transcriptionTask = Task { @MainActor in
            var shouldFadeOverlay = false
            var cleanupReason = "completed transcription"
            defer {
                if self.sessionID == sessionID {
                    if shouldFadeOverlay {
                        self.overlay.fadeOutAndHide()
                    } else {
                        self.overlay.hide()
                    }
                    if self.liveSession === liveSession {
                        self.liveSession = nil
                    }
                    self.transcriptionTask = nil
                    self.cleanupRecording(capture, reason: cleanupReason)
                }
            }

            do {
                try Task.checkCancellation()
                host.dictationState = .transcribing
                let result = try await liveSession.finish()

                try Task.checkCancellation()
                guard self.sessionID == sessionID, host.dictationState == .transcribing else { return }

                // Silent capture: Whisper hallucinates filler ("thank you") from
                // pure silence. Surface a real diagnostic instead of inserting it.
                if inputPeak < Self.silenceThreshold {
                    cleanupReason = "no audible input"
                    self.targetApplication = nil
                    host.dictationState = .idle
                    host.setStatusMessage(L10n.text("status.no_audio_detected"))
                    AppLog.error("no audible mic input (peak \(String(format: "%.4f", inputPeak))); \(inputDescription) — transcript suppressed")
                    shouldFadeOverlay = true
                    return
                }

                host.lastTranscript = result.text
                let insertionResult = try await self.textInsertion.insert(result.text, targetApplication: self.targetApplication)

                try Task.checkCancellation()
                guard self.sessionID == sessionID else { return }

                self.targetApplication = nil
                host.dictationState = .idle
                if let targetApplicationName = insertionResult.targetApplicationName,
                   !targetApplicationName.isEmpty {
                    host.setStatusMessage(L10n.text("status.dictation_inserted", targetApplicationName))
                } else {
                    host.setStatusMessage(L10n.text("status.dictation_inserted_focused"))
                }
                shouldFadeOverlay = true
                AppLog.info("transcript inserted via \(insertionResult.method.rawValue) into \(insertionResult.targetApplicationName ?? "focused app") (\(String(format: "%.2f", result.duration))s)")
            } catch is CancellationError {
                cleanupReason = "canceled dictation"
                liveSession.cancel()
                AppLog.info("transcription canceled")
            } catch WhisperLiveDictationSessionError.noAudioCaptured {
                cleanupReason = "too-short dictation"
                self.targetApplication = nil
                host.dictationState = .idle
                host.setStatusMessage(L10n.text("status.dictation_too_short"))
                AppLog.info("dictation too short; no audio captured")
            } catch TextInsertionError.emptyText {
                cleanupReason = "too-short dictation (empty text)"
                self.targetApplication = nil
                host.dictationState = .idle
                host.setStatusMessage(L10n.text("status.dictation_too_short"))
                AppLog.info("dictation too short; empty transcription output")
            } catch TextInsertionError.accessibilityPermissionMissing {
                // Don't lose the user's words: put the transcript on the
                // clipboard so it's one ⌘V away, and point them to the setting.
                cleanupReason = "accessibility missing"
                self.targetApplication = nil
                host.dictationState = .idle
                if let transcript = host.lastTranscript {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcript, forType: .string)
                }
                host.setStatusMessage(L10n.text("status.accessibility_needed"))
                host.presentAccessibilityNeededAlert()
                AppLog.info("insertion blocked: accessibility not granted; transcript copied to clipboard")
            } catch {
                guard self.sessionID == sessionID else { return }
                cleanupReason = "failed dictation"
                self.targetApplication = nil
                host.dictationState = .error
                host.setStatusMessage(L10n.text("status.dictation_failed", error.localizedDescription))
                AppLog.error("transcription or insertion failed: \(error.localizedDescription)")
                NSSound.beep()
            }
        }
    }

    /// Cancels active dictation (the double-Escape gesture and the menu's Cancel
    /// item). No-op when nothing is being dictated.
    func cancel() {
        guard let host, host.dictationState.isDictationActive else { return }

        let cancelledState = host.dictationState
        sessionID = UUID()
        pendingStopAfterRecordingStart = false
        transcriptionTask?.cancel()
        transcriptionTask = nil

        let capture = audioRecorder.stop()
        liveSession?.cancel()
        liveSession = nil
        targetApplication = nil
        overlay.hide()
        host.dictationState = .idle
        cleanupRecording(capture, reason: "canceled dictation")

        AppLog.info("dictation canceled while \(cancelledState.rawValue)")
    }

    // MARK: - Recording preservation

    private func cleanupRecording(_ capture: RecordedAudioCapture?, reason: String) {
        guard host?.shouldPreserveRecordedAudio == true, let capture else { return }
        let preservedURL = preserveRecording(capture)
        AppLog.info("preserved WAV for \(reason): \(preservedURL?.path ?? capture.fileName)")
    }

    private func preserveRecording(_ capture: RecordedAudioCapture) -> URL? {
        let bundleID = Bundle.main.bundleIdentifier ?? AppInfo.fallbackBundleIdentifier
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Preserved Recordings", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destinationURL = directory.appendingPathComponent(capture.fileName, isDirectory: false)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try capture.writeWAV(to: destinationURL)
            return destinationURL
        } catch {
            AppLog.error("could not preserve WAV at \(directory.path)/\(capture.fileName): \(error.localizedDescription)")
            return nil
        }
    }

    private static func currentInsertionTarget() -> NSRunningApplication? {
        let currentBundleIdentifier = Bundle.main.bundleIdentifier
        let frontmostApplication = NSWorkspace.shared.frontmostApplication

        guard frontmostApplication?.bundleIdentifier != currentBundleIdentifier else {
            return nil
        }

        return frontmostApplication
    }
}
