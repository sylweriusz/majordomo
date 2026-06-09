import AppKit
import os

@MainActor
final class DictationOverlayWindowController: NSWindowController {
    private let overlayView = WaveformOverlayView()
    private var leftWingView: WaveformOverlayView?
    private var rightWingView: WaveformOverlayView?
    private var leftWingPanel: NSPanel?
    private var rightWingPanel: NSPanel?
    private var levels: [Float] = Array(repeating: 0, count: WaveformLevels.count)
    private var dockPollTimer: Timer?
    private var fadeTimer: Timer?
    private var fadeGeneration = 0
    private var lastWingFrames: (left: NSRect, right: NSRect)?
    private var hintPanel: NSPanel?
    private var hintTimer: Timer?
    private static let cancelHintCountKey = "cancelHintShownCount"
    private static let cancelHintMaxShows = 3

    var visualStyle: IndicatorVisualStyle {
        get { overlayView.visualStyle }
        set {
            overlayView.visualStyle = newValue
            leftWingView?.visualStyle = newValue
            rightWingView?.visualStyle = newValue
        }
    }
    var colorPalette: IndicatorColorPalette {
        get { overlayView.colorPalette }
        set {
            overlayView.colorPalette = newValue
            leftWingView?.colorPalette = newValue
            rightWingView?.colorPalette = newValue
        }
    }
    var placement: IndicatorPlacement = .defaultPlacement {
        didSet { updatePlacement() }
    }

    init() {
        let frame = Self.defaultNotchFrame()
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = overlayView

        super.init(window: panel)

        createWingPanels()
        Self.log("init")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        // Safety net for the run-loop timers in case the controller is torn
        // down without an explicit hide()/stopDockPolling().
        fadeTimer?.invalidate()
        dockPollTimer?.invalidate()
    }

    func showRecording() {
        show(mode: .recording)
        maybeShowCancelHint()
    }

    func showTranscribing() {
        show(mode: .transcribing)
    }

    func hide() {
        cancelFade(resetAlpha: false)
        overlayView.stopAnimating()
        window?.orderOut(nil)
        leftWingView?.stopAnimating()
        rightWingView?.stopAnimating()
        leftWingPanel?.orderOut(nil)
        rightWingPanel?.orderOut(nil)
        stopDockPolling()
        hideCancelHint()
        resetOverlayOpacity()
    }

    // MARK: - Cancel hint

    /// Shows a transient "press Esc twice to cancel" caption below the notch for
    /// the first few dictations, then stops. Teaches the otherwise-undiscoverable
    /// double-Escape gesture without putting text inside the indicator effect.
    private func maybeShowCancelHint() {
        let defaults = UserDefaults.standard
        let shown = defaults.integer(forKey: Self.cancelHintCountKey)
        guard shown < Self.cancelHintMaxShows else { return }
        defaults.set(shown + 1, forKey: Self.cancelHintCountKey)

        let panel = hintPanel ?? Self.makeHintPanel()
        hintPanel = panel
        if let label = panel.contentView?.viewWithTag(1) as? NSTextField {
            label.stringValue = L10n.text("overlay.cancel_hint")
        }

        let notch = Self.defaultNotchFrame()
        let size = NSSize(width: 260, height: 26)
        panel.setFrame(NSRect(x: notch.midX - size.width / 2,
                              y: notch.minY - size.height - 6,
                              width: size.width, height: size.height),
                       display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hintTimer?.invalidate()
        let timer = Timer(timeInterval: 2.8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeCancelHintOut() }
        }
        hintTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func fadeCancelHintOut() {
        guard let hintPanel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            hintPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.hideCancelHint() }
        })
    }

    private func hideCancelHint() {
        hintTimer?.invalidate()
        hintTimer = nil
        hintPanel?.orderOut(nil)
    }

    private static func makeHintPanel() -> NSPanel {
        let size = NSSize(width: 260, height: 26)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true

        let background = NSView(frame: NSRect(origin: .zero, size: size))
        background.wantsLayer = true
        background.layer?.cornerRadius = 13
        background.layer?.cornerCurve = .continuous
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor

        let label = NSTextField(labelWithString: "")
        label.tag = 1
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 8, y: 5, width: size.width - 16, height: 16)
        label.autoresizingMask = [.width]
        background.addSubview(label)

        panel.contentView = background
        return panel
    }

    func fadeOutAndHide(duration: TimeInterval = 0.46) {
        cancelFade(resetAlpha: false)
        let generation = fadeGeneration
        let visibleWindows = overlayWindows().filter { $0.isVisible }
        guard !visibleWindows.isEmpty else {
            hide()
            return
        }

        let start = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.advanceFade(generation: generation, start: start, duration: duration)
            }
        }
        fadeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceFade(generation: Int, start: Date, duration: TimeInterval) {
        guard generation == fadeGeneration else { return }

        let progress = min(1, max(0, Date().timeIntervalSince(start) / max(0.01, duration)))
        let eased = progress * progress * (3 - 2 * progress)
        setOverlayOpacity(CGFloat(max(0, 1 - eased)))

        guard progress >= 1 else { return }
        fadeTimer?.invalidate()
        fadeTimer = nil
        hide()
    }

    private func cancelFade(resetAlpha: Bool) {
        fadeGeneration += 1
        fadeTimer?.invalidate()
        fadeTimer = nil
        if resetAlpha {
            resetOverlayOpacity()
        }
    }

    private func resetOverlayOpacity() {
        setOverlayOpacity(1)
    }

    private func setOverlayOpacity(_ alpha: CGFloat) {
        overlayWindows().forEach { $0.alphaValue = alpha }
    }

    private func overlayWindows() -> [NSWindow] {
        var windows: [NSWindow] = []
        if let window {
            windows.append(window)
        }
        if let leftWingPanel {
            windows.append(leftWingPanel)
        }
        if let rightWingPanel {
            windows.append(rightWingPanel)
        }
        return windows
    }

    func updateLevels(_ newLevels: [Float]) {
        levels = newLevels
        overlayView.setLevels(newLevels)
        leftWingView?.setLevels(newLevels)
        rightWingView?.setLevels(newLevels)
    }

    // MARK: - Placement

    private func updatePlacement() {
        cancelFade(resetAlpha: true)
        let resolved = resolvedPlacement()
        switch resolved {
        case .notch:
            leftWingPanel?.orderOut(nil)
            rightWingPanel?.orderOut(nil)
            leftWingView?.stopAnimating()
            rightWingView?.stopAnimating()
            stopDockPolling()
        case .dockWings:
            window?.orderOut(nil)
            overlayView.stopAnimating()
            startDockPolling()
        case .auto:
            break
        }
    }

    private func resolvedPlacement() -> IndicatorPlacement {
        switch placement {
        case .notch, .dockWings:
            return placement
        case .auto:
            return Self.hasDockSpace() ? .dockWings : .notch
        }
    }

    private static func hasDockSpace() -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.origin.x == 0 && $0.frame.origin.y == 0 }) ?? NSScreen.main else {
            return false
        }
        return Self.bottomDockGap(on: screen) > 10
    }

    // MARK: - Show

    private func show(mode: WaveformOverlayMode) {
        cancelFade(resetAlpha: true)
        let resolved = resolvedPlacement()

        switch resolved {
        case .notch:
            window?.setFrame(Self.defaultNotchFrame(), display: true)
            window?.alphaValue = 1
            window?.orderFrontRegardless()
            overlayView.startAnimating(mode: mode)
            leftWingPanel?.orderOut(nil)
            rightWingPanel?.orderOut(nil)
            leftWingView?.stopAnimating()
            rightWingView?.stopAnimating()
            stopDockPolling()

        case .dockWings:
            window?.orderOut(nil)
            overlayView.stopAnimating()
            showWings(mode: mode)
            startDockPolling()

        case .auto:
            break
        }
    }

    // MARK: - Wings

    private func createWingPanels() {
        let leftPanel = Self.makeWingPanel()
        let rightPanel = Self.makeWingPanel()

        let leftView = WaveformOverlayView()
        leftView.visualStyle = overlayView.visualStyle
        leftView.colorPalette = overlayView.colorPalette
        leftPanel.contentView = leftView

        let rightView = WaveformOverlayView()
        rightView.visualStyle = overlayView.visualStyle
        rightView.colorPalette = overlayView.colorPalette
        rightView.isHorizontallyMirrored = true
        rightPanel.contentView = rightView

        leftWingPanel = leftPanel
        rightWingPanel = rightPanel
        leftWingView = leftView
        rightWingView = rightView
    }

    private func showWings(mode: WaveformOverlayMode) {
        guard let screen = Self.primaryScreen() else { return }

        let frames = Self.wingFrames(on: screen)
        lastWingFrames = frames

        Self.log("showWings: screen=\(Int(screen.frame.width))x\(Int(screen.frame.height)) bottomGap=\(Int(Self.bottomDockGap(on: screen))) wing=\(Int(frames.left.width))x\(Int(frames.left.height))")

        leftWingPanel?.setFrame(frames.left, display: true)
        rightWingPanel?.setFrame(frames.right, display: true)
        leftWingPanel?.alphaValue = 1
        rightWingPanel?.alphaValue = 1

        leftWingView?.startAnimating(mode: mode)
        rightWingView?.startAnimating(mode: mode)

        leftWingPanel?.orderFrontRegardless()
        rightWingPanel?.orderFrontRegardless()
    }

    private func animateWingResize() {
        guard let screen = Self.primaryScreen() else { return }

        let frames = Self.wingFrames(on: screen)
        lastWingFrames = frames
        Self.log("animateResize: wing=\(Int(frames.left.width))x\(Int(frames.left.height))")

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 1.0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.leftWingPanel?.animator().setFrame(frames.left, display: true)
            self.rightWingPanel?.animator().setFrame(frames.right, display: true)
        }
    }

    private static func wingFrames(on screen: NSScreen) -> (left: NSRect, right: NSRect) {
        let screenFrame = screen.frame
        let wingHeight = bottomDockHeight(on: screen)
        let wingWidth = min(screenFrame.width * 0.18, screenFrame.width / 2)
        let bottomY = screenFrame.minY

        let left = NSRect(x: screenFrame.minX, y: bottomY, width: wingWidth, height: wingHeight)
        let right = NSRect(x: screenFrame.maxX - wingWidth, y: bottomY, width: wingWidth, height: wingHeight)
        return (left, right)
    }

    private static func bottomDockGap(on screen: NSScreen) -> CGFloat {
        max(0, screen.visibleFrame.minY - screen.frame.minY)
    }

    private static func bottomDockHeight(on screen: NSScreen) -> CGFloat {
        let systemBottomGap = bottomDockGap(on: screen)
        if systemBottomGap > 1 {
            return systemBottomGap
        }

        let fallback = CGFloat(readDockTileSize() + 20)
        Self.log("Dock height fallback: tilesize+20=\(Int(fallback))")
        return fallback
    }

    private static func primaryScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.origin.x == 0 && $0.frame.origin.y == 0 }) ?? NSScreen.main
    }

    // MARK: - Dock Discovery

    private static func readDockTileSize() -> Int {
        if let plist = UserDefaults(suiteName: "com.apple.dock"),
           plist.integer(forKey: "tilesize") > 0 {
            let tilesize = plist.integer(forKey: "tilesize")
            Self.log("Dock tilesize: \(tilesize)")
            return tilesize
        }
        let plistPath = "/Users/\(NSUserName())/Library/Preferences/com.apple.dock.plist"
        if let dict = NSDictionary(contentsOfFile: plistPath),
           let tilesize = dict["tilesize"] as? Int,
           tilesize > 0 {
            Self.log("Dock plist tilesize: \(tilesize)")
            return tilesize
        }
        Self.log("Dock: tilesize not found, fallback 47")
        return 47
    }

    private static let dockLogger = Logger(subsystem: "pl.wild-matrix.majordomo", category: "dock")
    private static let dockLoggingEnabled = ProcessInfo.processInfo.environment["MAJORDOMO_DEBUG_DOCK"] == "1"

    private static func log(_ message: String) {
        // Opt-in diagnostics only. Previously this wrote unconditionally to a
        // world-readable, fixed-name file in /tmp on every dictation — a debug
        // leftover and a symlink-follow target. Now gated and routed to the
        // unified log (no on-disk artifact).
        guard dockLoggingEnabled else { return }
        dockLogger.debug("\(message, privacy: .public)")
    }

    // MARK: - Dock Polling

    private func startDockPolling() {
        guard dockPollTimer == nil else { return }
        dockPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkDockChange() }
        }
        RunLoop.main.add(dockPollTimer!, forMode: .common)
    }

    private func stopDockPolling() {
        dockPollTimer?.invalidate()
        dockPollTimer = nil
        lastWingFrames = nil
    }

    private func checkDockChange() {
        guard let screen = Self.primaryScreen() else { return }
        let frames = Self.wingFrames(on: screen)

        guard let previousFrames = lastWingFrames else {
            lastWingFrames = frames
            return
        }

        guard !Self.framesMatch(previousFrames.left, frames.left) || !Self.framesMatch(previousFrames.right, frames.right) else {
            return
        }

        Self.log("poll: wing geometry changed to \(Int(frames.left.width))x\(Int(frames.left.height))")
        animateWingResize()
    }

    private static func framesMatch(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 0.5
            && abs(lhs.origin.y - rhs.origin.y) < 0.5
            && abs(lhs.width - rhs.width) < 0.5
            && abs(lhs.height - rhs.height) < 0.5
    }

    private static func makeWingPanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        return panel
    }

    // MARK: - Notch

    private static func defaultNotchFrame() -> NSRect {
        let screen = NSScreen.screens.first(where: { $0.frame.origin.x == 0 && $0.frame.origin.y == 0 }) ?? NSScreen.main
        guard let screenFrame = screen?.frame else { return NSRect(origin: .zero, size: NSSize(width: 300, height: 38)) }
        let size = NSSize(width: 300, height: 38)
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }
}

