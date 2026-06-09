import Foundation
import MajordomoCore

enum RuntimeDependencyKind: String, CaseIterable, Sendable {
    case whisperCLI
    case whisperDictate

    var displayName: String {
        switch self {
        case .whisperCLI: L10n.text("runtime.whisper_file")
        case .whisperDictate: L10n.text("runtime.whisper_dictation")
        }
    }

    var executableName: String {
        switch self {
        case .whisperCLI: "whisper-cli"
        case .whisperDictate: "whisper-dictate"
        }
    }
}

enum RuntimeDependencyStatus: Sendable {
    case ready(URL)
    case missing

    var title: String {
        switch self {
        case .ready(let url): "\(L10n.text("common.ready")) — \(url.lastPathComponent)"
        case .missing: L10n.text("common.missing")
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

enum RuntimeDependencyError: LocalizedError {
    case bundledHelperMissing(RuntimeDependencyKind)

    var errorDescription: String? {
        switch self {
        case .bundledHelperMissing(let kind):
            L10n.text("error.runtime.helper_missing", kind.displayName)
        }
    }
}

struct RuntimeDependencyManager: Sendable {
    var helpersDirectoryURL: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? AppInfo.fallbackBundleIdentifier
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
    }

    func status(for kind: RuntimeDependencyKind) -> RuntimeDependencyStatus {
        if let url = findExecutable(for: kind) {
            return .ready(url)
        }
        return .missing
    }

    func findExecutable(for kind: RuntimeDependencyKind) -> URL? {
        for url in appOwnedCandidateURLs(for: kind) where FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }

        if let devURL = devFallbackExecutable(for: kind) {
            return devURL
        }

        return nil
    }

    private func appOwnedCandidateURLs(for kind: RuntimeDependencyKind) -> [URL] {
        var urls = [URL]()
        if let bundledURL = bundledHelperURL(for: kind) {
            urls.append(bundledURL)
        }
        urls.append(helpersDirectoryURL.appendingPathComponent(kind.executableName, isDirectory: false))
        return urls
    }

    private func bundledHelperURL(for kind: RuntimeDependencyKind) -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        return resourceURL
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent(kind.executableName, isDirectory: false)
    }

    static func environment(for executableURL: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let helperDirectory = executableURL.deletingLastPathComponent()
        let libDirectory = helperDirectory.appendingPathComponent("lib", isDirectory: true)
        let libexecDirectory = helperDirectory.appendingPathComponent("libexec", isDirectory: true)

        let dyldDirectories = [libDirectory]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(\.path)
        if !dyldDirectories.isEmpty {
            let existing = environment["DYLD_LIBRARY_PATH"]
            environment["DYLD_LIBRARY_PATH"] = (dyldDirectories + [existing].compactMap { $0 }).joined(separator: ":")
        }

        if FileManager.default.fileExists(atPath: libexecDirectory.path) {
            environment["GGML_BACKEND_PATH"] = libexecDirectory.path
        }

        return environment
    }

    private func devFallbackExecutable(for kind: RuntimeDependencyKind) -> URL? {
        if let override = ProcessInfo.processInfo.environment["MAJORDOMO_\(kind.rawValue.uppercased())_PATH"],
           FileManager.default.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        guard ProcessInfo.processInfo.environment["MAJORDOMO_ENABLE_DEV_RUNTIME_FALLBACK"] == "1" else {
            return nil
        }

        // Development fallback only. Packaged releases must include app-owned helpers
        // in Contents/Resources/Helpers or Application Support/Majordomo/Helpers.
        let candidates: [String]
        switch kind {
        case .whisperCLI:
            candidates = ["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"]
        case .whisperDictate:
            candidates = []
        }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }
}
