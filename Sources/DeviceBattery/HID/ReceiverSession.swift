import BatteryCore
import Foundation
import IOKit.hid

/// One supported receiver interface, paired with the reader that speaks its protocol.
@MainActor
final class ReceiverSession {
    /// Source key in the reading store, unique per IOKit registry entry.
    let key: String
    /// Called when the device sends something worth an early refresh.
    var onEvent: (() -> Void)?

    private let channel: IOHIDReportChannel
    private let reader: BatteryReader
    /// Logitech receivers stay open to hear connection notifications; others are opened per read.
    private let keepsOpen: Bool
    private var isReading = false

    private init(key: String, channel: IOHIDReportChannel, reader: BatteryReader, keepsOpen: Bool) {
        self.key = key
        self.channel = channel
        self.reader = reader
        self.keepsOpen = keepsOpen
    }

    /// Reads all devices behind the receiver; nil when a read is already running.
    func read() async -> [DeviceReading]? {
        guard !isReading else { return nil }
        isReading = true
        defer {
            isReading = false
            if !keepsOpen { channel.close() }
        }
        return await reader.read()
    }

    /// The receiver was unplugged.
    func invalidate() {
        channel.invalidate()
    }

    /// Builds a session for `device` when it is an interface we know how to query.
    static func make(for device: IOHIDDevice) -> ReceiverSession? {
        let info = HIDDeviceInfo(device)
        let key = "hid.\(info.registryID)"

        if info.vendorID == HIDPP.vendorID, info.usagePage == HIDPP.usagePage, (0xC500...0xC5FF).contains(info.productID) {
            let channel = IOHIDReportChannel(device: device)
            let reader = LogitechReceiverReader(
                channel: channel, receiver: LogitechReceiverKind(productID: info.productID), receiverID: info.stableID
            )
            let session = ReceiverSession(key: key, channel: channel, reader: reader, keepsOpen: true)
            channel.onUnsolicitedReport = { [weak session, weak reader] report in
                if reader?.notice(report) == true { session?.onEvent?() }
            }
            return session
        }
        if info.vendorID == AsusOmniProtocol.vendorID, info.productID == AsusOmniProtocol.receiverProductID,
           info.usagePage == AsusOmniProtocol.usagePage {
            let channel = IOHIDReportChannel(device: device)
            let reader = AsusOmniReader(channel: channel, receiverID: info.stableID)
            return ReceiverSession(key: key, channel: channel, reader: reader, keepsOpen: false)
        }
        if CompxProtocol.isBatteryInterface(
            vendorID: info.vendorID, productID: info.productID, usagePage: info.usagePage,
            maxOutputReportSize: info.maxOutputReportSize, product: info.product
        ) {
            let channel = IOHIDReportChannel(device: device)
            let reader = CompxReader(
                channel: channel, id: "compx.\(info.stableID)", name: CompxProtocol.displayName(forProduct: info.product)
            )
            return ReceiverSession(key: key, channel: channel, reader: reader, keepsOpen: false)
        }
        return nil
    }
}

/// The IOKit properties used to pick a protocol and identify a receiver.
struct HIDDeviceInfo {
    let vendorID: Int
    let productID: Int
    let usagePage: Int
    let maxOutputReportSize: Int
    let product: String
    let registryID: UInt64
    /// USB serial when the receiver has one, otherwise its port location.
    let stableID: String

    init(_ device: IOHIDDevice) {
        func property<T>(_ key: String) -> T? {
            IOHIDDeviceGetProperty(device, key as CFString) as? T
        }
        vendorID = property(kIOHIDVendorIDKey) ?? 0
        productID = property(kIOHIDProductIDKey) ?? 0
        usagePage = property(kIOHIDPrimaryUsagePageKey) ?? 0
        maxOutputReportSize = property(kIOHIDMaxOutputReportSizeKey) ?? 0
        product = property(kIOHIDProductKey) ?? ""

        var entryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &entryID)
        registryID = entryID

        let serial: String = property(kIOHIDSerialNumberKey) ?? ""
        let location: Int = property(kIOHIDLocationIDKey) ?? 0
        stableID = serial.isEmpty ? String(format: "loc%08X", location) : serial
    }
}
