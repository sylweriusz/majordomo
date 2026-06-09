import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private weak var appDelegate: AppDelegate?
    private var isRefreshing = false

    private let appLanguagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let hotkeyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let customHotkeyButton = NSButton(title: "", target: nil, action: nil)
    private let launchAtLoginButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let privacyNoteLabel = SettingsTheme.makeHintLabel("")
    private let aboutButton = NSButton(title: "", target: nil, action: nil)

    private let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let modelStatusLabel = SettingsTheme.makeHintLabel("")
    private let modelActionButton = NSButton(title: "", target: nil, action: nil)
    private let whisperCliStatusLabel = SettingsTheme.makeHintLabel("")
    private let whisperDictateStatusLabel = SettingsTheme.makeHintLabel("")
    private let spokenLanguagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let soundPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let insertionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let transcribeAudioFileButton = NSButton(title: "", target: nil, action: nil)

    private let indicatorEnabledButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let indicatorStylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let indicatorPalettePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let indicatorPlacementPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let indicatorPreview = WaveformOverlayView()

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("settings.window_title")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 620, height: 440)
        super.init(window: window)
        window.delegate = self
        configureContent()
        reloadLocalizedText()
        refreshFromAppState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        refreshFromAppState()
        indicatorPreview.startAnimating(mode: .recording)
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        indicatorPreview.stopAnimating()
        sender.orderOut(nil)
        return false
    }

    func reloadLocalizedText() {
        window?.title = L10n.text("settings.window_title")
        customHotkeyButton.title = L10n.text("settings.custom_hotkey_button")
        launchAtLoginButton.title = L10n.text("settings.launch_at_login_label")
        privacyNoteLabel.stringValue = L10n.text("settings.privacy_note")
        aboutButton.title = L10n.text("settings.about_button")
        transcribeAudioFileButton.title = L10n.text("settings.transcribe_audio_file_button")
        indicatorEnabledButton.title = L10n.text("settings.show_indicator_label")
        configureAppLanguagePopup()
        configureHotkeyPopup()
        configureModelPopup()
        configureSpokenLanguagePopup()
        configureSoundPopup()
        configureInsertionPopup()
        configureIndicatorPopups()
    }

    func refreshFromAppState() {
        guard let appDelegate else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        selectPopupItem(appLanguagePopup, representedObject: appDelegate.currentAppLanguagePreference.rawValue)
        selectHotkeyPopup(keyCode: appDelegate.currentHotkeyKeyCode, modifiers: appDelegate.currentHotkeyModifiers)
        launchAtLoginButton.state = appDelegate.isLaunchAtLoginEnabled() ? .on : .off

        selectPopupItem(modelPopup, representedObject: appDelegate.currentBackendKind.rawValue)
        let modelStatus = appDelegate.modelStatus(for: appDelegate.currentBackendKind)
        modelStatusLabel.stringValue = "\(L10n.text("settings.model_status_label")): \(modelStatus.title)"
        modelStatusLabel.isHidden = false
        switch modelStatus {
        case .ready:
            modelActionButton.title = L10n.text("settings.delete_model")
            modelActionButton.isHidden = false
        case .downloading:
            modelActionButton.title = L10n.text("settings.cancel_download")
            modelActionButton.isHidden = false
        case .missing, .error:
            modelActionButton.isHidden = true
        }

        let cliReady = appDelegate.runtimeStatus(for: .whisperCLI).isReady
        let dictateReady = appDelegate.runtimeStatus(for: .whisperDictate).isReady
        if cliReady && dictateReady {
            whisperCliStatusLabel.isHidden = true
            whisperDictateStatusLabel.isHidden = true
        } else {
            whisperCliStatusLabel.stringValue = whisperCliStatusText()
            whisperCliStatusLabel.isHidden = false
            whisperDictateStatusLabel.stringValue = whisperDictateStatusText()
            whisperDictateStatusLabel.isHidden = false
        }

        selectPopupItem(spokenLanguagePopup, representedObject: appDelegate.currentLanguage)
        selectPopupItem(soundPopup, representedObject: appDelegate.currentSoundProfile.rawValue)
        selectPopupItem(insertionPopup, representedObject: appDelegate.currentInsertionStrategy.rawValue)

        indicatorEnabledButton.state = appDelegate.isIndicatorEnabled ? .on : .off
        selectPopupItem(indicatorStylePopup, representedObject: appDelegate.currentIndicatorVisualStyle.rawValue)
        selectPopupItem(indicatorPalettePopup, representedObject: appDelegate.currentIndicatorColorPalette.rawValue)
        selectPopupItem(indicatorPlacementPopup, representedObject: appDelegate.currentIndicatorPlacement.rawValue)

        // Live preview of the chosen style + palette; dim and disable when off.
        let indicatorOn = appDelegate.isIndicatorEnabled
        indicatorPreview.visualStyle = appDelegate.currentIndicatorVisualStyle
        indicatorPreview.colorPalette = appDelegate.currentIndicatorColorPalette
        indicatorPreview.alphaValue = indicatorOn ? 1 : 0.3
        indicatorStylePopup.isEnabled = indicatorOn
        indicatorPalettePopup.isEnabled = indicatorOn
        indicatorPlacementPopup.isEnabled = indicatorOn
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let backgroundView = SettingsBackgroundView(frame: contentView.bounds)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backgroundView)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        // Flipped so that when the content is shorter than the window, it pins to
        // the TOP (a plain NSView document sticks short content to the bottom,
        // leaving an empty gap above the header).
        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 16
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)

        // Two columns sized to balance height and fit the panel on screen without
        // scrolling. The wider left column holds General + Dictation (so the long
        // model-picker title isn't truncated); the narrower right column holds
        // Appearance. This is the most even split of the three cards.
        let general = makeGeneralCard()
        let dictation = makeDictationCard()
        let appearance = makeAppearanceCard()
        general.widthAnchor.constraint(equalToConstant: 470).isActive = true
        dictation.widthAnchor.constraint(equalToConstant: 470).isActive = true
        appearance.widthAnchor.constraint(equalToConstant: 380).isActive = true

        let leftColumn = NSStackView(views: [general, dictation])
        leftColumn.orientation = .vertical
        leftColumn.alignment = .leading
        leftColumn.spacing = 16

        let rightColumn = NSStackView(views: [appearance])
        rightColumn.orientation = .vertical
        rightColumn.alignment = .leading
        rightColumn.spacing = 16

        let columns = NSStackView(views: [leftColumn, rightColumn])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.spacing = 20

        // Equal-height columns: stretch the shorter Appearance card so both columns
        // bottom-align — no gap between it and the footer.
        appearance.heightAnchor.constraint(equalTo: leftColumn.heightAnchor).isActive = true

        stack.addArrangedSubview(makeHeaderView())
        stack.addArrangedSubview(columns)
        stack.addArrangedSubview(makeFooterBar())

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -20)
        ])

        // Size the window to exactly fit the content: equal 20px margins all around,
        // footer flush to the bottom, no empty band below the buttons or on the right.
        documentView.layoutSubtreeIfNeeded()
        let contentSize = stack.fittingSize
        window?.setContentSize(NSSize(width: contentSize.width + 40, height: contentSize.height + 40))
    }

    private func makeHeaderView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        let titleLabel = NSTextField(labelWithString: "Majordomo")
        titleLabel.font = .systemFont(ofSize: 28, weight: .semibold)

        stack.addArrangedSubview(titleLabel)
        return stack
    }

    private func makeGeneralCard() -> NSView {
        let card = makeCard(sectionTitle: L10n.text("settings.section_general"))
        let stack = card.subviews[0] as! NSStackView

        configureAppLanguagePopup()
        configureHotkeyPopup()

        customHotkeyButton.target = self
        customHotkeyButton.action = #selector(openCustomHotkey)

        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(toggleLaunchAtLogin)

        aboutButton.target = self
        aboutButton.action = #selector(showAbout)

        stack.addArrangedSubview(makeLabeledRow(label: L10n.text("settings.app_language_label"), control: appLanguagePopup))
        stack.addArrangedSubview(makeHotkeyRow())
        stack.addArrangedSubview(launchAtLoginButton)
        stack.addArrangedSubview(privacyNoteLabel)
        return card
    }

    private func makeDictationCard() -> NSView {
        let card = makeCard(sectionTitle: L10n.text("settings.section_dictation"))
        let stack = card.subviews[0] as! NSStackView

        configureModelPopup()
        configureSpokenLanguagePopup()
        configureSoundPopup()
        configureInsertionPopup()

        modelActionButton.bezelStyle = .rounded
        modelActionButton.controlSize = .small
        modelActionButton.target = self
        modelActionButton.action = #selector(modelActionTapped)
        let modelStatusRow = NSStackView(views: [modelStatusLabel, NSView(), modelActionButton])
        modelStatusRow.orientation = .horizontal
        modelStatusRow.alignment = .centerY
        modelStatusRow.spacing = 8

        stack.addArrangedSubview(makeLabeledRow(label: L10n.text("settings.whisper_model_label"), control: modelPopup))
        stack.addArrangedSubview(modelStatusRow)
        stack.addArrangedSubview(whisperCliStatusLabel)
        stack.addArrangedSubview(whisperDictateStatusLabel)
        stack.addArrangedSubview(makeLabeledRow(label: L10n.text("panel.spoken_language_label"), control: spokenLanguagePopup))
        stack.addArrangedSubview(makeLabeledRow(label: L10n.text("settings.dictation_sound_label"), control: soundPopup))
        stack.addArrangedSubview(makeLabeledRow(label: L10n.text("settings.insertion_method_label"), control: insertionPopup))
        return card
    }

    private func makeAppearanceCard() -> NSView {
        let card = makeCard(sectionTitle: L10n.text("settings.section_appearance"))
        let stack = card.subviews[0] as! NSStackView

        configureIndicatorPopups()

        indicatorEnabledButton.target = self
        indicatorEnabledButton.action = #selector(toggleIndicator)

        indicatorPreview.translatesAutoresizingMaskIntoConstraints = false
        indicatorPreview.widthAnchor.constraint(equalToConstant: 280).isActive = true
        indicatorPreview.heightAnchor.constraint(equalToConstant: 48).isActive = true

        stack.addArrangedSubview(indicatorEnabledButton)
        stack.addArrangedSubview(indicatorPreview)
        stack.addArrangedSubview(makeLabeledRow(label: L10n.text("settings.indicator_style_label"), control: indicatorStylePopup))
        stack.addArrangedSubview(makeLabeledRow(label: L10n.text("settings.indicator_palette_label"), control: indicatorPalettePopup))
        stack.addArrangedSubview(makeLabeledRow(label: L10n.text("settings.indicator_placement_label"), control: indicatorPlacementPopup))
        return card
    }

    private func makeFooterBar() -> NSView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.distribution = .equalSpacing

        aboutButton.bezelStyle = .rounded
        aboutButton.target = self
        aboutButton.action = #selector(showAbout)

        transcribeAudioFileButton.bezelStyle = .rounded
        transcribeAudioFileButton.target = self
        transcribeAudioFileButton.action = #selector(openAudioFileTranscription)

        bar.addArrangedSubview(aboutButton)
        bar.addArrangedSubview(transcribeAudioFileButton)

        bar.widthAnchor.constraint(equalToConstant: 870).isActive = true
        return bar
    }

    private func makeCard(sectionTitle: String) -> SettingsCardView {
        let card = SettingsCardView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        stack.addArrangedSubview(SettingsTheme.makeSectionTitle(sectionTitle))

        // Content pins to the top; the bottom is `<=` so a card can be made taller
        // than its content (to match the other column's height) without stretching
        // the rows apart. Width is set by the caller per column.
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -18)
        ])

        return card
    }

    private func makeLabeledRow(label: String, control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: label)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let row = NSStackView(views: [titleLabel, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func makeHotkeyRow() -> NSView {
        let titleLabel = NSTextField(labelWithString: L10n.text("settings.hotkey_label"))
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let controls = NSStackView(views: [hotkeyPopup, customHotkeyButton])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8

        let row = NSStackView(views: [titleLabel, controls])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func configureAppLanguagePopup() {
        appLanguagePopup.removeAllItems()
        for language in AppUILanguage.allCases {
            let item = NSMenuItem(title: language.displayName, action: nil, keyEquivalent: "")
            item.representedObject = language.rawValue
            appLanguagePopup.menu?.addItem(item)
        }
        appLanguagePopup.target = self
        appLanguagePopup.action = #selector(selectAppLanguage)
    }

    private func configureHotkeyPopup() {
        hotkeyPopup.removeAllItems()
        // First item: always show the current hotkey label
        guard let appDelegate else { return }
        let currentLabel = appDelegate.hotkeyDisplayName
        let currentItem = NSMenuItem(title: currentLabel, action: nil, keyEquivalent: "")
        currentItem.isEnabled = false
        currentItem.representedObject = [appDelegate.currentHotkeyKeyCode, appDelegate.currentHotkeyModifiers]
        hotkeyPopup.menu?.addItem(currentItem)
        hotkeyPopup.menu?.addItem(.separator())

        for preset in HotkeyPreset.all {
            let item = NSMenuItem(title: preset.label, action: nil, keyEquivalent: "")
            item.representedObject = [preset.keyCode, preset.modifiers]
            item.indentationLevel = 1
            hotkeyPopup.menu?.addItem(item)
        }
        hotkeyPopup.target = self
        hotkeyPopup.action = #selector(selectHotkey)
    }

    private func configureModelPopup() {
        modelPopup.removeAllItems()
        for backend in TranscriptionBackendKind.allCases {
            // Show size · speed · accuracy so the choice (and download size) is informed.
            let item = NSMenuItem(title: "\(backend.shortDisplayName) — \(backend.menuDescription)", action: nil, keyEquivalent: "")
            item.representedObject = backend.rawValue
            modelPopup.menu?.addItem(item)
        }
        modelPopup.target = self
        modelPopup.action = #selector(selectModel)
    }

    private func configureSpokenLanguagePopup() {
        spokenLanguagePopup.removeAllItems()
        for option in TranscriptionLanguageOption.allCases {
            let item = NSMenuItem(title: option.displayName, action: nil, keyEquivalent: "")
            item.representedObject = option.code
            spokenLanguagePopup.menu?.addItem(item)
        }
        spokenLanguagePopup.target = self
        spokenLanguagePopup.action = #selector(selectSpokenLanguage)
    }

    private func configureSoundPopup() {
        soundPopup.removeAllItems()
        for profile in DictationSoundProfile.allCases {
            let item = NSMenuItem(title: profile.displayName, action: nil, keyEquivalent: "")
            item.representedObject = profile.rawValue
            soundPopup.menu?.addItem(item)
        }
        soundPopup.target = self
        soundPopup.action = #selector(selectSoundProfile)
    }

    private func configureInsertionPopup() {
        insertionPopup.removeAllItems()
        for strategy in TextInsertionStrategy.allCases {
            let item = NSMenuItem(title: strategy.displayName, action: nil, keyEquivalent: "")
            item.representedObject = strategy.rawValue
            insertionPopup.menu?.addItem(item)
        }
        insertionPopup.target = self
        insertionPopup.action = #selector(selectInsertionStrategy)
    }

    private func configureIndicatorPopups() {
        indicatorStylePopup.removeAllItems()
        for style in IndicatorVisualStyle.allCases {
            let item = NSMenuItem(title: style.displayName, action: nil, keyEquivalent: "")
            item.representedObject = style.rawValue
            indicatorStylePopup.menu?.addItem(item)
        }
        indicatorStylePopup.target = self
        indicatorStylePopup.action = #selector(selectIndicatorStyle)

        indicatorPalettePopup.removeAllItems()
        for palette in IndicatorColorPalette.allCases {
            let item = NSMenuItem(title: palette.displayName, action: nil, keyEquivalent: "")
            item.representedObject = palette.rawValue
            indicatorPalettePopup.menu?.addItem(item)
        }
        indicatorPalettePopup.target = self
        indicatorPalettePopup.action = #selector(selectIndicatorPalette)

        indicatorPlacementPopup.removeAllItems()
        for placement in IndicatorPlacement.allCases {
            let item = NSMenuItem(title: placement.displayName, action: nil, keyEquivalent: "")
            item.representedObject = placement.rawValue
            indicatorPlacementPopup.menu?.addItem(item)
        }
        indicatorPlacementPopup.target = self
        indicatorPlacementPopup.action = #selector(selectIndicatorPlacement)
    }

    private func selectPopupItem(_ popup: NSPopUpButton, representedObject: String) {
        guard let items = popup.menu?.items else { return }
        if let item = items.first(where: { ($0.representedObject as? String) == representedObject }) {
            popup.select(item)
        }
    }

    private func selectHotkeyPopup(keyCode: UInt32, modifiers: UInt32) {
        guard let menu = hotkeyPopup.menu else { return }
        // First item in the menu is always the current hotkey display
        if let topItem = menu.items.first {
            topItem.representedObject = [keyCode, modifiers]
            guard let appDelegate else { return }
            topItem.title = appDelegate.hotkeyDisplayName
            hotkeyPopup.select(topItem)
            hotkeyPopup.synchronizeTitleAndSelectedItem()
        }
    }

    private func whisperCliStatusText() -> String {
        guard let appDelegate else { return "" }
        let ready = appDelegate.runtimeStatus(for: .whisperCLI).isReady
        let status = ready ? L10n.text("common.ready") : L10n.text("common.missing")
        return "\(L10n.text("settings.runtime_status_label")) — \(L10n.text("runtime.whisper_file")): \(status)"
    }

    private func whisperDictateStatusText() -> String {
        guard let appDelegate else { return "" }
        let ready = appDelegate.runtimeStatus(for: .whisperDictate).isReady
        let status = ready ? L10n.text("common.ready") : L10n.text("common.missing")
        return "\(L10n.text("settings.runtime_status_label")) — \(L10n.text("runtime.whisper_dictation")): \(status)"
    }

    @objc private func selectAppLanguage(_ sender: NSPopUpButton) {
        guard !isRefreshing,
              let rawValue = sender.selectedItem?.representedObject as? String,
              let language = AppUILanguage(rawValue: rawValue),
              let appDelegate,
              language != appDelegate.currentAppLanguagePreference else { return }

        appDelegate.applyAppLanguagePreference(language)
        appDelegate.promptForAppLanguageRelaunch()
        refreshFromAppState()
    }

    @objc private func selectHotkey(_ sender: NSPopUpButton) {
        guard !isRefreshing,
              let values = sender.selectedItem?.representedObject as? [UInt32],
              values.count == 2 else { return }
        appDelegate?.applyHotkeyChange(keyCode: values[0], modifiers: values[1])
        refreshFromAppState()
    }

    @objc private func openCustomHotkey() {
        appDelegate?.showHotkeySettings()
    }

    @objc private func toggleLaunchAtLogin() {
        guard !isRefreshing, let appDelegate else { return }
        let shouldEnable = launchAtLoginButton.state == .on
        if shouldEnable != appDelegate.isLaunchAtLoginEnabled() {
            appDelegate.toggleLaunchAtLogin()
        }
        refreshFromAppState()
    }

    @objc private func showAbout() {
        appDelegate?.showAboutPanel()
    }

    @objc private func selectModel(_ sender: NSPopUpButton) {
        guard !isRefreshing,
              let rawValue = sender.selectedItem?.representedObject as? String,
              let backend = TranscriptionBackendKind(rawValue: rawValue) else { return }
        appDelegate?.selectBackend(backend)
        refreshFromAppState()
    }

    @objc private func modelActionTapped() {
        guard let appDelegate else { return }
        let backend = appDelegate.currentBackendKind
        switch appDelegate.modelStatus(for: backend) {
        case .downloading:
            appDelegate.cancelModelDownload(for: backend)
        case .ready:
            confirmAndDeleteModel(backend)
        case .missing, .error:
            break
        }
    }

    private func confirmAndDeleteModel(_ backend: TranscriptionBackendKind) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("alert.delete_model_title")
        alert.informativeText = L10n.text("alert.delete_model_message", backend.shortDisplayName)
        alert.addButton(withTitle: L10n.text("settings.delete_model"))
        alert.addButton(withTitle: L10n.text("panel.cancel_button"))
        if alert.runModal() == .alertFirstButtonReturn {
            appDelegate?.deleteModel(for: backend)
            refreshFromAppState()
        }
    }

    @objc private func selectSpokenLanguage(_ sender: NSPopUpButton) {
        guard !isRefreshing,
              let code = sender.selectedItem?.representedObject as? String else { return }
        appDelegate?.currentLanguage = code
        refreshFromAppState()
    }

    @objc private func selectSoundProfile(_ sender: NSPopUpButton) {
        guard !isRefreshing,
              let rawValue = sender.selectedItem?.representedObject as? String,
              let profile = DictationSoundProfile(rawValue: rawValue) else { return }
        appDelegate?.selectSoundProfile(profile)
        refreshFromAppState()
    }

    @objc private func selectInsertionStrategy(_ sender: NSPopUpButton) {
        guard !isRefreshing,
              let rawValue = sender.selectedItem?.representedObject as? String,
              let strategy = TextInsertionStrategy(rawValue: rawValue) else { return }
        appDelegate?.selectInsertionStrategy(strategy)
        refreshFromAppState()
    }

    @objc private func openAudioFileTranscription() {
        appDelegate?.showAudioFileTranscriptionPanel()
    }

    @objc private func toggleIndicator() {
        guard !isRefreshing, let appDelegate else { return }
        let shouldEnable = indicatorEnabledButton.state == .on
        if shouldEnable != appDelegate.isIndicatorEnabled {
            appDelegate.toggleIndicatorEnabled()
        }
        refreshFromAppState()
    }

    @objc private func selectIndicatorStyle(_ sender: NSPopUpButton) {
        guard !isRefreshing,
              let rawValue = sender.selectedItem?.representedObject as? String,
              let style = IndicatorVisualStyle(rawValue: rawValue) else { return }
        appDelegate?.selectIndicatorVisualStyle(style)
        refreshFromAppState()
    }

    @objc private func selectIndicatorPalette(_ sender: NSPopUpButton) {
        guard !isRefreshing,
              let rawValue = sender.selectedItem?.representedObject as? String,
              let palette = IndicatorColorPalette(rawValue: rawValue) else { return }
        appDelegate?.selectIndicatorColorPalette(palette)
        refreshFromAppState()
    }

    @objc private func selectIndicatorPlacement(_ sender: NSPopUpButton) {
        guard !isRefreshing,
              let rawValue = sender.selectedItem?.representedObject as? String,
              let placement = IndicatorPlacement(rawValue: rawValue) else { return }
        appDelegate?.selectIndicatorPlacement(placement)
        refreshFromAppState()
    }
}

/// Top-origin view for use as an NSScrollView documentView, so content shorter
/// than the viewport pins to the top instead of the bottom.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
