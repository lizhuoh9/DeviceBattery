import Foundation
import Testing
@testable import BatteryCore

@Suite("Compx protocol")
struct CompxProtocolTests {
    @Test("battery request is report 0x08, command 0x04 and a 0x55-based checksum")
    func batteryRequest() {
        let request = CompxProtocol.batteryRequest
        #expect(request.count == 17)
        #expect(request[0] == 0x08)
        #expect(request[1] == 0x04)
        #expect(request[2..<16].allSatisfy { $0 == 0 })
        #expect(request[16] == 0x49)
    }

    @Test("reads the level from byte 6 and the charging flag from byte 7")
    func parsesLevel() {
        let reply = report([0x08, 0x04, 0, 0, 0, 0, 76, 1], length: 17)
        #expect(CompxProtocol.parseBattery(reply) == .level(76, charging: true))
    }

    @Test("a zero level that is not charging means the mouse is off")
    func zeroMeansAsleep() {
        let reply = report([0x08, 0x04, 0, 0, 0, 0, 0, 0], length: 17)
        #expect(CompxProtocol.parseBattery(reply) == .asleep)
    }

    @Test("an out-of-range level is rejected")
    func rejectsGarbage() {
        let reply = report([0x08, 0x04, 0, 0, 0, 0, 0xC8, 0], length: 17)
        #expect(CompxProtocol.parseBattery(reply) == nil)
    }

    @Test("only claims replies to the battery command", arguments: [
        [UInt8]([0x08, 0x05, 0, 0, 0, 0, 50]),
        [0x09, 0x04, 0, 0, 0, 0, 50],
        [0x08, 0x04],
    ])
    func claimsOnlyBatteryReplies(bytes: [UInt8]) {
        #expect(!CompxProtocol.isBatteryReply(bytes))
    }

    @Test("only mouse dongles with a vendor interface big enough for the query are used")
    func interfaceSelection() {
        #expect(CompxProtocol.isBatteryInterface(
            vendorID: 0x373B, productID: 0x11D9, usagePage: 0xFF05, maxOutputReportSize: 49, product: "Wireless mouse 8k dongle-L"
        ))
        #expect(CompxProtocol.isBatteryInterface(
            vendorID: 0x3554, productID: 0xF58A, usagePage: 0xFF02, maxOutputReportSize: 17, product: "VXE MOUSE"
        ))
        // Keyboards and other products on the same chip use different commands.
        #expect(!CompxProtocol.isBatteryInterface(
            vendorID: 0x373B, productID: 0x1234, usagePage: 0xFF02, maxOutputReportSize: 64, product: "AULA F75 Keyboard"
        ))
        #expect(!CompxProtocol.isBatteryInterface(
            vendorID: 0x373B, productID: 0x11D9, usagePage: 0x0001, maxOutputReportSize: 49, product: "Wireless mouse 8k dongle-L"
        ))
        #expect(!CompxProtocol.isBatteryInterface(
            vendorID: 0x373B, productID: 0x11D9, usagePage: 0xFF05, maxOutputReportSize: 8, product: "Wireless mouse 8k dongle-L"
        ))
        #expect(!CompxProtocol.isBatteryInterface(
            vendorID: 0x046D, productID: 0x11D9, usagePage: 0xFF05, maxOutputReportSize: 49, product: "mouse"
        ))
    }

    @Test("cleans the dongle's USB name into a device name")
    func displayName() {
        #expect(CompxProtocol.displayName(forProduct: "Wireless mouse 8k dongle-L") == "Wireless mouse 8k")
        #expect(CompxProtocol.displayName(forProduct: "ATK Dongle") == "ATK")
        #expect(CompxProtocol.displayName(forProduct: "  ") == "无线鼠标")
    }
}

@Suite("Compx reader")
@MainActor
struct CompxReaderTests {
    let date = Date(timeIntervalSince1970: 1_000)

    func reader(_ channel: FakeChannel) -> CompxReader {
        CompxReader(channel: channel, id: "compx.000000000001", name: "Wireless mouse 8k", now: { self.date })
    }

    @Test("an answering mouse is online with its level")
    func online() async {
        let channel = FakeChannel { _ in .success(report([0x08, 0x04, 0, 0, 0, 0, 76, 0], length: 17)) }
        let readings = await reader(channel).read()
        #expect(readings == [DeviceReading(
            id: "compx.000000000001", name: "Wireless mouse 8k", kind: .mouse, level: 76,
            charge: .discharging, status: .online, source: "Compx 2.4G", date: date
        )])
        #expect(channel.sent == [CompxProtocol.batteryRequest])
    }

    @Test("a silent dongle means the mouse is asleep")
    func timeout() async {
        let readings = await reader(FakeChannel { _ in .failure(.timeout) }).read()
        #expect(readings.map(\.status) == [.asleep])
        #expect(readings.first?.level == nil)
    }

    @Test("a refused interface asks for Input Monitoring")
    func permission() async {
        let readings = await reader(FakeChannel { _ in .failure(.notPermitted) }).read()
        #expect(readings.map(\.status) == [.needsPermission])
    }

    @Test("charging at 100% counts as full")
    func full() async {
        let channel = FakeChannel { _ in .success(report([0x08, 0x04, 0, 0, 0, 0, 100, 1], length: 17)) }
        let readings = await reader(channel).read()
        #expect(readings.first?.charge == .full)
    }
}
