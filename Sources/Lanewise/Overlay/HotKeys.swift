import Carbon.HIToolbox
import Foundation

/// System-wide hotkeys via Carbon's RegisterEventHotKey. These fire even while the game is
/// focused and, unlike an NSEvent global monitor, need no Accessibility permission.
@MainActor
final class HotKeys {
    static let shared = HotKeys()

    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var references: [EventHotKeyRef] = []
    private var handlerInstalled = false

    /// ⌃⇧O turns the whole overlay on/off, ⌃⇧M toggles move mode for placing panels.
    static func registerDefaults() {
        let modifiers = UInt32(controlKey | shiftKey)
        shared.register(keyCode: UInt32(kVK_ANSI_O), modifiers: modifiers) {
            AppSettings.shared.overlayEnabled.toggle()
            OverlayManager.shared.refresh()
        }
        shared.register(keyCode: UInt32(kVK_ANSI_M), modifiers: modifiers) {
            OverlayManager.shared.isMoveMode.toggle()
        }
    }

    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping @MainActor () -> Void) {
        installHandlerIfNeeded()
        let id = UInt32(handlers.count + 1)
        handlers[id] = handler
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4E_5753), id: id) // 'LNWS'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference)
        if status == noErr, let reference {
            references.append(reference)
        }
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
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
            guard status == noErr else { return status }
            let id = hotKeyID.id
            // Carbon delivers hotkey events on the main thread.
            MainActor.assumeIsolated { HotKeys.shared.fire(id) }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}
