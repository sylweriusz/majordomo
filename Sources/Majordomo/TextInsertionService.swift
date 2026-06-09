import AppKit
import ApplicationServices

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

        if let processIdentifier = targetApplication?.processIdentifier,
           Self.insertWithAccessibility(trimmedText, processIdentifier: processIdentifier) {
            AppLog.info("inserted text with Accessibility into \(targetName ?? "focused app")")
            return TextInsertionResult(method: .accessibilitySelectedText, targetApplicationName: targetName)
        }

        AppLog.info("Accessibility insertion unavailable for \(targetName ?? "focused app"); trying clipboard paste fallback")
        if await Self.insertWithClipboardPaste(trimmedText) {
            AppLog.info("posted clipboard paste fallback into \(targetName ?? "focused app")")
            return TextInsertionResult(method: .clipboardPasteEvent, targetApplicationName: targetName)
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
