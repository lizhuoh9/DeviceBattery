import Foundation

/// What a device is; drives its glyph and where it sorts in the list.
public enum DeviceKind: String, Codable, Sendable, CaseIterable {
    case mouse, keyboard, trackpad, headphones, gamepad, speaker, other
}

/// Charging state as reported by the device.
public enum ChargeState: String, Codable, Sendable {
    case discharging, charging, full, unknown
}

/// Whether the device could be reached on the latest read.
public enum LinkStatus: String, Codable, Sendable {
    /// Answered with a battery level.
    case online
    /// Paired but not reachable right now: sleeping, switched off or out of range.
    case asleep
    /// macOS refused access to the HID interface (Input Monitoring is off).
    case needsPermission
}

/// One battery inside a multi-battery device, e.g. an AirPods bud or its case.
public struct BatteryComponent: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case left, right, chargingCase
    }

    public let role: Role
    public let level: Int

    public init(role: Role, level: Int) {
        self.role = role
        self.level = level
    }
}

/// A battery reading for one device, as produced by a reader.
public struct DeviceReading: Codable, Equatable, Sendable, Identifiable {
    /// Stable across launches, e.g. `logi.1A2B3C4D` or `bt.AA:BB:CC:DD:EE:10`.
    public let id: String
    public let name: String
    public let kind: DeviceKind
    /// 0...100, or nil when the device could not report one this time.
    public let level: Int?
    public let charge: ChargeState
    public let status: LinkStatus
    public let components: [BatteryComponent]
    /// SF Symbol override for devices with a dedicated glyph, e.g. `airpods.pro`.
    public let symbol: String?
    /// Where the reading came from, e.g. `Logi Bolt`.
    public let source: String
    public let date: Date

    public init(
        id: String,
        name: String,
        kind: DeviceKind,
        level: Int?,
        charge: ChargeState = .unknown,
        status: LinkStatus,
        components: [BatteryComponent] = [],
        symbol: String? = nil,
        source: String,
        date: Date
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.level = level.map { min(max($0, 0), 100) }
        self.charge = charge
        self.status = status
        self.components = components
        self.symbol = symbol
        self.source = source
        self.date = date
    }

    /// A copy with a different display name.
    public func renamed(_ newName: String) -> DeviceReading {
        DeviceReading(
            id: id, name: newName, kind: kind, level: level, charge: charge, status: status,
            components: components, symbol: symbol, source: source, date: date
        )
    }
}

extension ChargeState {
    /// Maps a plain "is it charging" flag, treating a charging device at 100% as full.
    static func from(charging: Bool, level: Int) -> ChargeState {
        guard charging else { return .discharging }
        return level >= 100 ? .full : .charging
    }
}
