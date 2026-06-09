import Foundation

struct LaunchAtLoginManager {
    private let fileManager = FileManager.default

    var isEnabled: Bool {
        guard let launchAgentURL else { return false }
        return fileManager.fileExists(atPath: launchAgentURL.path)
    }

    func setEnabled(_ enabled: Bool) throws {
        guard let launchAgentURL else {
            throw LaunchAtLoginError.missingBundleIdentifier
        }

        if enabled {
            try enable(using: launchAgentURL)
        } else {
            try disable(using: launchAgentURL)
        }
    }

    private var launchAgentURL: URL? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return nil }
        let launchAgentsDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
        return launchAgentsDirectory.appendingPathComponent("\(bundleIdentifier).plist")
    }

    private var appBundlePath: String? {
        let path = Bundle.main.bundlePath
        return path.hasSuffix(".app") ? path : nil
    }

    private func enable(using launchAgentURL: URL) throws {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            throw LaunchAtLoginError.missingBundleIdentifier
        }
        guard let appBundlePath else {
            throw LaunchAtLoginError.notRunningFromAppBundle
        }

        try fileManager.createDirectory(
            at: launchAgentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let plist: [String: Any] = [
            "Label": bundleIdentifier,
            "ProgramArguments": ["/usr/bin/open", "-a", appBundlePath],
            "RunAtLoad": true
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: launchAgentURL, options: .atomic)

        try runLaunchctl(arguments: ["unload", launchAgentURL.path], allowFailure: true)
        try runLaunchctl(arguments: ["load", launchAgentURL.path])
    }

    private func disable(using launchAgentURL: URL) throws {
        guard fileManager.fileExists(atPath: launchAgentURL.path) else { return }
        try runLaunchctl(arguments: ["unload", launchAgentURL.path], allowFailure: true)
        try fileManager.removeItem(at: launchAgentURL)
    }

    @discardableResult
    private func runLaunchctl(arguments: [String], allowFailure: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combinedOutput = [output, errorOutput]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")

        if process.terminationStatus != 0 && !allowFailure {
            throw LaunchAtLoginError.launchctlFailed(combinedOutput.isEmpty ? "exit \(process.terminationStatus)" : combinedOutput)
        }

        return combinedOutput
    }
}

enum LaunchAtLoginError: LocalizedError {
    case missingBundleIdentifier
    case notRunningFromAppBundle
    case launchctlFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBundleIdentifier:
            return L10n.text("error.launch.missing_bundle")
        case .notRunningFromAppBundle:
            return L10n.text("error.launch.not_app_bundle")
        case .launchctlFailed(let message):
            return L10n.text("error.launch.launchctl_failed", message)
        }
    }
}
