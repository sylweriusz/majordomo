import AppKit
import Carbon
import MajordomoCore

/// Observes the double-Escape cancel gesture while dictation is active.
///
/// Uses passive `NSEvent` monitors rather than a Carbon `RegisterEventHotKey`.
/// A registered Carbon hot key *consumes* Escape system-wide, so the app the
/// user is dictating into never receives the key. A global monitor only
/// observes (it cannot swallow), so single Escape still passes through to the
/// target app while we detect the double press. Global key monitoring relies on
/// the Accessibility permission the app already requires for text insertion.
@MainActor
final class DoubleEscapeCancelMonitor {
    private var detector: DoubleEscapeDetector
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let onCancel: @MainActor () -> Void

    init(maximumInterval: TimeInterval = 0.45, onCancel: @escaping @MainActor () -> Void) {
        self.detector = DoubleEscapeDetector(maximumInterval: maximumInterval)
        self.onCancel = onCancel
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        detector.reset()

        // Events from other applications (the usual case while dictating).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }

        // Events delivered to our own windows (overlay). Returning the event
        // leaves it unconsumed so nothing in the app loses Escape either.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
            return event
        }

        AppLog.info("double Escape cancel armed (passive monitor)")
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        detector.reset()
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == UInt16(kVK_Escape) else { return }
        guard detector.recordKey(isEscape: true, at: ProcessInfo.processInfo.systemUptime) else { return }
        onCancel()
    }
}
