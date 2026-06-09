import Foundation
import MajordomoCore

struct AudioFileTranscriber {
    let whisperBackendOverride: WhisperCppBackend?

    init(whisperBackend: WhisperCppBackend? = nil) {
        self.whisperBackendOverride = whisperBackend
    }

    func transcribe(audioURL: URL, backend: TranscriptionBackendKind, language: String) async throws -> TranscriptionResult {
        guard SupportedAudioFile.isSupported(audioURL) else {
            throw AudioFileTranscriberError.unsupportedFileType(audioURL.pathExtension)
        }

        let normalizedURL = try await normalizeForSpeechToText(audioURL)
        defer { try? FileManager.default.removeItem(at: normalizedURL) }

        let whisperBackend = whisperBackendOverride ?? WhisperCppBackend(modelManager: ModelManager(kind: backend))
        return try await whisperBackend.transcribe(audioURL: normalizedURL, language: language)
    }

    private func normalizeForSpeechToText(_ audioURL: URL) async throws -> URL {
        let outputURL = Self.makeTemporaryWAVURL(sourceURL: audioURL)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        do {
            try await Self.convertToSpeechToTextWAV(inputURL: audioURL, outputURL: outputURL)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw AudioFileTranscriberError.normalizationFailed(error.localizedDescription)
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw AudioFileTranscriberError.normalizedOutputMissing(outputURL)
        }

        return outputURL
    }

    private static func convertToSpeechToTextWAV(inputURL: URL, outputURL: URL) async throws {
        let executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw AudioFileTranscriberError.normalizationFailed("macOS audio converter is unavailable at /usr/bin/afconvert.")
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            inputURL.path,
            "-f", "WAVE",
            "-d", "LEI16@16000",
            "-c", "1",
            outputURL.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let outputData = await readToEnd(pipe.fileHandleForReading)
        let terminationStatus = await process.waitForExit()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        guard terminationStatus == 0 else {
            throw AudioFileTranscriberError.normalizationFailed("afconvert failed with exit code \(terminationStatus): \(output)")
        }
    }

    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await Task.detached(priority: .utility) {
            handle.readDataToEndOfFile()
        }.value
    }

    private static func makeTemporaryWAVURL(sourceURL: URL) -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Majordomo", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
        return directory.appendingPathComponent("file-transcription-\(base)-\(UUID().uuidString).wav", isDirectory: false)
    }
}

enum AudioFileTranscriberError: LocalizedError {
    case unsupportedFileType(String)
    case normalizationFailed(String)
    case normalizedOutputMissing(URL)

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let ext):
            L10n.text("error.file.unsupported", ext.isEmpty ? "unknown" : ext)
        case .normalizationFailed(let message):
            L10n.text("error.file.normalization_failed", message)
        case .normalizedOutputMissing(let url):
            L10n.text("error.file.output_missing", url.path)
        }
    }
}
