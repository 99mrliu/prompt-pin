import AppKit
import Carbon.HIToolbox

/// Registers system-wide hot keys through Carbon's RegisterEventHotKey.
/// Unlike a global event tap this needs no Accessibility permission.
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handler: (() -> Void)?
    private var eventHandlerRef: EventHandlerRef?
    // 'PPIN'
    private static let signature = OSType(0x5050_494E)

    private init() {}

    /// - Parameters:
    ///   - keyCode: virtual key code, e.g. kVK_ANSI_P
    ///   - modifiers: Carbon modifier masks for equivalent shortcuts.
    func register(keyCode: UInt32, modifiers: [UInt32], handler: @escaping () -> Void) {
        unregister()
        self.handler = handler

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1, &eventSpec,
            userData,
            &eventHandlerRef)
        guard installStatus == noErr else {
            NSLog("PromptPin: InstallEventHandler failed \(installStatus)")
            self.handler = nil
            return
        }

        for (index, mask) in modifiers.enumerated() {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            let status = RegisterEventHotKey(
                keyCode, mask, hotKeyID,
                GetApplicationEventTarget(),
                0, &ref)
            if status == noErr, let ref {
                hotKeyRefs.append(ref)
                NSLog("PromptPin: hot key registered (modifiers \(mask))")
            } else {
                NSLog("PromptPin: RegisterEventHotKey failed \(status) (modifiers \(mask))")
            }
        }
        if hotKeyRefs.isEmpty { unregister() }
    }

    func unregister() {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        hotKeyRefs.removeAll()
        eventHandlerRef = nil
        handler = nil
    }

    fileprivate func fire() {
        // Hot-key callbacks are delivered on the main run loop.
        handler?()
    }
}

private let hotKeyEventHandler: EventHandlerProcPtr = { _, _, userData in
    guard let userData else { return noErr }
    Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue().fire()
    return noErr
}
