import BatteryCore
import Foundation
import OSLog

/// User preferences and remembered readings, persisted in UserDefaults.
@MainActor
final class Settings {
    private enum Key {
        static let customNames = "customNames"
        static let hidden = "hiddenDevices"
        static let alwaysOnTop = "alwaysOnTop"
        static let lowBatteryAlerts = "lowBatteryAlerts"
        static let remembered = "rememberedReadings"
    }

    /// Remembered devices beyond this are dropped, oldest first.
    private static let memoryLimit = 40

    private let defaults: UserDefaults
    private let log = Logger(subsystem: "local.DeviceBattery", category: "settings")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.lowBatteryAlerts: true])
    }

    var customNames: [String: String] {
        get { defaults.dictionary(forKey: Key.customNames) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Key.customNames) }
    }

    var hidden: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.hidden) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Key.hidden) }
    }

    var alwaysOnTop: Bool {
        get { defaults.bool(forKey: Key.alwaysOnTop) }
        set { defaults.set(newValue, forKey: Key.alwaysOnTop) }
    }

    var lowBatteryAlerts: Bool {
        get { defaults.bool(forKey: Key.lowBatteryAlerts) }
        set { defaults.set(newValue, forKey: Key.lowBatteryAlerts) }
    }

    var remembered: [DeviceReading] {
        get {
            guard let data = defaults.data(forKey: Key.remembered) else { return [] }
            do {
                return try JSONDecoder().decode([DeviceReading].self, from: data)
            } catch {
                log.error("Dropping unreadable remembered readings: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }
        set {
            let recent = newValue.sorted { $0.date > $1.date }.prefix(Self.memoryLimit)
            do {
                defaults.set(try JSONEncoder().encode(Array(recent)), forKey: Key.remembered)
            } catch {
                log.error("Could not save readings: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func setCustomName(_ name: String?, for id: String) {
        var names = customNames
        names[id] = name.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        customNames = names
    }
}
