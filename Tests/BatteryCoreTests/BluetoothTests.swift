import Foundation
import Testing
@testable import BatteryCore

@Suite("Bluetooth parsing")
struct BluetoothTests {
    let date = Date(timeIntervalSince1970: 4_000)

    static let profilerJSON = """
    {"SPBluetoothDataType": [{
      "controller_properties": {"controller_state": "attrib_on"},
      "device_connected": [
        {"我的AirPods": {"device_address": "AA:BB:CC:DD:EE:10", "device_minorType": "Headphones",
          "device_vendorID": "0x004C", "device_productID": "0x2036",
          "device_batteryLevelLeft": "100%", "device_batteryLevelRight": "92%", "device_batteryLevelCase": "41%"}},
        {"Magic Mouse": {"device_address": "AA:BB:CC:DD:EE:01", "device_minorType": "Mouse",
          "device_vendorID": "0x004C", "device_batteryLevelMain": "85%"}},
        {"iPhone": {"device_address": "AA:BB:CC:DD:EE:20", "device_services": "0x400000 < BLE >"}}
      ],
      "device_not_connected": [
        {"MX KEYS S": {"device_address": "AA:BB:CC:DD:EE:30", "device_minorType": "Keyboard"}}
      ]
    }]}
    """

    @Test("keeps connected devices that report a battery")
    func connectedOnly() throws {
        let readings = BluetoothProfileParser.parse(Data(Self.profilerJSON.utf8), now: date)
        #expect(readings.map(\.name) == ["我的AirPods", "Magic Mouse"])
    }

    @Test("AirPods report both buds and the case; the lower bud is the headline")
    func airPods() throws {
        let airPods = try #require(BluetoothProfileParser.parse(Data(Self.profilerJSON.utf8), now: date).first)
        #expect(airPods.id == "bt.AA:BB:CC:DD:EE:10")
        #expect(airPods.kind == .headphones)
        #expect(airPods.symbol == "airpods")
        #expect(airPods.level == 92)
        #expect(airPods.components == [
            BatteryComponent(label: "左", level: 100),
            BatteryComponent(label: "右", level: 92),
            BatteryComponent(label: "盒", level: 41),
        ])
    }

    @Test("a single battery is the headline level")
    func magicMouse() throws {
        let mouse = try #require(BluetoothProfileParser.parse(Data(Self.profilerJSON.utf8), now: date).last)
        #expect(mouse == DeviceReading(
            id: "bt.AA:BB:CC:DD:EE:01", name: "Magic Mouse", kind: .mouse, level: 85,
            status: .online, symbol: "magicmouse", source: "蓝牙", date: date
        ))
    }

    @Test("garbage input yields nothing", arguments: ["", "{}", "[1,2]", #"{"SPBluetoothDataType": "x"}"#])
    func garbage(json: String) {
        #expect(BluetoothProfileParser.parse(Data(json.utf8), now: date).isEmpty)
    }

    @Test("an IOKit battery service becomes a reading keyed by its Bluetooth address")
    func registry() throws {
        let properties: [String: Any] = [
            "Product": "Magic Keyboard", "BatteryPercent": 64, "BatteryStatusFlags": 3,
            "DeviceAddress": "aa-bb-cc-dd-ee-02",
        ]
        let reading = try #require(RegistryBatteryParser.reading(from: properties, now: date))
        #expect(reading.id == "bt.AA:BB:CC:DD:EE:02")
        #expect(reading.kind == .keyboard)
        #expect(reading.level == 64)
        #expect(reading.charge == .charging)
        #expect(RegistryBatteryParser.reading(from: ["Product": "X"], now: date) == nil)
        #expect(RegistryBatteryParser.reading(from: ["Product": "X", "BatteryPercent": 50, "Built-In": true], now: date) == nil)
    }

    @Test("merging prefers the live IOKit level but keeps the Bluetooth name")
    func merge() {
        let registry = DeviceReading(id: "bt.A", name: "Magic Keyboard", kind: .keyboard, level: 64, status: .online, source: "IOKit", date: date)
        let profiler = DeviceReading(id: "bt.A", name: "Leo's Keyboard", kind: .keyboard, level: 60, status: .online, source: "蓝牙", date: date)
        let other = DeviceReading(id: "bt.B", name: "AirPods", kind: .headphones, level: 50, status: .online, source: "蓝牙", date: date)
        let merged = BluetoothProfileParser.merge(registry: [registry], profiler: [profiler, other])
        #expect(merged.map(\.name) == ["Leo's Keyboard", "AirPods"])
        #expect(merged.first?.level == 64)
    }
}
