import Foundation

/// A device that just crossed a low-battery threshold.
public struct LowBatteryAlert: Equatable, Sendable {
    public let id: String
    public let name: String
    public let level: Int
    public let threshold: Int
}

/// Decides when to warn: once at 20% and once more at 10% per discharge,
/// re-armed when the device charges or climbs back above 25%.
public struct LowBatteryPolicy: Sendable {
    static let thresholds = [RowPresentation.lowThreshold, RowPresentation.criticalThreshold]
    static let rearmLevel = 25

    /// Device ID → lowest threshold already announced.
    private var announced: [String: Int] = [:]

    public init() {}

    public mutating func evaluate(_ readings: [DeviceReading]) -> [LowBatteryAlert] {
        var alerts: [LowBatteryAlert] = []
        for reading in readings {
            if let alert = evaluate(reading) { alerts.append(alert) }
        }
        return alerts
    }

    private mutating func evaluate(_ reading: DeviceReading) -> LowBatteryAlert? {
        guard reading.status == .online, let level = reading.level else { return nil }
        if reading.charge == .charging || reading.charge == .full || level > Self.rearmLevel {
            announced[reading.id] = nil
            return nil
        }
        guard let threshold = Self.thresholds.filter({ level <= $0 }).min(),
              threshold < announced[reading.id] ?? Int.max else { return nil }
        announced[reading.id] = threshold
        return LowBatteryAlert(id: reading.id, name: reading.name, level: level, threshold: threshold)
    }
}
