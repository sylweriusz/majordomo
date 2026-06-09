import AppKit

struct SettingsTheme {
    static var backgroundStart: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: "#1a1a2e")
                : NSColor(hex: "#f0ece4")
        }
    }

    static var backgroundEnd: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: "#2d1b4e")
                : NSColor(hex: "#e6dfd3")
        }
    }

    static var cardFill: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.08)
                : NSColor.white.withAlphaComponent(0.55)
        }
    }

    static var cardStroke: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor.black.withAlphaComponent(0.10)
        }
    }

    static var accent: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: "#0077b6")
                : NSColor(hex: "#97a7d6")
        }
    }

    static var noteText: NSColor {
        NSColor.secondaryLabelColor
    }

    /// Translucent fill for editable fields (e.g. the transcript editor) so they
    /// read as a field but sit on the gradient instead of a flat white/gray box.
    static var fieldFill: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.black.withAlphaComponent(0.28)
                : NSColor.white.withAlphaComponent(0.6)
        }
    }

    @MainActor
    static func makeSectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        return label
    }

    @MainActor
    static func makeHintLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = noteText
        label.font = .systemFont(ofSize: 12)
        return label
    }
}

final class SettingsBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let gradient = NSGradient(colors: [SettingsTheme.backgroundStart, SettingsTheme.backgroundEnd]) else {
            return
        }
        gradient.draw(in: bounds, angle: 90)
    }
}

final class SettingsCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        layer?.backgroundColor = SettingsTheme.cardFill.cgColor
        layer?.borderColor = SettingsTheme.cardStroke.cgColor
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xff, (int >> 8) & 0xff, int & 0xff)
        default:
            (r, g, b) = (0, 0, 0)
        }

        self.init(
            calibratedRed: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1
        )
    }
}
