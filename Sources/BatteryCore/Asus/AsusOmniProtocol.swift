import Foundation

/// Battery queries for devices on an ASUS ROG Omni receiver (0B05:1ACE), interface 2.
///
/// Every packet is a 64-byte vendor report, byte 0 being the report ID:
/// - `01 A0` lists the paired devices: little-endian product IDs every 4 bytes from byte 5.
/// - `03 12 07` asks a mouse: level in byte 5, charging in byte 10.
/// - `02 12 01` asks a keyboard: level in byte 6, charging in byte 9.
/// - The receiver answers `xx FF AA` when the addressed device is asleep or absent.
///
/// Sources: G-Helper's AsusMouse, rogctl's protocol notes, battery-tray's keyboard capture.
public enum AsusOmniProtocol {
    public static let vendorID = 0x0B05
    public static let receiverProductID = 0x1ACE
    /// Primary usage page of the interface carrying the vendor reports.
    public static let usagePage = 0xFF02
    static let packetLength = 64

    public enum BatteryReply: Equatable, Sendable {
        case level(Int, charging: Bool)
        case asleep
    }

    /// Where a device class keeps its battery query and answer.
    public enum Layout: CaseIterable, Sendable {
        case mouse, keyboard

        public var request: [UInt8] {
            switch self {
            case .mouse: [0x03, 0x12, 0x07].padded(to: AsusOmniProtocol.packetLength)
            case .keyboard: [0x02, 0x12, 0x01].padded(to: AsusOmniProtocol.packetLength)
            }
        }

        var kind: DeviceKind {
            switch self {
            case .mouse: .mouse
            case .keyboard: .keyboard
            }
        }

        fileprivate var levelByte: Int { self == .mouse ? 5 : 6 }
        fileprivate var chargingByte: Int { self == .mouse ? 10 : 9 }
    }

    public static let pairedRequest: [UInt8] = [0x01, 0xA0].padded(to: packetLength)

    public static func isPairedReply(_ report: [UInt8]) -> Bool {
        report.count > 5 && report[0] == 0x01 && report[1] == 0xA0
    }

    /// Product IDs of the paired devices, in receiver order.
    public static func parsePaired(_ report: [UInt8]) -> [UInt16] {
        guard isPairedReply(report) else { return [] }
        var ids: [UInt16] = []
        var offset = 5
        while offset + 1 < report.count {
            let id = UInt16(report[offset]) | UInt16(report[offset + 1]) << 8
            guard id != 0 else { break }
            ids.append(id)
            offset += 4
        }
        return ids
    }

    /// Whether `report` answers `layout`'s query, including the asleep rejection.
    public static func isReply(_ report: [UInt8], to layout: Layout) -> Bool {
        let request = layout.request
        guard report.count > 2, report[0] == request[0] else { return false }
        return (report[1] == request[1] && report[2] == request[2]) || isRejection(report)
    }

    public static func parseBattery(_ report: [UInt8], layout: Layout) -> BatteryReply? {
        guard isReply(report, to: layout) else { return nil }
        if isRejection(report) { return .asleep }
        let level = Int(report.byte(at: layout.levelByte))
        let charging = report.byte(at: layout.chargingByte) != 0
        guard level <= 100 else { return nil }
        if level == 0 && !charging { return .asleep }
        return .level(level, charging: charging)
    }

    private static func isRejection(_ report: [UInt8]) -> Bool {
        report.count > 2 && report[1] == 0xFF && report[2] == 0xAA
    }

    /// Known devices by the product ID the receiver reports (from G-Helper / rogctl).
    public static func model(for productID: UInt16) -> (name: String, kind: DeviceKind)? {
        knownModels[productID].map { ($0, .mouse) }
    }

    private static let knownModels: [UInt16: String] = [
        0x1B65: "ROG Harpe Ace Mini",
        0x1A94: "ROG Harpe Ace Aim Lab Edition",
        0x1B68: "ROG Harpe Ace Extreme", 0x1B69: "ROG Harpe Ace Extreme",
        0x1B1A: "ROG Keris II Ace", 0x1B18: "ROG Keris II Ace",
        0x1C0E: "ROG Keris II Origin", 0x1D4E: "ROG Keris II Origin",
        0x1A68: "ROG Keris Wireless Aimpoint", 0x1A6A: "ROG Keris Wireless Aimpoint",
        0x1A72: "ROG Gladius III Aimpoint",
        0x1AD7: "ROG Strix Impact III Wireless",
    ]
}
