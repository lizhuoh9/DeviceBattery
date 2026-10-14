import Foundation

/// Reads every device paired with one Logitech receiver over HID++.
///
/// Pairings come from the receiver's registers (Bolt / Unifying) or, for other receivers,
/// from pinging device indices 1...6. Each device's battery feature and name are looked up
/// when it connects; while it stays connected a read costs one request per device.
@MainActor
public final class LogitechReceiverReader: BatteryReader {
    private static let receiverTimeout = Duration.milliseconds(800)
    private static let deviceTimeout = Duration.milliseconds(1500)
    private static let rediscoveryInterval: TimeInterval = 30 * 60
    /// The receiver answers this for a paired device it cannot reach right now.
    private static let deviceAsleepError: UInt8 = 0x04
    /// Device names are short; this bounds the name loop against a bogus length byte.
    private static let maxNameLength = 64

    private enum BatteryLookup {
        case found(HIDPPFeature, index: UInt8)
        case absent
    }

    /// What a device told us about itself; kept while it sleeps.
    private struct Identity {
        var name: String?
        var kind: DeviceKind?
        var batteryIndex: UInt8?
    }

    private let channel: ReportChannel
    private let receiver: LogitechReceiverKind
    private let receiverID: String
    private let strings: Strings
    private let now: () -> Date
    private var slots: [PairedSlot] = []
    private var discoveredAt: Date?
    /// Battery feature per device, valid for its current connection only.
    private var batteries: [String: BatteryLookup] = [:]
    private var identities: [String: Identity] = [:]

    public init(
        channel: ReportChannel,
        receiver: LogitechReceiverKind,
        receiverID: String,
        strings: Strings,
        now: @escaping () -> Date = Date.init
    ) {
        self.channel = channel
        self.receiver = receiver
        self.receiverID = receiverID
        self.strings = strings
        self.now = now
    }

    public func read() async -> [DeviceReading] {
        await discoverIfNeeded()
        var readings: [DeviceReading] = []
        for slot in slots {
            if let reading = await read(slot) {
                readings.append(reading)
            }
        }
        return readings
    }

    /// Forces the pairing list to be read again on the next `read()`.
    public func invalidatePairings() {
        discoveredAt = nil
    }

    /// Looks at a report the receiver sent on its own. Returns true when it is worth a read:
    /// a device connected or disconnected, or broadcast a battery change.
    public func notice(_ report: [UInt8]) -> Bool {
        guard report.count >= 7, report[0] == HIDPP.shortReportID || report[0] == HIDPP.longReportID,
              (1...6).contains(report[1]) else { return false }
        let slot = slots.first { $0.index == report[1] }
        if report[2] == HIDPP.connectionNotification {
            // Whatever is in that slot now gets its features looked up again.
            if let slot { batteries[id(of: slot)] = nil } else { invalidatePairings() }
            return true
        }
        guard report[3] & 0x0F == 0, let slot,
              let batteryIndex = identities[id(of: slot)]?.batteryIndex else { return false }
        return report[2] == batteryIndex
    }

    // MARK: - Pairings

    private func discoverIfNeeded() async {
        let interval = receiver == .other ? 0 : Self.rediscoveryInterval
        if let discoveredAt, now().timeIntervalSince(discoveredAt) < interval { return }
        let found = receiver == .other ? await probeSlots() : await readPairingRegisters()
        // A silent receiver keeps the previous list; try again next time.
        guard let found else { return }
        slots = found
        discoveredAt = now()
    }

    private func readPairingRegisters() async -> [PairedSlot]? {
        var found: [PairedSlot] = []
        for index in UInt8(1)...6 {
            guard let request = HIDPPReceiverInfo.pairingRequest(slot: index, receiver: receiver) else { continue }
            guard let reply = await send(request, timeout: Self.receiverTimeout) else { return nil }
            guard case let .success(params) = reply else { continue }
            let extended = receiver == .unifying
                ? await registerParams(HIDPPReceiverInfo.extendedPairingRequest(slot: index))
                : nil
            guard var slot = HIDPPReceiverInfo.parsePairing(params, slot: index, receiver: receiver, extended: extended) else {
                continue
            }
            if let nameRequest = HIDPPReceiverInfo.nameRequest(slot: index, receiver: receiver),
               let nameParams = await registerParams(nameRequest) {
                slot.codename = HIDPPReceiverInfo.parseCodename(nameParams, receiver: receiver)
            }
            found.append(slot)
        }
        return found
    }

    /// Receivers without pairing registers: a device answers, or the receiver says it is asleep.
    private func probeSlots() async -> [PairedSlot]? {
        var found: [PairedSlot] = []
        var receiverAnswered = false
        for index in UInt8(1)...6 {
            switch await ping(index) {
            case .success?, .unreachable(Self.deviceAsleepError)?:
                receiverAnswered = true
                found.append(PairedSlot(index: index, kind: .other, serial: nil))
            case .unreachable?, .featureError?:
                receiverAnswered = true
            case nil:
                continue
            }
        }
        return receiverAnswered ? found : nil
    }

    private func registerParams(_ request: [UInt8]) async -> [UInt8]? {
        guard case let .success(params)? = await send(request, timeout: Self.receiverTimeout) else { return nil }
        return params
    }

    // MARK: - Devices

    private func read(_ slot: PairedSlot) async -> DeviceReading? {
        let key = id(of: slot)
        if batteries[key] == nil {
            guard case .success? = await ping(slot.index), let battery = await learn(slot.index, key: key) else {
                return reading(slot, battery: nil)
            }
            batteries[key] = battery
        }
        guard case let .found(feature, featureIndex)? = batteries[key] else { return nil }

        let request = HIDPP.request(device: slot.index, featureIndex: featureIndex, function: feature.statusFunction)
        guard case let .success(params)? = await send(request, timeout: Self.deviceTimeout) else {
            // Gone or changed: look its features up again once it answers, so a cached index
            // is never sent to a different device or firmware.
            batteries[key] = nil
            return reading(slot, battery: nil)
        }
        let state = decode(feature, params)
        // A live device cannot be at 0% unless it is charging; treat that as "unknown".
        guard state.level > 0 || state.charge == .charging || state.charge == .full else {
            return reading(slot, battery: nil)
        }
        return reading(slot, battery: state)
    }

    /// Looks up the battery feature, name and type of a freshly connected device;
    /// nil when it stopped answering.
    private func learn(_ device: UInt8, key: String) async -> BatteryLookup? {
        var battery = BatteryLookup.absent
        for feature in HIDPPFeature.batteries {
            guard let index = await featureIndex(of: feature, on: device) else { return nil }
            if index != 0 {
                battery = .found(feature, index: index)
                break
            }
        }
        var identity = identities[key] ?? Identity()
        if case let .found(_, index) = battery { identity.batteryIndex = index }
        if let nameIndex = await featureIndex(of: .deviceName, on: device), nameIndex != 0 {
            identity.name = await deviceName(device, featureIndex: nameIndex) ?? identity.name
            identity.kind = await deviceKind(device, featureIndex: nameIndex) ?? identity.kind
        }
        identities[key] = identity
        return battery
    }

    /// The feature's index on the device: 0 when it lacks it, nil when the call failed.
    private func featureIndex(of feature: HIDPPFeature, on device: UInt8) async -> UInt8? {
        let id = feature.rawValue
        let request = HIDPP.request(device: device, featureIndex: 0, function: 0, params: [UInt8(id >> 8), UInt8(id & 0xFF)])
        guard case let .success(params)? = await send(request, timeout: Self.deviceTimeout) else { return nil }
        return params.byte(at: 0)
    }

    private func deviceName(_ device: UInt8, featureIndex: UInt8) async -> String? {
        let countRequest = HIDPP.request(device: device, featureIndex: featureIndex, function: 0)
        guard case let .success(countParams)? = await send(countRequest, timeout: Self.deviceTimeout) else { return nil }
        let length = min(Int(countParams.byte(at: 0)), Self.maxNameLength)
        var bytes: [UInt8] = []
        while bytes.count < length {
            let request = HIDPP.request(device: device, featureIndex: featureIndex, function: 1, params: [UInt8(bytes.count)])
            guard case let .success(chunk)? = await send(request, timeout: Self.deviceTimeout) else { return nil }
            let part = chunk.prefix(length - bytes.count)
            guard !part.isEmpty else { break }
            bytes += part
        }
        let name = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private func deviceKind(_ device: UInt8, featureIndex: UInt8) async -> DeviceKind? {
        let request = HIDPP.request(device: device, featureIndex: featureIndex, function: 2)
        guard case let .success(params)? = await send(request, timeout: Self.deviceTimeout) else { return nil }
        let kind = HIDPPReceiverInfo.kind(deviceType: params.byte(at: 0))
        return kind == .other ? nil : kind
    }

    // MARK: - Helpers

    private func ping(_ device: UInt8) async -> HIDPP.Reply? {
        await send(HIDPP.request(device: device, featureIndex: 0, function: 1, params: [0, 0, 0x5A]), timeout: Self.deviceTimeout)
    }

    private func send(_ request: [UInt8], timeout: Duration) async -> HIDPP.Reply? {
        let report = try? await channel.exchange(request, timeout: timeout) { HIDPP.reply(to: request, in: $0) != nil }
        return report.flatMap { HIDPP.reply(to: request, in: $0) }
    }

    private func decode(_ feature: HIDPPFeature, _ params: [UInt8]) -> HIDPPBatteryState {
        switch feature {
        case .unifiedBattery: HIDPPBattery.decodeUnified(params)
        case .batteryVoltage: HIDPPBattery.decodeVoltage(params)
        default: HIDPPBattery.decodeStatus(params)
        }
    }

    private func id(of slot: PairedSlot) -> String {
        slot.serial.map { "logi.\($0)" } ?? "logi.\(receiverID).\(slot.index)"
    }

    private func reading(_ slot: PairedSlot, battery: HIDPPBatteryState?) -> DeviceReading {
        let identity = identities[id(of: slot)]
        return DeviceReading(
            id: id(of: slot),
            name: identity?.name ?? slot.codename ?? strings.logitechDevice,
            kind: identity?.kind ?? slot.kind,
            level: battery?.level,
            charge: battery?.charge ?? .unknown,
            status: battery == nil ? .asleep : .online,
            source: receiver.sourceName,
            date: now()
        )
    }
}
