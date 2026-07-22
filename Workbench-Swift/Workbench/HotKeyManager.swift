import AppKit
import Carbon.HIToolbox

/// Global hotkey ⌥⌘W: show/hide Workbench from any app.
/// Carbon's RegisterEventHotKey works without accessibility permissions.
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()
    private var hotKeyRef: EventHotKeyRef?

    func register() {
        guard hotKeyRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKeyManager.shared.toggleApp() }
            return noErr
        }, 1, &eventType, nil, nil)

        let hotKeyID = EventHotKeyID(signature: OSType(0x57424E48) /* 'WBNH' */, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_W),
                            UInt32(cmdKey | optionKey),
                            hotKeyID,
                            GetEventDispatcherTarget(),
                            0,
                            &hotKeyRef)
    }

    private func toggleApp() {
        if NSApp.isActive {
            NSApp.hide(nil)
        } else {
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.isVisible || $0.isMiniaturized }?.makeKeyAndOrderFront(nil)
        }
    }
}
