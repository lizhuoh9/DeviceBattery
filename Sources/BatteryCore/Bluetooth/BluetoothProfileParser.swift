import Foundation

/// Turns `system_profiler SPBluetoothDataType -json` output into readings.
///
/// Only connected devices that report at least one battery level are kept.
/// AirPods-style devices report left/right/case; everything else a single "Main" level.
public enum BluetoothProfileParser {
    /// Source of Bluetooth readings; `Strings.source(_:)` translates it for display.
    public static let source = "Bluetooth"

    private static let levelKeys: [(key: String, role: BatteryComponent.Role)] = [
        ("device_batteryLevelLeft", .left),
        ("device_batteryLevelRight", .right),
        ("device_batteryLevelCase", .chargingCase),
    ]

    public static func parse(_ data: Data, now: Date) -> [DeviceReading] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        return controllers
            .flatMap { $0["device_connected"] as? [[String: Any]] ?? [] }
            .flatMap { entry in entry.compactMap { name, info in reading(name: name, info: info, now: now) } }
    }

    /// Combines IOKit readings (live level) with system_profiler ones (user-visible name, buds).
    public static func merge(registry: [DeviceReading], profiler: [DeviceReading]) -> [DeviceReading] {
        let live = Dictionary(registry.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let merged = profiler.map { device in live[device.id]?.renamed(device.name) ?? device }
        let profiled = Set(profiler.map(\.id))
        return merged + registry.filter { !profiled.contains($0.id) }
    }

    private static func reading(name: String, info: Any, now: Date) -> DeviceReading? {
        guard let info = info as? [String: Any], let address = info["device_address"] as? String else { return nil }
        let components = levelKeys.compactMap { key, role in
            percent(info[key]).map { BatteryComponent(role: role, level: $0) }
        }
        let main = percent(info["device_batteryLevelMain"]) ?? percent(info["device_batteryLevel"])
        let buds = components.filter { $0.role != .chargingCase }.map(\.level)
        guard let level = main ?? buds.min() ?? components.first?.level else { return nil }

        let minorType = info["device_minorType"] as? String ?? ""
        let isApple = (info["device_vendorID"] as? String)?.lowercased() == "0x004c"
        let kind = kind(minorType: minorType, name: name)
        return DeviceReading(
            id: "bt.\(address.uppercased())", name: name, kind: kind, level: level,
            status: .online, components: components, symbol: symbol(kind: kind, name: name, isApple: isApple),
            source: source, date: now
        )
    }

    /// "85%" → 85.
    private static func percent(_ value: Any?) -> Int? {
        guard let text = value as? String else { return value as? Int }
        return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }

    static func kind(minorType: String, name: String) -> DeviceKind {
        let type = minorType.lowercased()
        if type.contains("mouse") { return .mouse }
        if type.contains("keyboard") { return .keyboard }
        if type.contains("trackpad") { return .trackpad }
        if type.contains("head") || name.localizedCaseInsensitiveContains("airpods") { return .headphones }
        if type.contains("game") || type.contains("joystick") { return .gamepad }
        if type.contains("speaker") { return .speaker }
        return .other
    }

    static func symbol(kind: DeviceKind, name: String, isApple: Bool) -> String? {
        switch kind {
        case .headphones where name.localizedCaseInsensitiveContains("airpods max"): "airpods.max"
        case .headphones where name.localizedCaseInsensitiveContains("airpods pro"): "airpods.pro"
        case .headphones where name.localizedCaseInsensitiveContains("airpods"): "airpods"
        case .mouse where isApple: "magicmouse"
        default: nil
        }
    }
}

/// Reads an IOKit service that publishes `BatteryPercent` (Apple Magic accessories and
/// other HID devices the OS tracks a battery for).
public enum RegistryBatteryParser {
    public static func reading(from properties: [String: Any], now: Date, strings: Strings) -> DeviceReading? {
        // Built-in services (the Mac's own parts) are not accessories.
        guard let level = properties["BatteryPercent"] as? Int, properties["Built-In"] as? Bool != true else {
            return nil
        }
        let name = properties["Product"] as? String ?? strings.bluetoothDevice
        let flags = properties["BatteryStatusFlags"] as? Int ?? 0
        let address = (properties["DeviceAddress"] as? String)?
            .replacingOccurrences(of: "-", with: ":").uppercased()
        let kind = BluetoothProfileParser.kind(minorType: name, name: name)
        let isApple = (properties["VendorID"] as? Int) == 0x004C || name.hasPrefix("Magic")
        return DeviceReading(
            id: address.map { "bt.\($0)" } ?? "hid.\(name)", name: name, kind: kind, level: level,
            charge: .from(charging: flags & 0x02 != 0, level: level), status: .online,
            symbol: BluetoothProfileParser.symbol(kind: kind, name: name, isApple: isApple),
            source: BluetoothProfileParser.source, date: now
        )
    }
}
