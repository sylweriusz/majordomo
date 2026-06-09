import AppKit

@MainActor
final class AboutWindowController: NSWindowController {
    private let textView = NSTextView()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("about.window_title")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 420)
        super.init(window: window)
        configureContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        applyAboutText()
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
    }

    func reloadLocalizedText() {
        guard let window else { return }
        window.title = L10n.text("about.window_title")
        applyAboutText()
        if let contentView = window.contentView {
            for view in contentView.subviews {
                view.removeFromSuperview()
            }
            configureContent()
        }
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let backgroundView = SettingsBackgroundView(frame: contentView.bounds)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backgroundView)

        let headerLabel = NSTextField(labelWithString: "Majordomo")
        headerLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = SettingsTheme.makeHintLabel(L10n.text("about.subtitle"))
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let card = SettingsCardView(frame: .zero)
        card.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        applyAboutText()

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(scrollView)
        contentView.addSubview(headerLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(card)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            headerLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            headerLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),

            subtitleLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),

            card.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

            scrollView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            scrollView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            scrollView.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            scrollView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
    }

    private func applyAboutText() {
        textView.textStorage?.setAttributedString(Self.attributedAboutText())
    }

    /// Renders the plain about text with a proportional font: lines that the
    /// source underlines with dashes become bold section headers, and the dash
    /// rules themselves are dropped (no more monospaced ASCII-art look).
    private static func attributedAboutText() -> NSAttributedString {
        let bodyFont = NSFont.systemFont(ofSize: 13)
        let headerFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 6

        let lines = aboutText().components(separatedBy: "\n")
        let result = NSMutableAttributedString()
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let isRule = !line.isEmpty && line.allSatisfy { $0 == "-" }
            if isRule { index += 1; continue }

            let nextIsRule = index + 1 < lines.count
                && !lines[index + 1].isEmpty
                && lines[index + 1].allSatisfy { $0 == "-" }

            result.append(NSAttributedString(string: line + "\n", attributes: [
                .font: nextIsRule ? headerFont : bodyFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]))
            index += 1
        }
        return result
    }

    private static func aboutText() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info["CFBundleVersion"] as? String ?? "dev"
        let notices = thirdPartyNotices()
        return L10n.text("about.text", version, build, notices)
    }

    private static func thirdPartyNotices() -> String {
        let url = Bundle.appResourceURL(forResource: "ThirdPartyNotices", withExtension: "txt")

        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            return L10n.text("about.notices_unavailable")
        }
        return text
    }
}
