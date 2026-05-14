import AppKit
import Carbon.HIToolbox

final class GlobalHotKey {
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    private static let signature: OSType = {
        let chars: [UInt8] = [UInt8(ascii: "s"), UInt8(ascii: "s"), UInt8(ascii: "M"), UInt8(ascii: "K")]
        return (OSType(chars[0]) << 24) | (OSType(chars[1]) << 16) | (OSType(chars[2]) << 8) | OSType(chars[3])
    }()
    private static var nextID: UInt32 = 1
    private static var instances: [UInt32: GlobalHotKey] = [:]
    private static var sharedHandler: EventHandlerRef?

    init() {
        Self.nextID += 1
        self.id = Self.nextID
        Self.instances[id] = self
        Self.installSharedHandlerIfNeeded()
    }

    deinit {
        unregister()
        Self.instances.removeValue(forKey: id)
    }

    func reconfigure(enabled: Bool, keyCode: UInt32, modifiers: UInt32) {
        unregister()
        guard enabled, modifiers != 0 else { return }
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hkID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        }
    }

    private func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private static func installSharedHandlerIfNeeded() {
        guard sharedHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, _ -> OSStatus in
                guard let eventRef else { return noErr }
                var hkID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard status == noErr else { return noErr }
                if let inst = GlobalHotKey.instances[hkID.id] {
                    DispatchQueue.main.async { inst.onTrigger?() }
                }
                return noErr
            },
            1,
            &spec,
            nil,
            &sharedHandler
        )
    }
}
