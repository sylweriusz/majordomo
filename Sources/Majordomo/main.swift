import AppKit
import Foundation

// Writing to a pipe whose read end has closed (e.g. the whisper-dictate helper
// died mid-stream) raises SIGPIPE, which by default terminates the whole app.
// We handle the resulting EPIPE in the write paths, so ignore the signal.
signal(SIGPIPE, SIG_IGN)

if let exportIndex = CommandLine.arguments.firstIndex(of: "--export-sound-previews") {
    let outputPath: String
    if CommandLine.arguments.indices.contains(exportIndex + 1) {
        outputPath = CommandLine.arguments[exportIndex + 1]
    } else {
        outputPath = ".e2e-runs/sound-previews"
    }
    do {
        try SoundFeedback.exportPreviewSounds(to: URL(fileURLWithPath: outputPath))
        print("Exported Majordomo sound previews to \(outputPath)")
        exit(0)
    } catch {
        fputs("Failed to export Majordomo sound previews: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

if let downloadIndex = CommandLine.arguments.firstIndex(of: "--test-download-model") {
    let kindArg: String
    if CommandLine.arguments.indices.contains(downloadIndex + 1) {
        kindArg = CommandLine.arguments[downloadIndex + 1]
    } else {
        kindArg = "large-v3-turbo-q8_0"
    }
    guard let kind = TranscriptionBackendKind(rawValue: kindArg) else {
        fputs("Unknown model kind: \(kindArg). Valid: \(TranscriptionBackendKind.allCases.map(\.rawValue).joined(separator: ", "))\n", stderr)
        exit(2)
    }

    let manager = ModelManager(kind: kind)
    let modelURL = manager.modelURL
    let backupURL = modelURL.appendingPathExtension("e2e-backup")

    fputs("=== Model Download Destructive Test ===\n", stderr)
    fputs("Model: \(kind.displayName) (\(kind.sizeLabel))\n", stderr)
    fputs("Path: \(modelURL.path)\n", stderr)

    // Backup
    if FileManager.default.fileExists(atPath: modelURL.path) {
        fputs("📦 Backing up existing model...\n", stderr)
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
        }
        do {
            try FileManager.default.moveItem(at: modelURL, to: backupURL)
            fputs("   Backup: \(backupURL.path)\n", stderr)
        } catch {
            fputs("❌ Backup failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    defer {
        if FileManager.default.fileExists(atPath: backupURL.path),
           !FileManager.default.fileExists(atPath: modelURL.path) {
            fputs("🔁 Restoring backup after failure...\n", stderr)
            try? FileManager.default.moveItem(at: backupURL, to: modelURL)
        }
        if FileManager.default.fileExists(atPath: backupURL.path),
           FileManager.default.fileExists(atPath: modelURL.path) {
            fputs("🧹 Cleaning up backup (download succeeded)\n", stderr)
            try? FileManager.default.removeItem(at: backupURL)
        }
    }

    guard !manager.hasModel() else {
        fputs("❌ Model still present after removal\n", stderr)
        exit(1)
    }
    fputs("✅ Model removed from cache\n", stderr)

    fputs("⬇️  Downloading from \(kind.downloadURL)...\n", stderr)
    let startTime = Date()
    Task {
        do {
            let downloadedURL = try await manager.downloadModelIfMissing()
            let elapsed = Date().timeIntervalSince(startTime)
            fputs("✅ Download successful!\n", stderr)
            fputs("   File: \(downloadedURL.path)\n", stderr)
            fputs("   SHA-256: \(kind.expectedSHA256)\n", stderr)
            fputs("   Time: \(String(format: "%.1f", elapsed))s\n", stderr)
            exit(0)
        } catch let error as ModelManagerError {
            fputs("❌ ModelManagerError: \(error.localizedDescription)\n", stderr)
            exit(1)
        } catch {
            fputs("❌ Download failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    dispatchMain()
}

if let transcribeIndex = CommandLine.arguments.firstIndex(of: "--transcribe-audio-file") {
    guard CommandLine.arguments.indices.contains(transcribeIndex + 1) else {
        fputs("usage: Majordomo --transcribe-audio-file <path> [--backend large-v3-turbo-q8_0|large-v3-turbo|large-v3] [--language auto|en|pl|...] [--whisper-model <path>] [--output <path>]\n", stderr)
        exit(2)
    }

    let audioURL = URL(fileURLWithPath: CommandLine.arguments[transcribeIndex + 1])
    let backend = commandLineValue(for: "--backend")
        .flatMap(TranscriptionBackendKind.init(rawValue:)) ?? .largeV3TurboQ8
    let language = commandLineValue(for: "--language") ?? "auto"
    let outputPath = commandLineValue(for: "--output")
    let whisperModelURL = commandLineValue(for: "--whisper-model").map { URL(fileURLWithPath: $0) }
    let transcriber = if let whisperModelURL {
        AudioFileTranscriber(whisperBackend: WhisperCppBackend(modelURLOverride: whisperModelURL))
    } else {
        AudioFileTranscriber()
    }

    Task {
        do {
            let result = try await transcriber.transcribe(audioURL: audioURL, backend: backend, language: language)
            if let outputPath {
                try result.text.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
            } else {
                print(result.text)
            }
            fputs("transcribed backend=\(backend.rawValue) model=\(result.modelURL.path) duration=\(String(format: "%.2f", result.duration))s audio=\(audioURL.path)\n", stderr)
            exit(0)
        } catch {
            fputs("audio file transcription failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    dispatchMain()
}

private func commandLineValue(for option: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: option),
          CommandLine.arguments.indices.contains(index + 1) else {
        return nil
    }
    return CommandLine.arguments[index + 1]
}

let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
