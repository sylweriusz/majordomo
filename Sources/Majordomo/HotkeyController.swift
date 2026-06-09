import AppKit
import Carbon
import Foundation
import MajordomoCore

enum HotkeyError: LocalizedError {
    case installHandlerFailed(OSStatus)
    case registerFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .installHandlerFailed(let status):
            L10n.text("error.hotkey.install_failed", status)
        case .registerFailed(let status):
            L10n.text("error.hotkey.register_failed", status)
        }
    }
}

/// Registers the global activation hotkey (Carbon hot key, or a passive Fn-key
/// monitor for the standalone Function key).
///
/// Concurrency: every method here must be called on the main actor. The type is
/// `@unchecked Sendable` rather than `@MainActor` on purpose — `deinit` calls
/// `unregister()` to release the Carbon `EventHotKeyRef`/`EventHandlerRef` and
/// the `NSEvent` monitors, and a `@MainActor` class cannot run that cleanup from
/// its non-isolated `deinit` under Swift 6. The `Unmanaged.passUnretained(self)`
/// pointer handed to the Carbon callback is sound because the callback fires on
/// the main run loop and hops to `@MainActor` before touching `self`, and the
/// single instance is owned by `AppDelegate` for the whole app lifetime.
final class HotkeyController: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var localFunctionMonitor: Any?
    private var globalFunctionMonitor: Any?
    private var functionKeyIsDown = false
    private let onPressed: @MainActor @Sendable () -> Void

    private(set) var currentKeyCode: UInt32
    private(set) var currentModifiers: UInt32

    private enum UserDefaultsKey {
        static let keyCode = DefaultsKey.hotkeyKeyCode
        static let modifiers = DefaultsKey.hotkeyModifiers
    }
    private static let hotKeySignature = fourCharCode("MJDM")
    private static let hotKeyID: UInt32 = 1

    private static var defaultHotkey: (keyCode: UInt32, modifiers: UInt32) {
        if Bundle.main.bundleIdentifier?.hasSuffix(".test") == true {
            return (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        }
        // Stable default is ⌥Space: a real chord registered via Carbon
        // (works without Accessibility, unlike a bare Fn key) and unlikely to
        // collide with the emoji picker / Apple Dictation that overload Fn.
        // Users can still pick Fn explicitly from Hotkey Settings.
        return (UInt32(kVK_Space), UInt32(optionKey))
    }

    init(onPressed: @escaping @MainActor @Sendable () -> Void) {
        self.onPressed = onPressed

        let storedKeyCode = UserDefaults.standard.integer(forKey: UserDefaultsKey.keyCode)
        let storedModifiers = UserDefaults.standard.integer(forKey: UserDefaultsKey.modifiers)

        if storedKeyCode > 0 || storedModifiers > 0 {
            currentKeyCode = UInt32(storedKeyCode)
            currentModifiers = UInt32(storedModifiers)
        } else {
            let defaultHotkey = Self.defaultHotkey
            currentKeyCode = defaultHotkey.keyCode
            currentModifiers = defaultHotkey.modifiers
        }
    }

    deinit {
        unregister()
    }

    func registerDefaultHotkey() throws {
        try registerHotkey(keyCode: currentKeyCode, modifiers: currentModifiers)
    }

    func registerHotkey(keyCode: UInt32, modifiers: UInt32) throws {
        unregister()

        if Self.isStandaloneFunctionKey(keyCode: keyCode, modifiers: modifiers) {
            registerStandaloneFunctionKey()
            currentKeyCode = keyCode
            currentModifiers = modifiers
            persist()
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData,
                      HotkeyController.eventMatchesHotKey(event, signature: HotkeyController.hotKeySignature, id: HotkeyController.hotKeyID) else {
                    return OSStatus(eventNotHandledErr)
                }
                let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    controller.onPressed()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            throw HotkeyError.installHandlerFailed(installStatus)
        }

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyID)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            unregister()
            throw HotkeyError.registerFailed(registerStatus)
        }

        currentKeyCode = keyCode
        currentModifiers = modifiers
        persist()
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        if let localFunctionMonitor {
            NSEvent.removeMonitor(localFunctionMonitor)
            self.localFunctionMonitor = nil
        }

        if let globalFunctionMonitor {
            NSEvent.removeMonitor(globalFunctionMonitor)
            self.globalFunctionMonitor = nil
        }

        functionKeyIsDown = false
    }

    private func registerStandaloneFunctionKey() {
        localFunctionMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFunctionFlagsChanged(event.modifierFlags)
            return event
        }

        globalFunctionMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFunctionFlagsChanged(event.modifierFlags)
        }
    }

    private func handleFunctionFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        let isDown = flags.contains(.function)

        guard isDown != functionKeyIsDown else { return }
        functionKeyIsDown = isDown

        guard isDown else { return }
        Task { @MainActor in
            self.onPressed()
        }
    }

    private static func isStandaloneFunctionKey(keyCode: UInt32, modifiers: UInt32) -> Bool {
        keyCode == UInt32(kVK_Function) && modifiers == 0
    }

    private static func eventMatchesHotKey(_ event: EventRef?, signature: OSType, id: UInt32) -> Bool {
        guard let event else { return false }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        return status == noErr && hotKeyID.signature == signature && hotKeyID.id == id
    }

    private func persist() {
        UserDefaults.standard.set(Int(currentKeyCode), forKey: UserDefaultsKey.keyCode)
        UserDefaults.standard.set(Int(currentModifiers), forKey: UserDefaultsKey.modifiers)
    }

    private static func fourCharCode(_ string: String) -> OSType {
        var result: OSType = 0
        for scalar in string.unicodeScalars.prefix(4) {
            result = (result << 8) + OSType(scalar.value)
        }
        return result
    }

    nonisolated func keyCodeName(_ code: UInt32) -> String {
        switch code {
        case UInt32(kVK_Space): return "Space"
        case UInt32(kVK_Return): return "Return"
        case UInt32(kVK_Tab): return "Tab"
        case UInt32(kVK_Delete): return "Delete"
        case UInt32(kVK_Escape): return "Escape"
        case UInt32(kVK_UpArrow): return "▲"
        case UInt32(kVK_DownArrow): return "▼"
        case UInt32(kVK_LeftArrow): return "◀"
        case UInt32(kVK_RightArrow): return "▶"
        case UInt32(kVK_Function): return "Fn"
        case UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
             UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
             UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12):
            return Self.fKeyName(code)
        default:
            if let scalar = codeToUnicode(code) {
                return scalar.uppercased()
            }
            return "key(\(code))"
        }
    }

    private nonisolated static func fKeyName(_ code: UInt32) -> String {
        let fkeys: [UInt32] = [
            UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
            UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
            UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12)
        ]
        if let index = fkeys.firstIndex(of: code) {
            return "F\(index + 1)"
        }
        return "key(\(code))"
    }

    nonisolated func modifiersName(_ flags: UInt32) -> String {
        var parts: [String] = []
        if flags & UInt32(controlKey) != 0 { parts.append("⌃") }
        if flags & UInt32(optionKey) != 0 { parts.append("⌥") }
        if flags & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if flags & UInt32(cmdKey) != 0 { parts.append("⌘") }
        return parts.joined()
    }

    nonisolated func hotkeyDisplayName(keyCode: UInt32, modifiers: UInt32) -> String {
        "\(modifiersName(modifiers))\(keyCodeName(keyCode))"
    }

    private nonisolated func codeToUnicode(_ code: UInt32) -> String? {
        let layout = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        guard let layout else { return nil }
        let layoutData = TISGetInputSourceProperty(layout, kTISPropertyUnicodeKeyLayoutData)
        guard let layoutData else { return nil }
        let keyboardLayoutPtr = unsafeBitCast(CFDataGetBytePtr(unsafeBitCast(layoutData, to: CFData.self)), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        let maxLength = 4
        var chars = [UniChar](repeating: 0, count: maxLength)
        var actualLength = 0

        let status = UCKeyTranslate(
            keyboardLayoutPtr,
            UInt16(code),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            maxLength,
            &actualLength,
            &chars
        )

        guard status == noErr, actualLength > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: actualLength)
    }
}
