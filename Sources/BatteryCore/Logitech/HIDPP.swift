import Foundation

/// Logitech HID++ framing, as spoken by Bolt / Unifying / Lightspeed receivers.
///
/// Short reports are `10 <device> <sub-ID or feature index> <function|software ID> p0 p1 p2`,
/// long reports start with `11` and carry 16 parameter bytes. Device 0xFF is the receiver.
/// See Logitech's HID++ 2.0 specification and Solaar.
public enum HIDPP {
    public static let vendorID = 0x046D
    /// Primary usage page of the receiver interface that carries HID++.
    public static let usagePage = 0xFF00

    static let shortReportID: UInt8 = 0x10
    static let longReportID: UInt8 = 0x11
    static let receiverIndex: UInt8 = 0xFF
    /// Tags our requests so replies to other software (Logi Options+) are not mistaken for ours.
    static let softwareID: UInt8 = 0x0B
    static let readLongRegisterSubID: UInt8 = 0x83
    /// HID++ 1.0 notification: a device connected to or disconnected from the receiver.
    static let connectionNotification: UInt8 = 0x41

    public enum Reply: Equatable, Sendable {
        /// Parameter bytes, starting at byte 4 of the report.
        case success([UInt8])
        /// HID++ 2.0 error from the device (`FF` frame).
        case featureError(UInt8)
        /// HID++ 1.0 error (`8F` frame). From a receiver, 0x04 means the device is asleep.
        case unreachable(UInt8)
    }

    /// A HID++ 2.0 feature call; `function` is 0...15.
    public static func request(device: UInt8, featureIndex: UInt8, function: UInt8, params: [UInt8] = []) -> [UInt8] {
        let isLong = params.count > 3
        let header = [isLong ? longReportID : shortReportID, device, featureIndex, (function << 4) | softwareID]
        return (header + params).padded(to: isLong ? 20 : 7)
    }

    /// A HID++ 1.0 long-register read addressed to the receiver.
    public static func registerRead(_ address: UInt8, params: [UInt8]) -> [UInt8] {
        ([shortReportID, receiverIndex, readLongRegisterSubID, address] + params).padded(to: 7)
    }

    /// Classifies `report` as the answer to `request`; nil when it answers something else.
    public static func reply(to request: [UInt8], in report: [UInt8]) -> Reply? {
        guard report.count >= 7, request.count >= 5,
              report[0] == shortReportID || report[0] == longReportID,
              report[1] == request[1] else { return nil }

        switch report[2] {
        case request[2] where report[3] == request[3]:
            // Register replies also echo the sub-register they answer.
            if request[2] == readLongRegisterSubID && report[4] != request[4] { return nil }
            return .success(Array(report[4...]))
        case 0x8F where report[3] == request[2] && report[4] == request[3]:
            return .unreachable(report[5])
        case 0xFF where report[3] == request[2] && report[4] == request[3]:
            return .featureError(report[5])
        default:
            return nil
        }
    }
}

/// HID++ 2.0 feature IDs used here.
enum HIDPPFeature: UInt16, CaseIterable, Sendable {
    case root = 0x0000
    case deviceName = 0x0005
    case batteryStatus = 0x1000
    case batteryVoltage = 0x1001
    case unifiedBattery = 0x1004

    /// Battery features in order of preference.
    static let batteries: [HIDPPFeature] = [.unifiedBattery, .batteryStatus, .batteryVoltage]

    /// Function that returns the current battery state.
    var statusFunction: UInt8 { self == .unifiedBattery ? 1 : 0 }
}
