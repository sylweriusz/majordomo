import AppKit
import Carbon

@MainActor
final class HotkeySettingsWindowController: NSWindowController, NSWindowDelegate {
    private let hintLabel = NSTextField(wrappingLabelWithString: "")
    private var captureMode = false
    private nonisolated(unsafe) var eventMonitor: Any?

    var onCaptureCompleted: (@MainActor (UInt32, UInt32) -> Void)?

    init() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 100))
        let window = NSWindow(contentRect: contentView.frame,
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = L10n.text("hotkey.window_title")
        window.center()
        window.contentView = contentView

        super.init(window: window)
        window.delegate = self
        configureContent(contentView)
        startCapture()
    }

    override func showWindow(_ sender: Any?) {
        if captureMode == false {
            startCapture()
        }
        hintLabel.stringValue = L10n.text("hotkey.listening")
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
    }

    deinit {
        stopEventMonitor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureContent(_ view: NSView) {
        let title = NSTextField(labelWithString: L10n.text("hotkey.press_combination"))
        title.font = .systemFont(ofSize: 15, weight: .medium)
        title.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.stringValue = L10n.text("hotkey.listening")
        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(title)
        view.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),

            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14)
        ])
    }

    @objc private func startCapture() {
        captureMode = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.captureMode else { return event }
            self.handleCapturedKeyEvent(event)
            return nil
        }
    }

    private static let functionKeyCodes: Set<UInt32> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
    ].map(UInt32.init).reduce(into: Set<UInt32>()) { $0.insert($1) }

    private func handleCapturedKeyEvent(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        let rawFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        var carbonModifiers: UInt32 = 0
        if rawFlags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if rawFlags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if rawFlags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if rawFlags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }

        // Bare Escape cancels the capture (keeps the existing hotkey).
        if keyCode == UInt32(kVK_Escape), carbonModifiers == 0 {
            captureMode = false
            stopEventMonitor()
            window?.close()
            return
        }

        // Require a modifier, unless it's a function key — a bare letter/number
        // would silently hijack that key system-wide.
        let isFunctionKey = Self.functionKeyCodes.contains(keyCode)
        guard carbonModifiers != 0 || isFunctionKey else {
            hintLabel.stringValue = L10n.text("hotkey.need_modifier")
            NSSound.beep()
            return
        }

        captureMode = false
        stopEventMonitor()
        onCaptureCompleted?(keyCode, carbonModifiers)
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        captureMode = false
        stopEventMonitor()
    }

    nonisolated private func stopEventMonitor() {
        guard let monitor = eventMonitor else { return }
        NSEvent.removeMonitor(monitor)
        MainActor.assumeIsolated {
            self.eventMonitor = nil
        }
    }
}
