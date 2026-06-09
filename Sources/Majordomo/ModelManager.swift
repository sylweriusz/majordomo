import Foundation

public enum TranscriptionBackendKind: String, CaseIterable, Sendable {
    case largeV3TurboQ8 = "large-v3-turbo-q8_0"
    case largeV3Turbo = "large-v3-turbo"
    case largeV3 = "large-v3"

    public var displayName: String {
        switch self {
        case .largeV3TurboQ8: "Whisper Large v3 Turbo 8-bit"
        case .largeV3Turbo: "Whisper Large v3 Turbo"
        case .largeV3: "Whisper Large v3"
        }
    }

    public var shortDisplayName: String {
        switch self {
        case .largeV3TurboQ8: "Large v3 Turbo 8-bit"
        case .largeV3Turbo: "Large v3 Turbo"
        case .largeV3: "Large v3"
        }
    }

    public var modelFileName: String {
        switch self {
        case .largeV3TurboQ8: "ggml-large-v3-turbo-q8_0.bin"
        case .largeV3Turbo: "ggml-large-v3-turbo.bin"
        case .largeV3: "ggml-large-v3.bin"
        }
    }

    public var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(modelFileName)")!
    }

    public var expectedSizeBytes: Int64 {
        switch self {
        case .largeV3TurboQ8: 874_188_075
        case .largeV3Turbo: 1_624_555_275
        case .largeV3: 3_095_033_483
        }
    }

    public var minimumDownloadSizeBytes: Int64 {
        Int64(Double(expectedSizeBytes) * 0.95)
    }

    /// SHA-256 checksum computed from locally downloaded models whose SHA-1
    /// matches the ggerganov/whisper.cpp HuggingFace repository.
    /// Computed from locally downloaded models whose SHA-1 matches the published values.
    public var expectedSHA256: String {
        switch self {
        case .largeV3TurboQ8: "317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1"
        case .largeV3Turbo:   "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"
        case .largeV3:        "64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2"
        }
    }

    public var speedLabel: String {
        switch self {
        case .largeV3TurboQ8: L10n.text("model.speed_very_fast")
        case .largeV3Turbo: L10n.text("model.speed_fast")
        case .largeV3: L10n.text("model.speed_slower")
        }
    }

    public var accuracyPercent: Int {
        switch self {
        case .largeV3TurboQ8: 94
        case .largeV3Turbo: 95
        case .largeV3: 98
        }
    }

    public var sizeLabel: String {
        let gigabyte = 1_024.0 * 1_024.0 * 1_024.0
        let megabyte = 1_024.0 * 1_024.0
        let bytes = Double(expectedSizeBytes)
        if bytes >= gigabyte {
            return String(format: "%.1f GB", bytes / gigabyte)
        }
        return String(format: "%.0f MB", bytes / megabyte)
    }

    public var menuDescription: String {
        L10n.text("model.menu_description", sizeLabel, speedLabel, accuracyPercent)
    }
}

public enum ModelManagerError: LocalizedError {
    case modelMissing(TranscriptionBackendKind, URL)
    case invalidHTTPResponse
    case downloadFailed(Int)
    case downloadedFileTooSmall(Int64)
    case checksumMismatch(TranscriptionBackendKind, String, String)

    public var errorDescription: String? {
        switch self {
        case .modelMissing(let profile, let url):
            L10n.text("error.model.missing", profile.displayName, url.path, profile.shortDisplayName)
        case .invalidHTTPResponse:
            L10n.text("error.model.invalid_http")
        case .downloadFailed(let statusCode):
            L10n.text("error.model.download_failed", statusCode)
        case .downloadedFileTooSmall(let size):
            L10n.text("error.model.too_small", size)
        case .checksumMismatch(let profile, let expected, let got):
            L10n.text("error.model.checksum_mismatch", profile.displayName, expected, got)
        }
    }
}

public struct ModelManager: Sendable {
    public let kind: TranscriptionBackendKind

    public init(kind: TranscriptionBackendKind = .largeV3TurboQ8) {
        self.kind = kind
    }

    public var modelDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".models", isDirectory: true)
    }

    public var modelURL: URL {
        modelDirectoryURL.appendingPathComponent(kind.modelFileName, isDirectory: false)
    }

    public func hasModel() -> Bool {
        FileManager.default.fileExists(atPath: modelURL.path)
    }

    /// Removes the downloaded model file, if present. No-op when it's missing.
    public func deleteModel() throws {
        guard FileManager.default.fileExists(atPath: modelURL.path) else { return }
        try FileManager.default.removeItem(at: modelURL)
    }

    func isRuntimeAvailable() -> Bool {
        RuntimeDependencyManager().findExecutable(for: .whisperCLI) != nil
    }

    public func requireModel() throws -> URL {
        let url = modelURL
        guard hasModel() else {
            throw ModelManagerError.modelMissing(kind, url)
        }
        return url
    }

    public func downloadModelIfMissing(onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        if hasModel() {
            return modelURL
        }
        return try await downloadWhisperModelIfMissing(onProgress: onProgress)
    }

    private func downloadWhisperModelIfMissing(onProgress: (@Sendable (Double) -> Void)?) async throws -> URL {
        try FileManager.default.createDirectory(at: modelDirectoryURL, withIntermediateDirectories: true)

        let progressDelegate = onProgress.map {
            ModelDownloadProgressDelegate(expectedBytes: kind.expectedSizeBytes, onProgress: $0)
        }
        let (temporaryURL, response) = try await URLSession.shared.download(from: kind.downloadURL, delegate: progressDelegate)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelManagerError.invalidHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            AppLog.error("model download HTTP \(httpResponse.statusCode) for \(kind.rawValue)")
            throw ModelManagerError.downloadFailed(httpResponse.statusCode)
        }

        let size = try fileSize(at: temporaryURL)
        guard size >= kind.minimumDownloadSizeBytes else {
            AppLog.error("model download too small: \(size) bytes for \(kind.rawValue)")
            throw ModelManagerError.downloadedFileTooSmall(size)
        }

        let sha256 = try await sha256OfFile(at: temporaryURL)
        guard sha256 == kind.expectedSHA256 else {
            try? FileManager.default.removeItem(at: temporaryURL)
            AppLog.error("model checksum mismatch for \(kind.rawValue): expected \(kind.expectedSHA256), got \(sha256)")
            throw ModelManagerError.checksumMismatch(kind, kind.expectedSHA256, sha256)
        }

        let destinationURL = modelURL
        let partialURL = destinationURL.appendingPathExtension("download")
        if FileManager.default.fileExists(atPath: partialURL.path) {
            try FileManager.default.removeItem(at: partialURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: partialURL)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: partialURL, to: destinationURL)

        return destinationURL
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private func sha256OfFile(at url: URL) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", url.path]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        try process.run()
        // Read to EOF before awaiting exit so a large hash output can never
        // fill the pipe buffer and deadlock the process.
        let outputData = await Task.detached(priority: .utility) {
            outputPipe.fileHandleForReading.readDataToEndOfFile()
        }.value
        _ = await process.waitForExit()
        guard let output = String(data: outputData, encoding: .utf8) else {
            throw ModelManagerError.checksumMismatch(kind, kind.expectedSHA256, "\(url.lastPathComponent): parse error")
        }
        let components = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
        guard let hash = components.first, !hash.isEmpty else {
            throw ModelManagerError.checksumMismatch(kind, kind.expectedSHA256, "\(url.lastPathComponent): empty hash")
        }
        return hash
    }
}

/// Reports download progress (0…1) for the model fetch. Falls back to the known
/// expected size when the server doesn't send a Content-Length.
private final class ModelDownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let expectedBytes: Int64
    private let onProgress: @Sendable (Double) -> Void

    init(expectedBytes: Int64, onProgress: @escaping @Sendable (Double) -> Void) {
        self.expectedBytes = expectedBytes
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytes
        guard total > 0 else { return }
        onProgress(min(1, Double(totalBytesWritten) / Double(total)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The async download(from:delegate:) API handles the downloaded file;
        // this required callback intentionally does nothing.
    }
}
