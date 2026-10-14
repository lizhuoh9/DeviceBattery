import Foundation

/// Reads every device paired with one ROG Omni receiver.
@MainActor
public final class AsusOmniReader: BatteryReader {
    static let source = "ROG Omni"
    private static let timeout = Duration.milliseconds(500)

    private let channel: ReportChannel
    private let receiverID: String
    private let strings: Strings
    private let now: () -> Date
    /// Device classes learned from the command each product answered.
    private var learnedKinds: [UInt16: DeviceKind] = [:]
    private var lastPaired: [UInt16] = []

    public init(channel: ReportChannel, receiverID: String, strings: Strings, now: @escaping () -> Date = Date.init) {
        self.channel = channel
        self.receiverID = receiverID
        self.strings = strings
        self.now = now
    }

    public func read() async -> [DeviceReading] {
        guard let paired = await pairedProducts() else {
            // The receiver itself did not answer: keep what it listed before.
            return lastPaired.map { asleepReading(for: $0) }
        }
        lastPaired = paired
        // The mouse and keyboard queries carry no product ID, so each class can only be
        // answered by one paired device: classes already known are not offered to others.
        var claimed = Set(paired.compactMap { kind(of: $0) })
        var readings: [DeviceReading] = []
        for productID in paired {
            let reading = await readDevice(productID, excluding: claimed)
            claimed.insert(reading.kind)
            readings.append(reading)
        }
        return readings
    }

    private func pairedProducts() async -> [UInt16]? {
        let reply = try? await channel.exchange(
            AsusOmniProtocol.pairedRequest, timeout: Self.timeout, accept: AsusOmniProtocol.isPairedReply
        )
        return reply.map(AsusOmniProtocol.parsePaired)
    }

    private func readDevice(_ productID: UInt16, excluding claimed: Set<DeviceKind>) async -> DeviceReading {
        for layout in layouts(for: productID, excluding: claimed) {
            let reply = try? await channel.exchange(layout.request, timeout: Self.timeout) {
                AsusOmniProtocol.isReply($0, to: layout)
            }
            guard let reply, case let .level(level, charging) = AsusOmniProtocol.parseBattery(reply, layout: layout) else {
                continue
            }
            learnedKinds[productID] = layout.kind
            return reading(
                for: productID, kind: layout.kind, level: level,
                charge: .from(charging: charging, level: level), status: .online
            )
        }
        return asleepReading(for: productID)
    }

    /// Which queries to try: the known class only, or every class no other device holds.
    private func layouts(for productID: UInt16, excluding claimed: Set<DeviceKind>) -> [AsusOmniProtocol.Layout] {
        switch kind(of: productID) {
        case .mouse: [.mouse]
        case .keyboard: [.keyboard]
        default: AsusOmniProtocol.Layout.allCases.filter { !claimed.contains($0.kind) }
        }
    }

    private func kind(of productID: UInt16) -> DeviceKind? {
        learnedKinds[productID] ?? AsusOmniProtocol.model(for: productID)?.kind
    }

    private func asleepReading(for productID: UInt16) -> DeviceReading {
        reading(for: productID, kind: kind(of: productID) ?? .other, level: nil, charge: .unknown, status: .asleep)
    }

    private func reading(
        for productID: UInt16, kind: DeviceKind, level: Int?, charge: ChargeState, status: LinkStatus
    ) -> DeviceReading {
        DeviceReading(
            id: "rog.\(receiverID).\(String(format: "%04X", productID))",
            name: AsusOmniProtocol.model(for: productID)?.name ?? strings.rogDevice(kind: kind),
            kind: kind, level: level, charge: charge, status: status,
            source: Self.source, date: now()
        )
    }

}
