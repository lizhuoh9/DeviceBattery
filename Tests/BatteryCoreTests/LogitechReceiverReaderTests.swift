import Foundation
import Testing
@testable import BatteryCore

/// A Bolt receiver with an MX Keys S in slot 1, scripted after real captures.
@MainActor
final class BoltSimulator {
    var online = true
    var features: [UInt16: UInt8] = [0x1004: 0x08, 0x0005: 0x03]
    var batteryCall: (index: UInt8, function: UInt8) = (0x08, 1)
    var battery: [UInt8] = [0x56, 0x04, 0x00, 0x00]
    var name = "MX Keys S"
    var exposesRegisters = true

    func respond(_ request: [UInt8]) -> Result<[UInt8], ChannelError> {
        let (device, sub, tag) = (request[1], request[2], request[3])
        if device == 0xFF { return register(request) }
        guard device == 1 else { return .success([0x10, device, 0x8F, sub, tag, 0x09, 0x00]) }
        guard online else { return .success([0x10, device, 0x8F, sub, tag, 0x04, 0x00]) }
        let reply = { (params: [UInt8]) in Result<[UInt8], ChannelError>.success(report([0x11, device, sub, tag] + params, length: 20)) }
        switch (sub, tag >> 4) {
        case (0x00, 0): return reply([features[UInt16(request[4]) << 8 | UInt16(request[5])] ?? 0])
        case (0x00, 1): return reply([0x04, 0x05, request[6]])
        case (0x03, 0): return reply([UInt8(name.utf8.count)])
        case (0x03, 1): return reply(Array(name.utf8.dropFirst(Int(request[4])).prefix(16)))
        case (0x03, 2): return reply([0x00])
        case (batteryCall.index, batteryCall.function): return reply(battery)
        default: return .success(report([0x11, device, 0xFF, sub, tag, 0x02], length: 20))
        }
    }

    private func register(_ request: [UInt8]) -> Result<[UInt8], ChannelError> {
        switch (exposesRegisters, request[4]) {
        case (true, 0x51):
            .success([0x11, 0xFF, 0x83, 0xB5, 0x51, 0x41, 0x80, 0xB3, 0x1A, 0x2B, 0x3C, 0x4D,
                      0x01, 0x00, 0x80, 0x14, 0x01, 0x00, 0x00, 0x00])
        case (true, 0x61):
            .success(report([0x11, 0xFF, 0x83, 0xB5, 0x61, 0x01, 0x09] + Array("MX KEYS B".utf8), length: 20))
        default:
            .success([0x10, 0xFF, 0x8F, 0x83, 0xB5, exposesRegisters ? 0x08 : 0x02, 0x00])
        }
    }
}

@Suite("Logitech receiver reader")
@MainActor
struct LogitechReceiverReaderTests {
    let date = Date(timeIntervalSince1970: 3_000)
    let device = BoltSimulator()

    func reader(_ kind: LogitechReceiverKind = .bolt) -> (LogitechReceiverReader, FakeChannel) {
        let channel = FakeChannel { [device] in device.respond($0) }
        let reader = LogitechReceiverReader(
            channel: channel, receiver: kind, receiverID: "loc1130000", strings: Strings(.simplifiedChinese), now: { self.date }
        )
        return (reader, channel)
    }

    @Test("reads an awake MX Keys S through the Bolt receiver")
    func awake() async {
        let readings = await reader().0.read()
        #expect(readings == [DeviceReading(
            id: "logi.1A2B3C4D", name: "MX Keys S", kind: .keyboard, level: 86,
            charge: .discharging, status: .online, source: "Logi Bolt", date: date
        )])
    }

    @Test("a sleeping keyboard is listed by its receiver codename")
    func asleep() async {
        device.online = false
        let readings = await reader().0.read()
        #expect(readings == [DeviceReading(
            id: "logi.1A2B3C4D", name: "MX KEYS B", kind: .keyboard, level: nil,
            status: .asleep, source: "Logi Bolt", date: date
        )])
    }

    @Test("features and pairings are looked up once, then one request per device")
    func caching() async {
        let (reader, channel) = reader()
        _ = await reader.read()
        let before = channel.sent.count
        let second = await reader.read()
        #expect(channel.sent.count - before == 1)
        #expect(second.first?.level == 86)
    }

    @Test("falls back to the battery status feature")
    func batteryStatus() async {
        device.features = [0x1000: 0x06, 0x0005: 0x03]
        device.batteryCall = (0x06, 0)
        device.battery = [0x1E, 0x0A, 0x01]
        let readings = await reader().0.read()
        #expect(readings.first?.level == 30)
        #expect(readings.first?.charge == .charging)
    }

    @Test("a device without a battery feature is left out")
    func noBattery() async {
        device.features = [0x0005: 0x03]
        #expect(await reader().0.read().isEmpty)
    }

    @Test("keeps the HID++ name after the device falls asleep")
    func nameSticks() async {
        let (reader, _) = reader()
        _ = await reader.read()
        device.online = false
        let readings = await reader.read()
        #expect(readings.first?.name == "MX Keys S")
        #expect(readings.first?.status == .asleep)
    }

    @Test("a device that went away has its features looked up again when it returns")
    func revalidatesAfterReconnect() async {
        let (reader, _) = reader()
        _ = await reader.read()
        device.online = false
        _ = await reader.read()
        // New firmware moved the battery feature while the keyboard was away.
        device.features = [0x1004: 0x09, 0x0005: 0x03]
        device.batteryCall = (0x09, 1)
        device.online = true
        let readings = await reader.read()
        #expect(readings.first?.status == .online)
        #expect(readings.first?.level == 86)
    }

    @Test("an all-zero battery reply is not shown as an empty battery")
    func zeroReply() async {
        device.battery = [0x00, 0x00, 0x00, 0x00]
        let readings = await reader().0.read()
        #expect(readings.first?.level == nil)
        #expect(readings.first?.status == .asleep)
    }

    @Test("only connection changes and battery broadcasts ask for a refresh")
    func notices() async {
        let (reader, _) = reader()
        _ = await reader.read()
        #expect(reader.notice([0x10, 0x01, 0x41, 0x10, 0x01, 0x80, 0xB3]))
        #expect(reader.notice(report([0x11, 0x01, 0x08, 0x00, 0x50, 0x04, 0x01], length: 20)))
        #expect(!reader.notice(report([0x11, 0x01, 0x0A, 0x00, 0x01], length: 20)))
        #expect(!reader.notice(report([0x11, 0x01, 0x08, 0x1B, 0x50], length: 20)))
    }

    @Test("a connection from a device we have not listed re-reads the pairings")
    func newPairing() async {
        let (reader, channel) = reader()
        _ = await reader.read()
        let registerReads = { channel.sent.filter { $0[1] == 0xFF }.count }
        let before = registerReads()
        _ = await reader.read()
        #expect(registerReads() == before)
        #expect(reader.notice([0x10, 0x02, 0x41, 0x10, 0x02, 0x40, 0x40]))
        _ = await reader.read()
        #expect(registerReads() > before)
    }

    @Test("receivers without pairing registers are probed by device index")
    func probing() async {
        device.exposesRegisters = false
        let readings = await reader(.other).0.read()
        #expect(readings.map(\.id) == ["logi.loc1130000.1"])
        #expect(readings.first?.name == "MX Keys S")
        #expect(readings.first?.source == "Logitech")
    }
}
