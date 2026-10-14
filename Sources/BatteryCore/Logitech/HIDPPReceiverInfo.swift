import Foundation

/// Receiver families differ in how they list paired devices.
public enum LogitechReceiverKind: Sendable, Equatable {
    case bolt, unifying, other

    public init(productID: Int) {
        switch productID {
        case 0xC548: self = .bolt
        case 0xC52B, 0xC532: self = .unifying
        default: self = .other
        }
    }

    var sourceName: String {
        switch self {
        case .bolt: "Logi Bolt"
        case .unifying: "Logi Unifying"
        case .other: "Logitech"
        }
    }
}

/// A device paired with a receiver, as listed by its pairing registers.
struct PairedSlot: Equatable, Sendable {
    let index: UInt8
    let kind: DeviceKind
    let serial: String?
    var codename: String?

    init(index: UInt8, kind: DeviceKind, serial: String?, codename: String? = nil) {
        self.index = index
        self.kind = kind
        self.serial = serial
        self.codename = codename
    }
}

/// The receiver-info register (0xB5) and its sub-registers, per receiver family (after Solaar).
enum HIDPPReceiverInfo {
    static let register: UInt8 = 0xB5

    /// Bolt: 0x5N. Unifying: 0x2(N-1). Other receivers do not expose it.
    static func pairingRequest(slot: UInt8, receiver: LogitechReceiverKind) -> [UInt8]? {
        switch receiver {
        case .bolt: HIDPP.registerRead(register, params: [0x50 + slot, 0x00])
        case .unifying: HIDPP.registerRead(register, params: [0x20 + slot - 1, 0x00])
        case .other: nil
        }
    }

    /// Unifying keeps the serial in the extended pairing register, 0x3(N-1).
    static func extendedPairingRequest(slot: UInt8) -> [UInt8] {
        HIDPP.registerRead(register, params: [0x30 + slot - 1, 0x00])
    }

    /// Bolt: 0x6N with parameter 1. Unifying: 0x4(N-1).
    static func nameRequest(slot: UInt8, receiver: LogitechReceiverKind) -> [UInt8]? {
        switch receiver {
        case .bolt: HIDPP.registerRead(register, params: [0x60 + slot, 0x01])
        case .unifying: HIDPP.registerRead(register, params: [0x40 + slot - 1, 0x00])
        case .other: nil
        }
    }

    /// Parses pairing info; `params` start with the echoed sub-register.
    static func parsePairing(
        _ params: [UInt8], slot: UInt8, receiver: LogitechReceiverKind, extended: [UInt8]? = nil
    ) -> PairedSlot? {
        switch receiver {
        case .bolt where params.count >= 8:
            PairedSlot(index: slot, kind: kind(pairingNibble: params[1] & 0x0F), serial: Array(params[4..<8]).hexString)
        case .unifying where params.count >= 8:
            PairedSlot(
                index: slot, kind: kind(pairingNibble: params[7] & 0x0F),
                serial: extended.flatMap { $0.count >= 5 ? Array($0[1..<5]).hexString : nil }
            )
        default:
            nil
        }
    }

    static func parseCodename(_ params: [UInt8], receiver: LogitechReceiverKind) -> String? {
        let (lengthIndex, maxLength) = receiver == .bolt ? (2, 14) : (1, 16)
        guard params.count > lengthIndex else { return nil }
        let start = lengthIndex + 1
        let length = min(Int(params[lengthIndex]), maxLength, params.count - start)
        guard length > 0 else { return nil }
        let name = String(decoding: params[start..<(start + length)], as: UTF8.self)
            .trimmingCharacters(in: .whitespaces.union(.controlCharacters))
        return name.isEmpty ? nil : name
    }

    /// HID++ 1.0 device kind nibble from pairing info or connection notifications.
    static func kind(pairingNibble: UInt8) -> DeviceKind {
        switch pairingNibble {
        case 0x01, 0x03: .keyboard
        case 0x02, 0x08: .mouse
        case 0x09: .trackpad
        case 0x0B, 0x0C: .gamepad
        case 0x0D: .headphones
        default: .other
        }
    }

    /// HID++ 2.0 DEVICE_NAME getDeviceType code.
    static func kind(deviceType: UInt8) -> DeviceKind {
        switch deviceType {
        case 0, 2: .keyboard
        case 3, 5: .mouse
        case 4: .trackpad
        case 8: .headphones
        case 11, 12: .gamepad
        case 14: .speaker
        default: .other
        }
    }
}
