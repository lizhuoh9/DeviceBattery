import BatteryCore
import Foundation
import IOKit

/// Bluetooth devices macOS already tracks a battery for: AirPods, Magic accessories,
/// and other headsets / keyboards / mice that report one over Bluetooth.
enum BluetoothSource {
    static let key = "bluetooth"
    private static let profilerTimeout: TimeInterval = 10
    private static let profilerKillDelay: TimeInterval = 2

    /// Current Bluetooth readings; nil when system_profiler failed, so the previous ones stay.
    static func read() async -> [DeviceReading]? {
        let now = Date()
        guard let data = await runProfiler() else { return nil }
        let profiled = BluetoothProfileParser.parse(data, now: now)
        return BluetoothProfileParser.merge(registry: registryReadings(now: now), profiler: profiled)
    }

    /// Services that publish `BatteryPercent`; a cheap in-process registry lookup.
    private static func registryReadings(now: Date) -> [DeviceReading] {
        var iterator: io_iterator_t = 0
        let matching = ["IOPropertyExistsMatch": "BatteryPercent"] as CFDictionary
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var readings: [String: DeviceReading] = [:]
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dictionary = properties?.takeRetainedValue() as? [String: Any],
                  let reading = RegistryBatteryParser.reading(from: dictionary, now: now) else { continue }
            readings[reading.id] = reading
        }
        return Array(readings.values)
    }

    /// Runs `system_profiler SPBluetoothDataType -json` off the main thread (~70 ms).
    private static func runProfiler() async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
                process.arguments = ["SPBluetoothDataType", "-json"]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let pid = process.processIdentifier
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + profilerTimeout) {
                    guard process.isRunning else { return }
                    process.terminate()
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + profilerKillDelay) {
                        if process.isRunning { kill(pid, SIGKILL) }
                    }
                }
                let data = try? output.fileHandleForReading.readToEnd()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0 ? (data ?? Data()) : nil)
            }
        }
    }
}
