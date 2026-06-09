import os

/// Centralized logging for Majordomo.
///
/// Privacy posture: the app never logs transcript text or audio. Operational
/// lifecycle traces (recording started/stopped, settings changed, which app
/// text was inserted into) go through ``info`` at the unified log's `.debug`
/// level, which is **ephemeral** — captured only during live debugging, never
/// written to disk. Only ``error`` uses a persisted level, so a production
/// install leaves no on-disk activity trail while still surfacing failures for
/// diagnosis.
enum AppLog {
    private static let logger = Logger(subsystem: "pl.wild-matrix.majordomo", category: "app")

    /// Ephemeral diagnostic trace (not persisted to disk).
    static func info(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    /// Persisted error trace.
    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
