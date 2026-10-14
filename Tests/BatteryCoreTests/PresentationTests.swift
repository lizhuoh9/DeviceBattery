import Foundation
import Testing
@testable import BatteryCore

@Suite("Row presentation")
struct PresentationTests {
    let now = Date(timeIntervalSince1970: 100_000)
    let zh = Strings(.simplifiedChinese)

    func reading(
        level: Int?, charge: ChargeState = .discharging, status: LinkStatus = .online,
        components: [BatteryComponent] = [], age: TimeInterval = 0
    ) -> DeviceReading {
        DeviceReading(
            id: "x", name: "X", kind: .mouse, level: level, charge: charge, status: status,
            components: components, source: "Logi Bolt", date: now.addingTimeInterval(-age)
        )
    }

    @Test("tone follows level thresholds, charging and reachability", arguments: [
        (Int?(80), ChargeState.discharging, LinkStatus.online, RowTone.normal),
        (20, .discharging, .online, .low),
        (10, .discharging, .online, .critical),
        (5, .charging, .online, .charging),
        (100, .full, .online, .charging),
        (80, .discharging, .asleep, .inactive),
        (nil, .unknown, .needsPermission, .attention),
    ])
    func tone(level: Int?, charge: ChargeState, status: LinkStatus, expected: RowTone) {
        #expect(RowPresentation(reading(level: level, charge: charge, status: status), now: now, strings: zh).tone == expected)
    }

    @Test("detail line describes the state")
    func detail() {
        #expect(RowPresentation(reading(level: 80), now: now, strings: zh).detail == "Logi Bolt")
        #expect(RowPresentation(reading(level: 20), now: now, strings: zh).detail == "电量偏低")
        #expect(RowPresentation(reading(level: 7), now: now, strings: zh).detail == "电量极低，请尽快充电")
        #expect(RowPresentation(reading(level: 40, charge: .charging), now: now, strings: zh).detail == "充电中")
        #expect(RowPresentation(reading(level: 100, charge: .full), now: now, strings: zh).detail == "已充满")
        #expect(RowPresentation(reading(level: 86, status: .asleep, age: 3 * 3600), now: now, strings: zh).detail == "休眠 · 3 小时前")
        #expect(RowPresentation(reading(level: nil, status: .asleep), now: now, strings: zh).detail == "休眠中，唤醒后更新")
        #expect(RowPresentation(reading(level: nil, status: .needsPermission), now: now, strings: zh).detail == "需要“输入监控”权限")
        let buds = [BatteryComponent(role: .left, level: 100), BatteryComponent(role: .right, level: 92)]
        #expect(RowPresentation(reading(level: 92, components: buds), now: now, strings: zh).detail == "左 100% · 右 92%")
    }

    @Test("percentage text", arguments: [(86, "86"), (nil, "—")] as [(Int?, String)])
    func percent(level: Int?, text: String) {
        #expect(RowPresentation(reading(level: level), now: now, strings: zh).percent == text)
    }
}

@Suite("Low battery alerts")
struct LowBatteryPolicyTests {
    let date = Date(timeIntervalSince1970: 0)

    func reading(_ level: Int?, charge: ChargeState = .discharging, status: LinkStatus = .online) -> DeviceReading {
        DeviceReading(id: "m", name: "Mouse", kind: .mouse, level: level, charge: charge, status: status, source: "t", date: date)
    }

    @Test("alerts once per threshold while discharging")
    func thresholds() {
        var policy = LowBatteryPolicy()
        #expect(policy.evaluate([reading(30)]).isEmpty)
        #expect(policy.evaluate([reading(19)]).map(\.threshold) == [20])
        #expect(policy.evaluate([reading(18)]).isEmpty)
        #expect(policy.evaluate([reading(9)]).map(\.threshold) == [10])
        #expect(policy.evaluate([reading(5)]).isEmpty)
    }

    @Test("a big drop alerts only for the lowest threshold crossed")
    func bigDrop() {
        var policy = LowBatteryPolicy()
        #expect(policy.evaluate([reading(8)]).map(\.threshold) == [10])
    }

    @Test("charging re-arms the alerts; asleep readings change nothing")
    func rearm() {
        var policy = LowBatteryPolicy()
        _ = policy.evaluate([reading(15)])
        #expect(policy.evaluate([reading(15, status: .asleep)]).isEmpty)
        _ = policy.evaluate([reading(40, charge: .charging)])
        #expect(policy.evaluate([reading(15)]).map(\.threshold) == [20])
    }
}
