import AppKit
import MajordomoCore
import UniformTypeIdentifiers

@MainActor
final class AudioFileTranscriptionWindowController: NSWindowController, NSWindowDelegate {
    typealias TranscribeHandler = @MainActor (URL, TranscriptionBackendKind, String) async throws -> TranscriptionResult
    typealias ModelSelectionHandler = @MainActor (TranscriptionBackendKind) -> Void

    private let transcribeHandler: TranscribeHandler
    private let modelSelectionHandler: ModelSelectionHandler
    private var selectedAudioURL: URL?
    private var selectedBackend: TranscriptionBackendKind
    private var selectedLanguage: String
    private var transcriptionTask: Task<Void, Never>?

    private let fileLabel = NSTextField(labelWithString: L10n.text("panel.no_audio_file"))
    private let statusLabel = SettingsTheme.makeHintLabel(L10n.text("panel.default_status"))
    private let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let chooseButton = NSButton(title: L10n.text("panel.choose_button"), target: nil, action: nil)
    private let transcribeButton = NSButton(title: L10n.text("panel.transcribe_button"), target: nil, action: nil)
    private let copyButton = NSButton(title: L10n.text("panel.copy_button"), target: nil, action: nil)
    private let saveButton = NSButton(title: L10n.text("panel.save_button"), target: nil, action: nil)
    private let progressIndicator = NSProgressIndicator()
    private let textView = NSTextView()

    init(
        initialBackend: TranscriptionBackendKind,
        initialLanguage: String,
        transcribeHandler: @escaping TranscribeHandler,
        modelSelectionHandler: @escaping ModelSelectionHandler
    ) {
        self.selectedBackend = initialBackend
        self.selectedLanguage = initialLanguage
        self.transcribeHandler = transcribeHandler
        self.modelSelectionHandler = modelSelectionHandler
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("panel.window_title")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 540, height: 420)
        super.init(window: window)
        window.delegate = self
        configureContent()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        transcriptionTask?.cancel()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
        refreshIdleStatus()
        setTranscribing(false)
    }

    func windowWillClose(_ notification: Notification) {
        cancelTranscriptionIfNeeded()
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let backgroundView = SettingsBackgroundView(frame: contentView.bounds)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backgroundView)

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        // Header
        let headerLabel = NSTextField(labelWithString: L10n.text("panel.window_title"))
        headerLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        root.addArrangedSubview(headerLabel)

        // Card
        let card = SettingsCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        let cardStack = NSStackView()
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 12
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)

        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureModelPopup()
        configureLanguagePopup()

        chooseButton.target = self
        chooseButton.action = #selector(chooseAudioFile)

        transcribeButton.target = self
        transcribeButton.action = #selector(transcribeSelectedAudioFile)
        transcribeButton.isEnabled = false

        copyButton.target = self
        copyButton.action = #selector(copyText)
        copyButton.isEnabled = false

        saveButton.target = self
        saveButton.action = #selector(saveText)
        saveButton.isEnabled = false

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false

        let modelRow = makeRow(label: L10n.text("panel.model_label"), control: modelPopup)
        let languageRow = makeRow(label: L10n.text("panel.spoken_language_label"), control: languagePopup)
        let buttonRow = NSStackView(views: [chooseButton, transcribeButton, copyButton, saveButton, progressIndicator])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.drawsBackground = true
        textView.backgroundColor = SettingsTheme.fieldFill
        textView.string = ""
        textView.textContainerInset = NSSize(width: 10, height: 10)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        cardStack.addArrangedSubview(fileLabel)
        cardStack.addArrangedSubview(statusLabel)
        cardStack.addArrangedSubview(modelRow)
        cardStack.addArrangedSubview(languageRow)
        cardStack.addArrangedSubview(buttonRow)
        cardStack.addArrangedSubview(scrollView)

        root.addArrangedSubview(card)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

            card.widthAnchor.constraint(equalTo: root.widthAnchor),

            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            cardStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),

            fileLabel.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])
    }

    private func makeRow(label: String, control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: label)
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let row = NSStackView(views: [titleLabel, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    func updateSelectedBackend(_ backend: TranscriptionBackendKind) {
        selectedBackend = backend
        selectModelPopupItem(for: backend)
    }

    func updateSelectedLanguage(_ language: String) {
        selectedLanguage = language
        selectLanguagePopupItem(for: language)
    }

    func reloadLocalizedText() {
        window?.title = L10n.text("panel.window_title")
        fileLabel.stringValue = selectedAudioURL?.path ?? L10n.text("panel.no_audio_file")
        chooseButton.title = selectedAudioURL == nil ? L10n.text("panel.choose_button") : L10n.text("panel.choose_another_button")
        transcribeButton.title = transcriptionTask == nil ? L10n.text("panel.transcribe_button") : L10n.text("panel.cancel_button")
        copyButton.title = L10n.text("panel.copy_button")
        saveButton.title = L10n.text("panel.save_button")
        configureModelPopup()
        configureLanguagePopup()
        refreshIdleStatus()
    }

    private func configureModelPopup() {
        modelPopup.removeAllItems()
        for backend in TranscriptionBackendKind.allCases {
            let item = NSMenuItem(title: "\(backend.shortDisplayName) — \(backend.menuDescription)", action: nil, keyEquivalent: "")
            item.representedObject = backend
            modelPopup.menu?.addItem(item)
        }
        modelPopup.target = self
        modelPopup.action = #selector(selectModel(_:))
        selectModelPopupItem(for: selectedBackend)
    }

    private func configureLanguagePopup() {
        languagePopup.removeAllItems()
        for option in PanelTranscriptionLanguageOption.allCases {
            let item = NSMenuItem(title: option.displayName, action: nil, keyEquivalent: "")
            item.representedObject = option.code
            languagePopup.menu?.addItem(item)
        }
        languagePopup.target = self
        languagePopup.action = #selector(selectLanguage(_:))
        selectLanguagePopupItem(for: selectedLanguage)
    }

    private func selectModelPopupItem(for backend: TranscriptionBackendKind) {
        guard let items = modelPopup.menu?.items else { return }
        for item in items where item.representedObject as? TranscriptionBackendKind == backend {
            modelPopup.select(item)
            return
        }
    }

    private func selectLanguagePopupItem(for language: String) {
        guard let items = languagePopup.menu?.items else { return }
        for item in items where item.representedObject as? String == language {
            languagePopup.select(item)
            return
        }
        languagePopup.selectItem(at: 0)
    }

    @objc private func selectModel(_ sender: NSPopUpButton) {
        guard let backend = sender.selectedItem?.representedObject as? TranscriptionBackendKind else { return }
        selectedBackend = backend
        modelSelectionHandler(backend)
        refreshIdleStatus(extra: L10n.text("panel.model_set", backend.shortDisplayName))
    }

    @objc private func selectLanguage(_ sender: NSPopUpButton) {
        guard let language = sender.selectedItem?.representedObject as? String else { return }
        selectedLanguage = language
        refreshIdleStatus(extra: L10n.text("panel.language_set", PanelTranscriptionLanguageOption.displayName(for: language)))
    }

    @objc private func chooseAudioFile() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("panel.choose_dialog_title")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = SupportedAudioFile.sortedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard SupportedAudioFile.isSupported(url) else {
            showError(L10n.text("panel.unsupported_audio", url.pathExtension))
            return
        }

        selectedAudioURL = url
        fileLabel.stringValue = url.path
        refreshIdleStatus(extra: L10n.text("panel.file_selected"))
        setTranscribing(false)
    }

    @objc private func transcribeSelectedAudioFile() {
        startTranscription()
    }

    @objc private func cancelTranscription() {
        cancelTranscriptionIfNeeded(userInitiated: true)
    }

    @objc private func copyText() {
        let selectedRange = textView.selectedRange()
        let text: String
        if selectedRange.length > 0, let range = Range(selectedRange, in: textView.string) {
            text = String(textView.string[range])
        } else {
            text = textView.string
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusLabel.stringValue = selectedRange.length > 0 ? L10n.text("panel.copied_selected") : L10n.text("panel.copied_transcript")
    }

    @objc private func saveText() {
        let text = textView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }

        let panel = NSSavePanel()
        panel.title = L10n.text("panel.save_title")
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = defaultTranscriptFileName()

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            statusLabel.stringValue = L10n.text("panel.saved", url.lastPathComponent)
        } catch {
            showError(L10n.text("panel.save_failed", error.localizedDescription))
        }
    }

    private func startTranscription() {
        guard let selectedAudioURL else {
            showError(L10n.text("panel.choose_first"))
            return
        }

        transcriptionTask?.cancel()
        setTranscribing(true)
        statusLabel.stringValue = L10n.text("panel.transcribing", selectedAudioURL.lastPathComponent, selectedBackend.shortDisplayName, PanelTranscriptionLanguageOption.displayName(for: selectedLanguage))

        transcriptionTask = Task { @MainActor in
            do {
                let result = try await transcribeHandler(selectedAudioURL, selectedBackend, selectedLanguage)
                try Task.checkCancellation()
                textView.string = result.text
                statusLabel.stringValue = L10n.text("panel.transcribed", selectedBackend.shortDisplayName, result.duration)
                copyButton.isEnabled = !result.text.isEmpty
                saveButton.isEnabled = !result.text.isEmpty
            } catch is CancellationError {
                refreshIdleStatus(extra: L10n.text("panel.transcription_canceled"))
            } catch {
                showError(error.localizedDescription)
            }
            setTranscribing(false)
            transcriptionTask = nil
        }
    }

    private func cancelTranscriptionIfNeeded(userInitiated: Bool = false) {
        guard transcriptionTask != nil else { return }
        transcriptionTask?.cancel()
        transcriptionTask = nil
        setTranscribing(false)
        if userInitiated {
            refreshIdleStatus(extra: L10n.text("panel.transcription_canceled"))
        }
    }

    private func setTranscribing(_ isTranscribing: Bool) {
        modelPopup.isEnabled = !isTranscribing
        languagePopup.isEnabled = !isTranscribing
        chooseButton.isEnabled = !isTranscribing
        chooseButton.title = selectedAudioURL == nil ? L10n.text("panel.choose_button") : L10n.text("panel.choose_another_button")
        transcribeButton.title = isTranscribing ? L10n.text("panel.cancel_button") : L10n.text("panel.transcribe_button")
        transcribeButton.action = isTranscribing ? #selector(cancelTranscription) : #selector(transcribeSelectedAudioFile)
        transcribeButton.isEnabled = isTranscribing || selectedAudioURL != nil
        copyButton.isEnabled = !isTranscribing && !textView.string.isEmpty
        saveButton.isEnabled = !isTranscribing && !textView.string.isEmpty
        if isTranscribing {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
    }

    private func refreshIdleStatus(extra: String? = nil) {
        let base = selectedAudioURL == nil
            ? L10n.text("panel.default_status")
            : L10n.text("panel.ready_to_transcribe", selectedAudioURL?.lastPathComponent ?? L10n.text("common.audio_file"), selectedBackend.shortDisplayName, PanelTranscriptionLanguageOption.displayName(for: selectedLanguage))
        statusLabel.stringValue = [extra, base].compactMap { $0 }.joined(separator: extra == nil ? "" : " ")
    }

    private func showError(_ message: String) {
        statusLabel.stringValue = message
        NSSound.beep()
    }

    private func defaultTranscriptFileName() -> String {
        let base = selectedAudioURL?.deletingPathExtension().lastPathComponent ?? L10n.text("panel.transcript_default_name")
        return "\(base).txt"
    }
}

private struct PanelTranscriptionLanguageOption: CaseIterable {
    let code: String
    let displayName: String

    static let allCases: [PanelTranscriptionLanguageOption] = [
        PanelTranscriptionLanguageOption(code: "auto", displayName: "🌐 Auto"),
        PanelTranscriptionLanguageOption(code: "en", displayName: "🇬🇧 English"),
        PanelTranscriptionLanguageOption(code: "pl", displayName: "🇵🇱 Polski"),
        PanelTranscriptionLanguageOption(code: "de", displayName: "🇩🇪 Deutsch"),
        PanelTranscriptionLanguageOption(code: "fr", displayName: "🇫🇷 Français"),
        PanelTranscriptionLanguageOption(code: "es", displayName: "🇪🇸 Español"),
        PanelTranscriptionLanguageOption(code: "it", displayName: "🇮🇹 Italiano"),
        PanelTranscriptionLanguageOption(code: "pt", displayName: "🇵🇹 Português"),
        PanelTranscriptionLanguageOption(code: "nl", displayName: "🇳🇱 Nederlands"),
        PanelTranscriptionLanguageOption(code: "uk", displayName: "🇺🇦 Українська"),
        PanelTranscriptionLanguageOption(code: "ru", displayName: "🗣️ Русский"),
        PanelTranscriptionLanguageOption(code: "cs", displayName: "🇨🇿 Čeština"),
        PanelTranscriptionLanguageOption(code: "sk", displayName: "🇸🇰 Slovenčina"),
        PanelTranscriptionLanguageOption(code: "sl", displayName: "🇸🇮 Slovenščina"),
        PanelTranscriptionLanguageOption(code: "hr", displayName: "🇭🇷 Hrvatski"),
        PanelTranscriptionLanguageOption(code: "sr", displayName: "🇷🇸 Српски"),
        PanelTranscriptionLanguageOption(code: "bg", displayName: "🇧🇬 Български"),
        PanelTranscriptionLanguageOption(code: "ro", displayName: "🇷🇴 Română"),
        PanelTranscriptionLanguageOption(code: "hu", displayName: "🇭🇺 Magyar"),
        PanelTranscriptionLanguageOption(code: "el", displayName: "🇬🇷 Ελληνικά"),
        PanelTranscriptionLanguageOption(code: "tr", displayName: "🇹🇷 Türkçe"),
        PanelTranscriptionLanguageOption(code: "da", displayName: "🇩🇰 Dansk"),
        PanelTranscriptionLanguageOption(code: "sv", displayName: "🇸🇪 Svenska"),
        PanelTranscriptionLanguageOption(code: "no", displayName: "🇳🇴 Norsk"),
        PanelTranscriptionLanguageOption(code: "fi", displayName: "🇫🇮 Suomi"),
        PanelTranscriptionLanguageOption(code: "et", displayName: "🇪🇪 Eesti"),
        PanelTranscriptionLanguageOption(code: "lv", displayName: "🇱🇻 Latviešu"),
        PanelTranscriptionLanguageOption(code: "lt", displayName: "🇱🇹 Lietuvių"),
        PanelTranscriptionLanguageOption(code: "ca", displayName: "🏴 Català"),
        PanelTranscriptionLanguageOption(code: "eu", displayName: "🏴 Euskara"),
        PanelTranscriptionLanguageOption(code: "gl", displayName: "🏴 Galego"),
        PanelTranscriptionLanguageOption(code: "ga", displayName: "🇮🇪 Gaeilge"),
        PanelTranscriptionLanguageOption(code: "cy", displayName: "🏴 Cymraeg"),
        PanelTranscriptionLanguageOption(code: "ar", displayName: "🇸🇦 العربية"),
        PanelTranscriptionLanguageOption(code: "he", displayName: "🇮🇱 עברית"),
        PanelTranscriptionLanguageOption(code: "hi", displayName: "🇮🇳 हिन्दी"),
        PanelTranscriptionLanguageOption(code: "zh", displayName: "🇨🇳 中文"),
        PanelTranscriptionLanguageOption(code: "ja", displayName: "🇯🇵 日本語"),
        PanelTranscriptionLanguageOption(code: "ko", displayName: "🇰🇷 한국어"),
        PanelTranscriptionLanguageOption(code: "vi", displayName: "🇻🇳 Tiếng Việt"),
        PanelTranscriptionLanguageOption(code: "id", displayName: "🇮🇩 Bahasa Indonesia")
    ]

    static func displayName(for code: String) -> String {
        allCases.first { $0.code == code }?.displayName ?? code
    }
}
