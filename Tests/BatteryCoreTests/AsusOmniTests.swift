import Foundation
import Testing
@testable import BatteryCore

@Suite("ROG Omni protocol")
struct AsusOmniProtocolTests {
    @Test("requests are 64-byte vendor reports")
    func requests() {
        #expect(AsusOmniProtocol.pairedRequest == report([0x01, 0xA0], length: 64))
        #expect(AsusOmniProtocol.Layout.mouse.request == report([0x03, 0x12, 0x07], length: 64))
        #expect(AsusOmniProtocol.Layout.keyboard.request == report([0x02, 0x12, 0x01], length: 64))
    }

    @Test("parses the paired product IDs captured from a real receiver")
    func pairedCapture() {
        let reply = report([0x01, 0xA0, 0x00, 0x01, 0x00, 0x06, 0x1B, 0x02, 0x04], length: 64)
        #expect(AsusOmniProtocol.parsePaired(reply) == [0x1B06])
    }

    @Test("reads every 4-byte entry until a zero product ID")
    func pairedMany() {
        let reply = report([0x01, 0xA0, 0, 0, 0, 0x65, 0x1B, 0, 0, 0x1A, 0x1B, 0, 0, 0, 0], length: 64)
        #expect(AsusOmniProtocol.parsePaired(reply) == [0x1B65, 0x1B1A])
    }

    @Test("decodes a mouse reply: level in byte 5, charging in byte 10")
    func mouseReply() {
        let reply = report([0x03, 0x12, 0x07, 0, 0, 0x50, 0x02, 0x14, 0xD8, 0x0F, 0x00, 0, 0x01], length: 64)
        #expect(AsusOmniProtocol.parseBattery(reply, layout: .mouse) == .level(80, charging: false))
    }

    @Test("decodes a keyboard reply: level in byte 6, charging in byte 9")
    func keyboardReply() {
        let reply = report([0x02, 0x12, 0x01, 0, 0, 0, 0x57, 0, 0, 0x01], length: 64)
        #expect(AsusOmniProtocol.parseBattery(reply, layout: .keyboard) == .level(87, charging: true))
    }

    @Test("FF AA from the receiver means the device is asleep", arguments: AsusOmniProtocol.Layout.allCases)
    func rejected(layout: AsusOmniProtocol.Layout) {
        let reply = report([layout.request[0], 0xFF, 0xAA], length: 64)
        #expect(AsusOmniProtocol.isReply(reply, to: layout))
        #expect(AsusOmniProtocol.parseBattery(reply, layout: layout) == .asleep)
    }

    @Test("a level byte above 100 is not a level")
    func rejectsImpossibleLevel() {
        let reply = report([0x03, 0x12, 0x07, 0, 0, 0xFF], length: 64)
        #expect(AsusOmniProtocol.parseBattery(reply, layout: .mouse) == nil)
    }

    @Test("does not claim replies for another report or command")
    func foreignReplies() {
        #expect(!AsusOmniProtocol.isReply(report([0x02, 0x12, 0x07], length: 64), to: .mouse))
        #expect(!AsusOmniProtocol.isReply(report([0x03, 0x12, 0x04], length: 64), to: .mouse))
        #expect(!AsusOmniProtocol.isPairedReply(report([0x01, 0x12, 0x07], length: 64)))
    }

    @Test("names known mice and leaves unknown products generic")
    func models() {
        #expect(AsusOmniProtocol.model(for: 0x1B65)?.name == "ROG Harpe Ace Mini")
        #expect(AsusOmniProtocol.model(for: 0x1B65)?.kind == .mouse)
        #expect(AsusOmniProtocol.model(for: 0x1B06) == nil)
    }
}

@Suite("ROG Omni reader")
@MainActor
struct AsusOmniReaderTests {
    let date = Date(timeIntervalSince1970: 2_000)
    static let pairedKeyboard = report([0x01, 0xA0, 0, 0x01, 0, 0x06, 0x1B, 0x02, 0x04], length: 64)
    static let pairedMouse = report([0x01, 0xA0, 0, 0x01, 0, 0x65, 0x1B, 0x01, 0x04], length: 64)

    func reader(_ channel: FakeChannel) -> AsusOmniReader {
        AsusOmniReader(channel: channel, receiverID: "OMNI0000TEST", now: { self.date })
    }

    @Test("an unknown device is identified by the command it answers")
    func learnsKind() async {
        let channel = FakeChannel { request in
            switch request[0] {
            case 0x01: .success(Self.pairedKeyboard)
            case 0x03: .success(report([0x03, 0xFF, 0xAA], length: 64))
            default: .success(report([0x02, 0x12, 0x01, 0, 0, 0, 64, 0, 0, 0], length: 64))
            }
        }
        let omni = reader(channel)
        let first = await omni.read()
        #expect(first == [DeviceReading(
            id: "rog.OMNI0000TEST.1B06", name: "ROG 无线键盘", kind: .keyboard, level: 64,
            charge: .discharging, status: .online, source: "ROG Omni", date: date
        )])
        let sentBefore = channel.sent.count
        _ = await omni.read()
        // Second round: paired list + keyboard query only.
        #expect(channel.sent.count - sentBefore == 2)
        #expect(channel.sent.last?[0] == 0x02)
    }

    @Test("a known mouse is only asked with the mouse command")
    func knownMouse() async {
        let channel = FakeChannel { request in
            request[0] == 0x01
                ? .success(Self.pairedMouse)
                : .success(report([0x03, 0x12, 0x07, 0, 0, 55, 0, 0, 0, 0, 1], length: 64))
        }
        let readings = await reader(channel).read()
        #expect(readings.first?.name == "ROG Harpe Ace Mini")
        #expect(readings.first?.level == 55)
        #expect(readings.first?.charge == .charging)
        #expect(channel.sent.map { $0[0] } == [0x01, 0x03])
    }

    @Test("an unknown device next to a known mouse is only asked as a keyboard")
    func knownMouseAndUnknownKeyboard() async {
        let paired = report([0x01, 0xA0, 0, 0x02, 0, 0x65, 0x1B, 0x01, 0x04, 0x06, 0x1B, 0x02, 0x04], length: 64)
        let channel = FakeChannel { request in
            switch request[0] {
            case 0x01: .success(paired)
            case 0x03: .success(report([0x03, 0x12, 0x07, 0, 0, 55], length: 64))
            default: .success(report([0x02, 0x12, 0x01, 0, 0, 0, 64], length: 64))
            }
        }
        let readings = await reader(channel).read()
        #expect(readings.map(\.kind) == [.mouse, .keyboard])
        #expect(readings.map(\.level) == [55, 64])
        #expect(channel.sent.map { $0[0] } == [0x01, 0x03, 0x02])
    }

    @Test("two unknown devices never learn the same class")
    func twoUnknownDevices() async {
        let paired = report([0x01, 0xA0, 0, 0x02, 0, 0x06, 0x1B, 0, 0, 0x99, 0x1C, 0, 0], length: 64)
        let channel = FakeChannel { request in
            switch request[0] {
            case 0x01: .success(paired)
            case 0x03: .success(report([0x03, 0x12, 0x07, 0, 0, 55], length: 64))
            default: .success(report([0x02, 0x12, 0x01, 0, 0, 0, 64], length: 64))
            }
        }
        let omni = reader(channel)
        for _ in 0..<2 {
            let readings = await omni.read()
            #expect(readings.map(\.kind) == [.mouse, .keyboard])
            #expect(readings.map(\.level) == [55, 64])
        }
    }

    @Test("a device that rejects every command is asleep")
    func asleep() async {
        let channel = FakeChannel { request in
            request[0] == 0x01
                ? .success(Self.pairedKeyboard)
                : .success(report([request[0], 0xFF, 0xAA], length: 64))
        }
        let readings = await reader(channel).read()
        #expect(readings.map(\.status) == [.asleep])
        #expect(readings.first?.name == "ROG 无线设备")
        #expect(readings.first?.kind == .other)
    }

    @Test("a silent receiver keeps the devices it listed before, as asleep")
    func silentReceiver() async {
        var answering = true
        let channel = FakeChannel { request in
            guard answering else { return .failure(.timeout) }
            return request[0] == 0x01
                ? .success(Self.pairedMouse)
                : .success(report([0x03, 0x12, 0x07, 0, 0, 55], length: 64))
        }
        let omni = reader(channel)
        _ = await omni.read()
        answering = false
        let readings = await omni.read()
        #expect(readings.map(\.id) == ["rog.OMNI0000TEST.1B65"])
        #expect(readings.map(\.status) == [.asleep])
    }
}
