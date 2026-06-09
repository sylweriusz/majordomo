import Foundation

public enum SupportedAudioFile {
    public static let supportedExtensions: Set<String> = [
        "aac",
        "aif",
        "aiff",
        "alac",
        "caf",
        "m4a",
        "m4b",
        "mp3",
        "mp4",
        "wav",
        "wave"
    ]

    public static var sortedExtensions: [String] {
        supportedExtensions.sorted()
    }

    public static func isSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }
}
