import Foundation

/// A decoded HID++ battery state.
public struct HIDPPBatteryState: Equatable, Sendable {
    public let level: Int
    public let charge: ChargeState

    public init(level: Int, charge: ChargeState) {
        self.level = level
        self.charge = charge
    }
}

/// Decoders for the three HID++ 2.0 battery features (after Solaar's `hidpp20.py`).
enum HIDPPBattery {
    /// UNIFIED_BATTERY (0x1004) get_status: state of charge, level flags, charging status.
    static func decodeUnified(_ params: [UInt8]) -> HIDPPBatteryState {
        let charge: ChargeState = switch params.byte(at: 2) {
        case 0: .discharging
        case 1, 2: .charging
        case 3: .full
        default: .unknown
        }
        let stateOfCharge = Int(params.byte(at: 0))
        let level = stateOfCharge > 0 ? stateOfCharge : approximateLevel(flags: params.byte(at: 1))
        return HIDPPBatteryState(level: charge == .full ? 100 : level, charge: charge)
    }

    /// BATTERY_STATUS (0x1000) getBatteryLevelStatus: level, next level, status.
    static func decodeStatus(_ params: [UInt8]) -> HIDPPBatteryState {
        let charge: ChargeState = switch params.byte(at: 2) {
        case 0: .discharging
        case 1, 2, 4: .charging
        case 3: .full
        default: .unknown
        }
        let level = Int(params.byte(at: 0))
        return HIDPPBatteryState(level: charge == .full ? 100 : level, charge: charge)
    }

    /// BATTERY_VOLTAGE (0x1001) getBatteryInfo: millivolts (big-endian) and flags.
    static func decodeVoltage(_ params: [UInt8]) -> HIDPPBatteryState {
        let millivolts = Int(params.byte(at: 0)) << 8 | Int(params.byte(at: 1))
        let flags = params.byte(at: 2)
        let charge: ChargeState = switch (flags & 0x80 != 0, flags & 0x03) {
        case (false, _): .discharging
        case (true, 1): .full
        case (true, _): .charging
        }
        let level = charge == .full ? 100 : percent(forMillivolts: millivolts)
        return HIDPPBatteryState(level: level, charge: charge)
    }

    /// Remaining charge of a single Li-ion cell at `millivolts` (Solaar's table).
    static func percent(forMillivolts millivolts: Int) -> Int {
        voltageCurve.first { $0.millivolts < millivolts }?.percent ?? 0
    }

    private static let voltageCurve: [(millivolts: Int, percent: Int)] = [
        (4186, 100), (4067, 90), (3989, 80), (3922, 70), (3859, 60), (3811, 50), (3778, 40),
        (3751, 30), (3717, 20), (3671, 10), (3646, 5), (3579, 2), (3500, 0),
    ]

    /// Devices that only report coarse levels: full / good / low / critical.
    private static func approximateLevel(flags: UInt8) -> Int {
        if flags & 0x08 != 0 { return 90 }
        if flags & 0x04 != 0 { return 50 }
        if flags & 0x02 != 0 { return 20 }
        if flags & 0x01 != 0 { return 5 }
        return 0
    }
}
