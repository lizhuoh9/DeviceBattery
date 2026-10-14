import Foundation
import Testing
@testable import BatteryCore

@Suite("HID++ framing")
struct HIDPPFramingTests {
    @Test("a feature call is a short report tagged with our software ID")
    func featureCall() {
        let request = HIDPP.request(device: 1, featureIndex: 0x00, function: 1, params: [0, 0, 0x5A])
        #expect(request == [0x10, 0x01, 0x00, 0x1B, 0x00, 0x00, 0x5A])
    }

    @Test("a register read goes to the receiver with sub-ID 0x83")
    func registerRead() {
        #expect(HIDPP.registerRead(0xB5, params: [0x51, 0x00]) == [0x10, 0xFF, 0x83, 0xB5, 0x51, 0x00, 0x00])
    }

    @Test("classifies a successful feature reply")
    func success() {
        let request = HIDPP.request(device: 1, featureIndex: 0x00, function: 1)
        let reply = report([0x11, 0x01, 0x00, 0x1B, 0x04, 0x05, 0x5A], length: 20)
        #expect(HIDPP.reply(to: request, in: reply) == .success(Array(reply[4...])))
    }

    @Test("classifies the receiver's 'device unreachable' error captured from a sleeping MX Keys")
    func unreachable() {
        let request = HIDPP.request(device: 1, featureIndex: 0x00, function: 1)
        #expect(HIDPP.reply(to: request, in: [0x10, 0x01, 0x8F, 0x00, 0x1B, 0x04, 0x00]) == .unreachable(0x04))
    }

    @Test("classifies a HID++ 2.0 feature error")
    func featureError() {
        let request = HIDPP.request(device: 2, featureIndex: 0x08, function: 1)
        let reply = report([0x11, 0x02, 0xFF, 0x08, 0x1B, 0x07], length: 20)
        #expect(HIDPP.reply(to: request, in: reply) == .featureError(0x07))
    }

    @Test("matches register replies on the echoed sub-register")
    func registerReplies() {
        let request = HIDPP.registerRead(0xB5, params: [0x51, 0x00])
        let capture: [UInt8] = [0x11, 0xFF, 0x83, 0xB5, 0x51, 0x41, 0x80, 0xB3, 0x1A, 0x2B, 0x3C, 0x4D,
                                0x01, 0x00, 0x80, 0x14, 0x01, 0x00, 0x00, 0x00]
        #expect(HIDPP.reply(to: request, in: capture) == .success(Array(capture[4...])))
        var other = capture
        other[4] = 0x52
        #expect(HIDPP.reply(to: request, in: other) == nil)
        #expect(HIDPP.reply(to: request, in: [0x10, 0xFF, 0x8F, 0x83, 0xB5, 0x08, 0x00]) == .unreachable(0x08))
    }

    @Test("ignores reports for other devices, functions or report IDs")
    func foreign() {
        let request = HIDPP.request(device: 1, featureIndex: 0x08, function: 1)
        #expect(HIDPP.reply(to: request, in: report([0x11, 0x02, 0x08, 0x1B], length: 20)) == nil)
        #expect(HIDPP.reply(to: request, in: report([0x11, 0x01, 0x08, 0x10], length: 20)) == nil)
        #expect(HIDPP.reply(to: request, in: report([0x20, 0x01, 0x08, 0x1B], length: 20)) == nil)
        #expect(HIDPP.reply(to: request, in: [0x10, 0x01]) == nil)
    }
}

@Suite("HID++ battery decoding")
struct HIDPPBatteryTests {
    @Test("unified battery: state of charge and charging status")
    func unified() {
        #expect(HIDPPBattery.decodeUnified([0x4F, 0x04, 0x00, 0x00]) == .init(level: 79, charge: .discharging))
        #expect(HIDPPBattery.decodeUnified([0x30, 0x04, 0x01, 0x01]) == .init(level: 48, charge: .charging))
        #expect(HIDPPBattery.decodeUnified([0x64, 0x08, 0x03, 0x01]) == .init(level: 100, charge: .full))
    }

    @Test("unified battery without a percentage falls back to the level flags", arguments: [
        (UInt8(0x08), 90), (0x04, 50), (0x02, 20), (0x01, 5),
    ])
    func unifiedFlags(flags: UInt8, level: Int) {
        #expect(HIDPPBattery.decodeUnified([0x00, flags, 0x00, 0x00]).level == level)
    }

    @Test("battery status feature")
    func status() {
        #expect(HIDPPBattery.decodeStatus([0x32, 0x1E, 0x01]) == .init(level: 50, charge: .charging))
        #expect(HIDPPBattery.decodeStatus([0x64, 0x00, 0x03]) == .init(level: 100, charge: .full))
        #expect(HIDPPBattery.decodeStatus([0x0A, 0x05, 0x00]) == .init(level: 10, charge: .discharging))
        #expect(HIDPPBattery.decodeStatus([0x0A, 0x05, 0x06]).charge == .unknown)
    }

    @Test("battery voltage is mapped onto a Li-ion discharge curve")
    func voltage() {
        #expect(HIDPPBattery.decodeVoltage([0x0F, 0x50, 0x00]) == .init(level: 60, charge: .discharging))
        #expect(HIDPPBattery.decodeVoltage([0x10, 0x04, 0x80]) == .init(level: 90, charge: .charging))
        #expect(HIDPPBattery.decodeVoltage([0x10, 0x68, 0x81]) == .init(level: 100, charge: .full))
        #expect(HIDPPBattery.decodeVoltage([0x0D, 0x00, 0x00]).level == 0)
    }
}

@Suite("Logitech receiver registers")
struct HIDPPReceiverInfoTests {
    @Test("parses Bolt pairing info captured from an MX Keys S")
    func boltPairing() {
        let params: [UInt8] = [0x51, 0x41, 0x80, 0xB3, 0x1A, 0x2B, 0x3C, 0x4D, 0x01, 0x00, 0x80, 0x14]
        let slot = HIDPPReceiverInfo.parsePairing(params, slot: 1, receiver: .bolt)
        #expect(slot == PairedSlot(index: 1, kind: .keyboard, serial: "1A2B3C4D"))
    }

    @Test("parses the Bolt codename captured from an MX Keys S")
    func boltName() {
        let params: [UInt8] = [0x61, 0x01, 0x09, 0x4D, 0x58, 0x20, 0x4B, 0x45, 0x59, 0x53, 0x20, 0x42, 0, 0, 0, 0]
        #expect(HIDPPReceiverInfo.parseCodename(params, receiver: .bolt) == "MX KEYS B")
    }

    @Test("parses Unifying pairing info and codename")
    func unifying() {
        let pairing: [UInt8] = [0x20, 0x00, 0x08, 0x40, 0x82, 0x04, 0x00, 0x02, 0, 0, 0, 0, 0, 0, 0, 0]
        let extended: [UInt8] = [0x30, 0x12, 0x34, 0x56, 0x78, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        let slot = HIDPPReceiverInfo.parsePairing(pairing, slot: 1, receiver: .unifying, extended: extended)
        #expect(slot == PairedSlot(index: 1, kind: .mouse, serial: "12345678"))
        let name: [UInt8] = [0x40, 0x04, 0x4D, 0x58, 0x33, 0x53, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        #expect(HIDPPReceiverInfo.parseCodename(name, receiver: .unifying) == "MX3S")
    }

    @Test("register addresses differ between Bolt and Unifying")
    func requests() {
        #expect(HIDPPReceiverInfo.pairingRequest(slot: 2, receiver: .bolt) == HIDPP.registerRead(0xB5, params: [0x52, 0x00]))
        #expect(HIDPPReceiverInfo.nameRequest(slot: 2, receiver: .bolt) == HIDPP.registerRead(0xB5, params: [0x62, 0x01]))
        #expect(HIDPPReceiverInfo.pairingRequest(slot: 2, receiver: .unifying) == HIDPP.registerRead(0xB5, params: [0x21, 0x00]))
        #expect(HIDPPReceiverInfo.nameRequest(slot: 2, receiver: .unifying) == HIDPP.registerRead(0xB5, params: [0x41, 0x00]))
        #expect(HIDPPReceiverInfo.pairingRequest(slot: 2, receiver: .other) == nil)
    }

    @Test("maps receiver and device type codes onto device kinds")
    func kinds() {
        #expect(LogitechReceiverKind(productID: 0xC548) == .bolt)
        #expect(LogitechReceiverKind(productID: 0xC52B) == .unifying)
        #expect(LogitechReceiverKind(productID: 0xC539) == .other)
        #expect(HIDPPReceiverInfo.kind(pairingNibble: 0x02) == .mouse)
        #expect(HIDPPReceiverInfo.kind(pairingNibble: 0x09) == .trackpad)
        #expect(HIDPPReceiverInfo.kind(deviceType: 0) == .keyboard)
        #expect(HIDPPReceiverInfo.kind(deviceType: 3) == .mouse)
        #expect(HIDPPReceiverInfo.kind(deviceType: 8) == .headphones)
        #expect(HIDPPReceiverInfo.kind(deviceType: 99) == .other)
    }
}
