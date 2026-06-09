import Foundation

struct LiveTranscriptionResult: Sendable {
    let text: String
    let modelURL: URL
    let duration: TimeInterval
}

enum WhisperLiveDictationSessionError: LocalizedError {
    case stdinWriteFailed(String)
    case noAudioCaptured
    case processFailed(Int32, String)
    case outputUnreadable

    var errorDescription: String? {
        switch self {
        case .stdinWriteFailed(let message):
            L10n.text("error.whisper.stream_failed", message)
        case .noAudioCaptured:
            L10n.text("error.whisper.no_audio")
        case .processFailed(let code, let output):
            L10n.text("error.whisper.dictate_failed", code, output)
        case .outputUnreadable:
            L10n.text("error.whisper.output_unreadable")
        }
    }
}

final class WhisperLiveDictationSession: @unchecked Sendable {
    private let process: Process
    private let stdinHandle: FileHandle
    private let stdoutTask: Task<Data, Never>
    private let stderrTask: Task<Data, Never>
    private let modelURL: URL
    private let startedAt: Date
    private let ioQueue = DispatchQueue(label: "pl.wild-matrix.majordomo.whisper-dictate-io")

    private var inputClosed = false
    private var writeFailure: String?
    private var bytesWritten = 0

    init(
        process: Process,
        stdinHandle: FileHandle,
        stdoutHandle: FileHandle,
        stderrHandle: FileHandle,
        modelURL: URL,
        startedAt: Date = Date()
    ) {
        self.process = process
        self.stdinHandle = stdinHandle
        self.modelURL = modelURL
        self.startedAt = startedAt
        self.stdoutTask = Task.detached(priority: .utility) {
            stdoutHandle.readDataToEndOfFile()
        }
        self.stderrTask = Task.detached(priority: .utility) {
            stderrHandle.readDataToEndOfFile()
        }
    }

    func appendPCM(_ data: Data) {
        guard !data.isEmpty else { return }

        // Non-blocking from the caller's perspective. The audio tap thread must
        // never park inside `stdinHandle.write`: when the kernel pipe buffer
        // fills (the helper stalls or back-pressures), a synchronous write would
        // block the tap, which `AudioRecorder.stop()` joins on the MainActor —
        // deadlocking the whole app. Enqueuing on the serial `ioQueue` keeps the
        // tap fast and preserves FIFO ordering of the pipe writes.
        ioQueue.async { [weak self] in
            guard let self else { return }
            guard !self.inputClosed, self.writeFailure == nil else { return }
            do {
                try self.stdinHandle.write(contentsOf: data)
                self.bytesWritten += data.count
            } catch {
                self.writeFailure = error.localizedDescription
                self.closeInputLocked()
            }
        }
    }

    func finish() async throws -> LiveTranscriptionResult {
        let finishState = ioQueue.sync { () -> (String?, Int) in
            let result = (writeFailure, bytesWritten)
            closeInputLocked()
            return result
        }

        if let writeFailure = finishState.0 {
            cancel()
            throw WhisperLiveDictationSessionError.stdinWriteFailed(writeFailure)
        }

        if finishState.1 == 0 {
            cancel()
            throw WhisperLiveDictationSessionError.noAudioCaptured
        }

        let terminationStatus = await process.waitForExit()

        let stdoutData = await stdoutTask.value
        let stderrData = await stderrTask.value
        let stderrOutput = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard terminationStatus == 0 else {
            AppLog.error("whisper-dictate exit \(terminationStatus): \(stderrOutput)")
            throw WhisperLiveDictationSessionError.processFailed(terminationStatus, stderrOutput)
        }

        guard let transcript = String(data: stdoutData, encoding: .utf8) else {
            throw WhisperLiveDictationSessionError.outputUnreadable
        }

        return LiveTranscriptionResult(
            text: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            modelURL: modelURL,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    func cancel() {
        // Terminate first: closing the child's read end unblocks any write that
        // is currently parked on a full pipe, so the io queue can drain. Doing
        // `ioQueue.sync` here instead would re-introduce the deadlock on the
        // cancel path (cancel runs on the MainActor). Close stdin asynchronously
        // once the queue is free.
        if process.isRunning {
            process.terminate()
        }

        ioQueue.async { [weak self] in
            self?.closeInputLocked()
        }
    }

    private func closeInputLocked() {
        guard !inputClosed else { return }
        inputClosed = true
        try? stdinHandle.close()
    }
}

struct TranscriptionResult: Sendable {
    let text: String
    let audioURL: URL
    let modelURL: URL
    let duration: TimeInterval
}

enum WhisperCppBackendError: LocalizedError {
    case executableMissing(RuntimeDependencyKind)
    case processFailed(Int32, String)
    case outputMissing(URL)
    case outputUnreadable(URL)

    var errorDescription: String? {
        switch self {
        case .executableMissing(let kind):
            L10n.text("error.whisper.executable_missing", kind.displayName, kind.executableName)
        case .processFailed(let code, let output):
            L10n.text("error.whisper.helper_failed", code, output)
        case .outputMissing(let url):
            L10n.text("error.whisper.txt_missing", url.path)
        case .outputUnreadable(let url):
            L10n.text("error.whisper.txt_unreadable", url.path)
        }
    }
}

struct WhisperCppBackend {
    private let modelManager: ModelManager
    private let runtimeManager: RuntimeDependencyManager
    private let modelURLOverride: URL?

    init(
        modelManager: ModelManager = ModelManager(kind: .largeV3TurboQ8),
        runtimeManager: RuntimeDependencyManager = RuntimeDependencyManager(),
        modelURLOverride: URL? = nil
    ) {
        self.modelManager = modelManager
        self.runtimeManager = runtimeManager
        self.modelURLOverride = modelURLOverride
    }

    func transcribe(audioURL: URL, language: String = "pl") async throws -> TranscriptionResult {
        let startedAt = Date()
        let modelURL = try modelURLOverride ?? modelManager.requireModel()
        let executableURL = try findExecutable(for: .whisperCLI)
        let outputPrefix = Self.makeOutputPrefix()
        let transcriptURL = outputPrefix.appendingPathExtension("txt")

        let process = Process()
        process.executableURL = executableURL
        process.environment = RuntimeDependencyManager.environment(for: executableURL)
        process.arguments = [
            "-l", language,
            "-m", modelURL.path,
            "-f", audioURL.path,
            "-otxt",
            "-of", outputPrefix.path,
            "-nt"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let outputData = await readToEnd(pipe.fileHandleForReading)
        let terminationStatus = await process.waitForExit()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        guard terminationStatus == 0 else {
            AppLog.error("whisper-cli exit \(terminationStatus): \(output)")
            throw WhisperCppBackendError.processFailed(terminationStatus, output)
        }

        guard FileManager.default.fileExists(atPath: transcriptURL.path) else {
            throw WhisperCppBackendError.outputMissing(transcriptURL)
        }

        guard let text = try? String(contentsOf: transcriptURL, encoding: .utf8) else {
            throw WhisperCppBackendError.outputUnreadable(transcriptURL)
        }
        try? FileManager.default.removeItem(at: transcriptURL)

        return TranscriptionResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            audioURL: audioURL,
            modelURL: modelURL,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    func startLiveDictation(language: String = "pl") throws -> WhisperLiveDictationSession {
        let modelURL = try modelURLOverride ?? modelManager.requireModel()
        let executableURL = try findExecutable(for: .whisperDictate)

        let process = Process()
        process.executableURL = executableURL
        process.environment = RuntimeDependencyManager.environment(for: executableURL)
        process.arguments = [
            "--model", modelURL.path,
            "--language", language
        ]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        return WhisperLiveDictationSession(
            process: process,
            stdinHandle: stdinPipe.fileHandleForWriting,
            stdoutHandle: stdoutPipe.fileHandleForReading,
            stderrHandle: stderrPipe.fileHandleForReading,
            modelURL: modelURL
        )
    }

    private func findExecutable(for kind: RuntimeDependencyKind) throws -> URL {
        guard let url = runtimeManager.findExecutable(for: kind) else {
            throw WhisperCppBackendError.executableMissing(kind)
        }
        return url
    }

    private func readToEnd(_ handle: FileHandle) async -> Data {
        await Task.detached(priority: .utility) {
            handle.readDataToEndOfFile()
        }.value
    }

    private static func makeOutputPrefix() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Majordomo", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "transcript-\(timestamp())"
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }
}
