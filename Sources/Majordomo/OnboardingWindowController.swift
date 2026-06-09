import AppKit
@preconcurrency import AVFoundation
import ApplicationServices

/// First-run welcome window. Teaches the activation hotkey and the double-Escape
/// cancel gesture, and primes the Microphone + Accessibility permissions up
/// front — before the first dictation, instead of mid-flight where a denied
/// permission would lose the user's first transcript.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private static let completedKey = "hasCompletedOnboarding"
    static var hasCompleted: Bool { UserDefaults.standard.bool(forKey: completedKey) }

    /// Display name of the current activation hotkey (e.g. "⌥ Space").
    var hotkeyDisplayName: String = "⌥ Space"
    /// Called once when the user finishes onboarding.
    var onFinish: (@MainActor () -> Void)?
    /// Whether the current hotkey is the bare Fn key (worth nudging away from).
    var isCurrentHotkeyBareFn = false
    /// Switches the activation hotkey to the recommended ⌥Space chord.
    var onUseRecommendedHotkey: (@MainActor () -> Void)?

    private let hotkeyLine = NSTextField(wrappingLabelWithString: "")
    private let micStatusLabel = NSTextField(labelWithString: "")
    private let micButton = NSButton()
    private let axStatusLabel = NSTextField(labelWithString: "")
    private let axButton = NSButton()
    private let fnNudgeButton = NSButton()
    private var fnNudgeRow: NSView?
    private var pollTimer: Timer?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 410),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = L10n.text("onboarding.title")
        super.init(window: window)
        window.delegate = self
        buildContent()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        refreshHotkeyLine()
        refreshPermissionStates()
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
        startPolling()
    }

    func windowWillClose(_ notification: Notification) {
        stopPolling()
    }

    // MARK: - Content

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: L10n.text("onboarding.title"))
        title.font = .systemFont(ofSize: 22, weight: .bold)

        let subtitle = NSTextField(wrappingLabelWithString: L10n.text("onboarding.subtitle"))
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor

        hotkeyLine.font = .systemFont(ofSize: 13)
        let cancelLine = NSTextField(wrappingLabelWithString: L10n.text("onboarding.cancel_line"))
        cancelLine.font = .systemFont(ofSize: 13)
        cancelLine.textColor = .secondaryLabelColor

        let fnNudge = makeFnNudgeRow()

        let permTitle = SettingsTheme.makeSectionTitle(L10n.text("onboarding.permissions_title"))

        let micRow = makePermissionRow(
            title: L10n.text("onboarding.mic_label"),
            rationale: L10n.text("onboarding.mic_rationale"),
            statusLabel: micStatusLabel,
            button: micButton,
            action: #selector(handleMicButton))
        let axRow = makePermissionRow(
            title: L10n.text("onboarding.accessibility_label"),
            rationale: L10n.text("onboarding.accessibility_rationale"),
            statusLabel: axStatusLabel,
            button: axButton,
            action: #selector(handleAccessibilityButton))

        let modelNote = NSTextField(wrappingLabelWithString: L10n.text("onboarding.model_note"))
        modelNote.font = .systemFont(ofSize: 11)
        modelNote.textColor = .tertiaryLabelColor

        let getStarted = NSButton(title: L10n.text("onboarding.get_started"), target: self, action: #selector(finish))
        getStarted.bezelStyle = .rounded
        getStarted.keyEquivalent = "\r"

        let buttonRow = NSStackView(views: [NSView(), getStarted])
        buttonRow.orientation = .horizontal

        let stack = NSStackView(views: [title, subtitle, hotkeyLine, cancelLine, fnNudge,
                                        permTitle, micRow, axRow, modelNote, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Match the Settings window: gradient background + a translucent card.
        let background = SettingsBackgroundView(frame: content.bounds)
        background.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(background)

        let card = SettingsCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(card)
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            background.topAnchor.constraint(equalTo: content.topAnchor),
            background.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            card.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            card.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),

            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -22),
            buttonRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
    }

    private func makePermissionRow(title: String, rationale: String,
                                   statusLabel: NSTextField, button: NSButton,
                                   action: Selector) -> NSView {
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        let why = NSTextField(labelWithString: rationale)
        why.font = .systemFont(ofSize: 11)
        why.textColor = .secondaryLabelColor
        let textStack = NSStackView(views: [name, why])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        statusLabel.font = .systemFont(ofSize: 12)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.target = self
        button.action = action

        let row = NSStackView(views: [textStack, NSView(), statusLabel, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func makeFnNudgeRow() -> NSView {
        let label = NSTextField(wrappingLabelWithString: L10n.text("onboarding.fn_warning"))
        label.font = .systemFont(ofSize: 11)
        label.textColor = .systemOrange
        fnNudgeButton.title = L10n.text("onboarding.use_recommended")
        fnNudgeButton.bezelStyle = .rounded
        fnNudgeButton.controlSize = .small
        fnNudgeButton.target = self
        fnNudgeButton.action = #selector(handleUseRecommendedHotkey)
        let row = NSStackView(views: [label, fnNudgeButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.isHidden = true
        fnNudgeRow = row
        return row
    }

    @objc private func handleUseRecommendedHotkey() {
        onUseRecommendedHotkey?()
        hotkeyDisplayName = "⌥ Space"
        isCurrentHotkeyBareFn = false
        refreshHotkeyLine()
    }

    // MARK: - Permissions

    private func refreshHotkeyLine() {
        hotkeyLine.stringValue = L10n.text("onboarding.hotkey_line", hotkeyDisplayName)
        fnNudgeRow?.isHidden = !isCurrentHotkeyBareFn
    }

    private func refreshPermissionStates() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let micGranted = mic == .authorized
        micStatusLabel.stringValue = L10n.text(micGranted ? "onboarding.granted" : "onboarding.not_granted")
        micStatusLabel.textColor = micGranted ? .systemGreen : .secondaryLabelColor
        micButton.isHidden = micGranted
        micButton.title = L10n.text(mic == .denied || mic == .restricted ? "onboarding.open_settings" : "onboarding.grant")

        let axGranted = AXIsProcessTrusted()
        axStatusLabel.stringValue = L10n.text(axGranted ? "onboarding.granted" : "onboarding.not_granted")
        axStatusLabel.textColor = axGranted ? .systemGreen : .secondaryLabelColor
        axButton.isHidden = axGranted
        axButton.title = L10n.text("onboarding.open_settings")
    }

    @objc private func handleMicButton() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in self.refreshPermissionStates() }
            }
        default:
            openSettings("Privacy_Microphone")
        }
    }

    @objc private func handleAccessibilityButton() {
        // Prompts the system Accessibility dialog (which deep-links to Settings).
        // Use the literal key string to avoid referencing the non-Sendable
        // global `kAXTrustedCheckOptionPrompt` under Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSettings("Privacy_Accessibility")
    }

    private func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startPolling() {
        stopPolling()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissionStates() }
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    @objc private func finish() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        stopPolling()
        window?.close()
        onFinish?()
    }
}
