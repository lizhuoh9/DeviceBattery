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

    public init(_ reading: DeviceReading, now: Date) {
        percent = reading.level.map(String.init) ?? "—"
        fraction = reading.level.map { Double($0) / 100 }
        tone = Self.tone(of: reading)
        detail = Self.detail(of: reading, now: now)
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

    private static func detail(of reading: DeviceReading, now: Date) -> String {
        switch reading.status {
        case .needsPermission:
            return "需要“输入监控”权限"
        case .asleep:
            return reading.level == nil ? "休眠中，唤醒后更新" : "休眠 · \(age(of: reading.date, now: now))"
        case .online:
            break
        }
        switch reading.charge {
        case .charging: return "充电中"
        case .full: return "已充满"
        default: break
        }
        if !reading.components.isEmpty {
            return reading.components.map { "\($0.label) \($0.level)%" }.joined(separator: " · ")
        }
        if let level = reading.level, level <= criticalThreshold { return "电量极低，请尽快充电" }
        if let level = reading.level, level <= lowThreshold { return "电量偏低" }
        return reading.source
    }

    /// "刚刚", "5 分钟前", "2 小时前", "3 天前".
    public static func age(of date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "刚刚"
        case ..<3600: return "\(Int(seconds / 60)) 分钟前"
        case ..<86_400: return "\(Int(seconds / 3600)) 小时前"
        default: return "\(Int(seconds / 86_400)) 天前"
        }
    }
}
