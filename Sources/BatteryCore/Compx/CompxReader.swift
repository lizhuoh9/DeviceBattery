import Foundation

/// Reads the battery of the one mouse behind a Compx dongle.
@MainActor
public final class CompxReader: BatteryReader {
    static let source = "Compx 2.4G"

    private let channel: ReportChannel
    private let id: String
    private let name: String
    private let now: () -> Date

    public init(channel: ReportChannel, id: String, name: String, now: @escaping () -> Date = Date.init) {
        self.channel = channel
        self.id = id
        self.name = name
        self.now = now
    }

    public func read() async -> [DeviceReading] {
        do {
            let reply = try await channel.exchange(
                CompxProtocol.batteryRequest,
                timeout: .milliseconds(600),
                accept: CompxProtocol.isBatteryReply
            )
            guard case let .level(level, charging) = CompxProtocol.parseBattery(reply) else {
                return [reading(level: nil, charge: .unknown, status: .asleep)]
            }
            return [reading(level: level, charge: .from(charging: charging, level: level), status: .online)]
        } catch .notPermitted {
            return [reading(level: nil, charge: .unknown, status: .needsPermission)]
        } catch {
            return [reading(level: nil, charge: .unknown, status: .asleep)]
        }
    }

    private func reading(level: Int?, charge: ChargeState, status: LinkStatus) -> DeviceReading {
        DeviceReading(
            id: id, name: name, kind: .mouse, level: level, charge: charge,
            status: status, source: Self.source, date: now()
        )
    }
}
