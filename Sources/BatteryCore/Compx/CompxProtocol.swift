import Foundation

/// Battery query for Compx-chip 2.4 GHz dongles (VID 0x373B / 0x3554), used by many
/// 4K/8K gaming mice (ATK, VXE, MCHOSE, ...).
///
/// The dongle takes a 16-byte vendor output report with ID 0x08: command 0x04 asks
/// for the battery, and the last byte is `0x55 - sum(report ID + bytes 0...14)`.
/// The answer is an input report with the same ID and command:
/// byte 6 = level (%), byte 7 = charging flag (byte 0 being the report ID).
public enum CompxProtocol {
    public static let vendorIDs: Set<Int> = [0x373B, 0x3554]
    public static let reportID: UInt8 = 0x08
    static let batteryCommand: UInt8 = 0x04
    static let payloadLength = 16

    public enum BatteryReply: Equatable, Sendable {
        case level(Int, charging: Bool)
        /// The dongle answered but the mouse is off or asleep.
        case asleep
    }

    /// Report 0x08 carrying command 0x04 and its checksum.
    public static let batteryRequest: [UInt8] = {
        var payload = [UInt8](repeating: 0, count: payloadLength)
        payload[0] = batteryCommand
        let sum = payload.dropLast().reduce(Int(reportID)) { $0 + Int($1) }
        payload[payloadLength - 1] = UInt8(truncatingIfNeeded: 0x55 - sum)
        return [reportID] + payload
    }()

    /// Product IDs known to answer the battery command, besides dongles named as mouse dongles.
    static let knownProductIDs: Set<Int> = [0x11D9]

    /// Whether this HID interface is a mouse dongle's vendor interface that takes the query.
    /// Other products on the same chip (keyboards) use different commands, so they are left alone.
    public static func isBatteryInterface(
        vendorID: Int, productID: Int, usagePage: Int, maxOutputReportSize: Int, product: String
    ) -> Bool {
        guard vendorIDs.contains(vendorID), usagePage >= 0xFF00,
              maxOutputReportSize >= batteryRequest.count else { return false }
        let name = product.lowercased()
        return knownProductIDs.contains(productID) || (name.contains("mouse") && !name.contains("keyboard"))
    }

    /// Whether `report` answers the battery command.
    public static func isBatteryReply(_ report: [UInt8]) -> Bool {
        report.count > 7 && report[0] == reportID && report[1] == batteryCommand
    }

    /// Decodes a battery reply; nil when it is not one or carries an impossible level.
    public static func parseBattery(_ report: [UInt8]) -> BatteryReply? {
        guard isBatteryReply(report) else { return nil }
        let level = Int(report[6])
        let charging = report[7] != 0
        guard level <= 100 else { return nil }
        if level == 0 && !charging { return .asleep }
        return .level(level, charging: charging)
    }

    /// Turns the dongle's USB product string into a device name.
    public static func displayName(forProduct product: String) -> String {
        let cleaned = product
            .replacingOccurrences(of: #"(?i)\s*dongle(-\w+)?\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "无线鼠标" : cleaned
    }
}
