import AppKit
import ApplicationServices
import MajordomoCore

/// User-selectable order of insertion methods. Paste works in the broadest set
/// of targets (text fields and terminals); the Accessibility selected-text API
/// is cleaner where it works but silently no-ops in terminals.
enum TextInsertionStrategy: String, CaseIterable {
    case clipboardPaste
    case accessibility

    static let userDefaultsKey = DefaultsKey.textInsertionStrategy
    static let defaultStrategy: TextInsertionStrategy = .clipboardPaste

    var displayName: String {
        switch self {
        case .clipboardPaste: L10n.text("insertion.method_paste")
        case .accessibility: L10n.text("insertion.method_accessibility")
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> TextInsertionStrategy {
        guard let rawValue = defaults.string(forKey: userDefaultsKey),
              let strategy = TextInsertionStrategy(rawValue: rawValue) else {
            return defaultStrategy
        }
        return strategy
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
    }
}

struct TextInsertionResult: Sendable {
    let method: TextInsertionMethod
    let targetApplicationName: String?
}

enum TextInsertionMethod: String, Sendable {
    case accessibilitySelectedText = "accessibility-selected-text"
    case clipboardPasteEvent = "clipboard-paste-event"
}

enum TextInsertionError: LocalizedError {
    case emptyText
    case accessibilityPermissionMissing
    case noInsertionMethodWorked(String?)

    var errorDescription: String? {
        switch self {
        case .emptyText:
            L10n.text("error.text.empty")
        case .accessibilityPermissionMissing:
            L10n.text("error.text.accessibility")
        case .noInsertionMethodWorked(let target):
            if let target, !target.isEmpty {
                L10n.text("error.text.insert_failed", target)
            } else {
                L10n.text("error.text.insert_failed_focused")
            }
        }
    }
}

@MainActor
final class TextInsertionService {
    func insert(_ text: String, targetApplication: NSRunningApplication?) async throws -> TextInsertionResult {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw TextInsertionError.emptyText
        }

        guard Self.requestAccessibilityPermissionIfNeeded() else {
            throw TextInsertionError.accessibilityPermissionMissing
        }

        let targetName = targetApplication?.localizedName
        if let targetApplication,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != targetApplication.processIdentifier {
            targetApplication.activate()
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        // Clipboard paste (⌘V) works in the broadest set of targets — text fields
        // AND terminals (Terminal.app, Ghostty), where the Accessibility
        // selected-text API returns success but inserts nothing (read-only buffer).
        // Paste is the default; Accessibility is the alternative for those who'd
        // rather not touch the clipboard. The non-chosen method is the fallback.
        // The clipboard is snapshotted, restored, and marked concealed/transient so
        // clipboard managers don't record the transcript.
        func tryClipboardPaste() async -> TextInsertionResult? {
            guard await Self.insertWithClipboardPaste(trimmedText) else { return nil }
            AppLog.info("inserted text via clipboard paste into \(targetName ?? "focused app")")
            return TextInsertionResult(method: .clipboardPasteEvent, targetApplicationName: targetName)
        }
        func tryAccessibility() -> TextInsertionResult? {
            guard let processIdentifier = targetApplication?.processIdentifier,
                  Self.insertWithAccessibility(trimmedText, processIdentifier: processIdentifier) else { return nil }
            AppLog.info("inserted text with Accessibility into \(targetName ?? "focused app")")
            return TextInsertionResult(method: .accessibilitySelectedText, targetApplicationName: targetName)
        }

        switch TextInsertionStrategy.load() {
        case .clipboardPaste:
            if let result = await tryClipboardPaste() { return result }
            if let result = tryAccessibility() { return result }
        case .accessibility:
            if let result = tryAccessibility() { return result }
            if let result = await tryClipboardPaste() { return result }
        }

        throw TextInsertionError.noInsertionMethodWorked(targetName)
    }

    private nonisolated static func requestAccessibilityPermissionIfNeeded() -> Bool {
        if AXIsProcessTrusted() { return true }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private nonisolated static func insertWithAccessibility(_ text: String, processIdentifier: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard focusedResult == .success, let focusedValue else {
            return false
        }

        let focusedElement = unsafeDowncast(focusedValue, to: AXUIElement.self)
        let setResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        return setResult == .success
    }

    private static func insertWithClipboardPaste(_ text: String) async -> Bool {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        // Mark the item concealed/transient so clipboard managers (Maccy, Paste,
        // Raycast…) don't record the transcript into their history — important
        // for a "local-first, no history" tool.
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        pasteboard.declareTypes([.string, concealed, transient], owner: nil)
        guard pasteboard.setString(text, forType: .string) else {
            snapshot.restore(to: pasteboard)
            return false
        }
        pasteboard.setString("", forType: concealed)
        pasteboard.setString("", forType: transient)

        guard postCommandV() else {
            snapshot.restore(to: pasteboard)
            return false
        }

        try? await Task.sleep(nanoseconds: 250_000_000)
        snapshot.restore(to: pasteboard)
        return true
    }

    private nonisolated static func postCommandV() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCodeV: CGKeyCode = 9

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]] = pasteboard.pasteboardItems?.map { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    values[type] = data
                }
            }
            return values
        } ?? []

        return PasteboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        let restoredItems = items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }

        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}
