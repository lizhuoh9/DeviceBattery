import Foundation

/// The visual emphasis of a row; the UI maps it onto colors.
public enum RowTone: Sendable, Equatable {
    case normal, low, critical, charging, inactive, attention
}

/// Text and tone for one device row, independent of AppKit.
public struct RowPresentation: Equatable, Sendable {
    public static let lowThreshold = 20
    public static let criticalThreshold = 10

    public let percent: String
    public let detail: String
    public let tone: RowTone
    /// 0...1 for the ring; nil draws an empty ring.
    public let fraction: Double?

    public init(_ reading: DeviceReading, now: Date, strings: Strings) {
        percent = reading.level.map(String.init) ?? "—"
        fraction = reading.level.map { Double($0) / 100 }
        tone = Self.tone(of: reading)
        detail = Self.detail(of: reading, now: now, strings: strings)
    }

    private static func tone(of reading: DeviceReading) -> RowTone {
        switch reading.status {
        case .needsPermission: return .attention
        case .asleep: return .inactive
        case .online: break
        }
        if reading.charge == .charging || reading.charge == .full { return .charging }
        guard let level = reading.level else { return .normal }
        if level <= criticalThreshold { return .critical }
        if level <= lowThreshold { return .low }
        return .normal
    }

    private static func detail(of reading: DeviceReading, now: Date, strings: Strings) -> String {
        switch reading.status {
        case .needsPermission:
            return strings.needsInputMonitoring
        case .asleep:
            guard reading.level != nil else { return strings.asleepUntilWake }
            return strings.asleep(since: strings.age(of: reading.date, now: now))
        case .online:
            break
        }
        switch reading.charge {
        case .charging: return strings.charging
        case .full: return strings.fullyCharged
        default: break
        }
        if !reading.components.isEmpty {
            return reading.components.map { "\(strings.component($0.role)) \($0.level)%" }.joined(separator: " · ")
        }
        if let level = reading.level, level <= criticalThreshold { return strings.criticalBattery }
        if let level = reading.level, level <= lowThreshold { return strings.lowBattery }
        return strings.source(reading.source)
    }
}
