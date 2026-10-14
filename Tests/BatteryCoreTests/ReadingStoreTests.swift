import Foundation
import Testing
@testable import BatteryCore

@Suite("Reading store")
struct ReadingStoreTests {
    let earlier = Date(timeIntervalSince1970: 10_000)
    let later = Date(timeIntervalSince1970: 20_000)

    func reading(
        _ id: String, name: String = "Device", kind: DeviceKind = .mouse, level: Int?,
        status: LinkStatus = .online, date: Date
    ) -> DeviceReading {
        DeviceReading(id: id, name: name, kind: kind, level: level, status: status, source: "test", date: date)
    }

    @Test("an asleep device keeps its last known level, name and kind")
    func carriesLastLevel() {
        var store = ReadingStore()
        store.apply([reading("logi.1", name: "MX Keys S", kind: .keyboard, level: 86, date: earlier)], from: "bolt")
        store.apply([reading("logi.1", name: "MX KEYS B", kind: .other, level: nil, status: .asleep, date: later)], from: "bolt")
        let row = store.rows().first
        #expect(row?.name == "MX Keys S")
        #expect(row?.kind == .keyboard)
        #expect(row?.level == 86)
        #expect(row?.status == .asleep)
        #expect(row?.date == earlier)
    }

    @Test("remembered readings from a previous launch fill in asleep devices")
    func remembered() {
        var store = ReadingStore(remembered: [reading("rog.1", name: "ROG 无线键盘", kind: .keyboard, level: 70, date: earlier)])
        #expect(store.rows().isEmpty)
        store.apply([reading("rog.1", name: "ROG 无线设备", kind: .other, level: nil, status: .asleep, date: later)], from: "omni")
        #expect(store.rows().first?.name == "ROG 无线键盘")
        #expect(store.rows().first?.level == 70)
    }

    @Test("devices a source stops reporting disappear; other sources are untouched")
    func dropsMissing() {
        var store = ReadingStore()
        store.apply([reading("bt.1", level: 50, date: earlier), reading("bt.2", level: 60, date: earlier)], from: "bt")
        store.apply([reading("compx.1", level: 70, date: earlier)], from: "compx")
        store.apply([reading("bt.2", level: 58, date: later)], from: "bt")
        #expect(Set(store.rows().map(\.id)) == ["bt.2", "compx.1"])
        store.removeSource("compx")
        #expect(store.rows().map(\.id) == ["bt.2"])
    }

    @Test("rows apply custom names, hide devices and sort by kind then name")
    func rows() {
        var store = ReadingStore()
        store.apply([
            reading("k", name: "Keyboard", kind: .keyboard, level: 50, date: earlier),
            reading("m2", name: "b mouse", kind: .mouse, level: 50, date: earlier),
            reading("m1", name: "A mouse", kind: .mouse, level: 50, date: earlier),
            reading("h", name: "AirPods", kind: .headphones, level: 50, date: earlier),
        ], from: "s")
        let rows = store.rows(customNames: ["k": "我的键盘"], hidden: ["h"])
        #expect(rows.map(\.name) == ["A mouse", "b mouse", "我的键盘"])
    }

    @Test("a device whose receiver was unplugged keeps its last level for later reads")
    func survivesSourceRemoval() {
        var store = ReadingStore(remembered: [reading("logi.1", name: "MX Keys S", kind: .keyboard, level: 60, date: earlier)])
        store.apply([reading("logi.1", name: "MX Keys S", kind: .keyboard, level: 80, date: later)], from: "hid.1")
        store.removeSource("hid.1")
        #expect(store.rows().isEmpty)
        #expect(store.memorySnapshot.first?.level == 80)
        store.apply([reading("logi.1", name: "MX KEYS B", kind: .other, level: nil, status: .asleep, date: later)], from: "hid.2")
        #expect(store.rows().first?.level == 80)
        #expect(store.rows().first?.date == later)
    }

    @Test("a device seen by two sources shows the best reading; removing one keeps the other")
    func duplicateSources() {
        var store = ReadingStore()
        store.apply([reading("logi.1", level: 70, date: later)], from: "a")
        store.apply([reading("logi.1", level: nil, status: .asleep, date: later)], from: "b")
        #expect(store.rows().map(\.status) == [.online])
        store.removeSource("a")
        #expect(store.rows().map(\.status) == [.asleep])
        #expect(store.rows().first?.level == 70)
        store.removeSource("b")
        #expect(store.rows().isEmpty)
    }

    @Test("rows with the same kind and name keep a stable order")
    func stableOrder() {
        var store = ReadingStore()
        store.apply([
            reading("b", name: "Logitech 设备", level: 1, date: earlier),
            reading("a", name: "Logitech 设备", level: 2, date: earlier),
        ], from: "s")
        #expect(store.rows().map(\.id) == ["a", "b"])
    }

    @Test("the memory snapshot includes current and remembered devices")
    func memory() {
        var store = ReadingStore(remembered: [reading("old", level: 10, date: earlier)])
        store.apply([reading("new", level: 20, date: later)], from: "s")
        #expect(Set(store.memorySnapshot.map(\.id)) == ["old", "new"])
    }
}
