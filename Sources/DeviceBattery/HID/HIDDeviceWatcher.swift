import BatteryCore
import Foundation
import IOKit.hid

/// Watches for supported receivers being plugged in or out.
///
/// Matching only enumerates devices; nothing is opened until a session reads.
@MainActor
final class HIDDeviceWatcher {
    enum Change {
        case added(ReceiverSession)
        case removed(key: String)
    }

    var onChange: ((Change) -> Void)?
    private(set) var sessions: [String: ReceiverSession] = [:]
    /// Removal callbacks hand back the same IOHIDDevice object; its service may already be gone.
    private var keysByDevice: [ObjectIdentifier: String] = [:]
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

    private static let matching: [[String: Int]] = [
        [kIOHIDVendorIDKey: HIDPP.vendorID, kIOHIDPrimaryUsagePageKey: HIDPP.usagePage],
        [kIOHIDVendorIDKey: AsusOmniProtocol.vendorID, kIOHIDProductIDKey: AsusOmniProtocol.receiverProductID],
    ] + CompxProtocol.vendorIDs.sorted().map { [kIOHIDVendorIDKey: $0] }

    func start() {
        IOHIDManagerSetDeviceMatchingMultiple(manager, Self.matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<HIDDeviceWatcher>.fromOpaque(context).takeUnretainedValue().added(device)
            }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<HIDDeviceWatcher>.fromOpaque(context).takeUnretainedValue().removed(device)
            }
        }, context)
        // Common modes, so plug events are not held back while a menu or an alert is open.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    private func added(_ device: IOHIDDevice) {
        guard let session = ReceiverSession.make(for: device), sessions[session.key] == nil else { return }
        sessions[session.key] = session
        keysByDevice[ObjectIdentifier(device)] = session.key
        onChange?(.added(session))
    }

    private func removed(_ device: IOHIDDevice) {
        guard let key = keysByDevice.removeValue(forKey: ObjectIdentifier(device)),
              let session = sessions.removeValue(forKey: key) else { return }
        session.invalidate()
        onChange?(.removed(key: key))
    }
}
