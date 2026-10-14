import Foundation
import Testing
@testable import BatteryCore

@Suite("Localization")
struct LocalizationTests {
    let now = Date(timeIntervalSince1970: 100_000)

    @Test("picks the first supported language the user prefers", arguments: [
        (["ko-KR", "en-US"], AppLanguage.korean),
        (["zh-Hans-CN"], .simplifiedChinese),
        (["zh-Hant-TW", "en"], .simplifiedChinese),
        (["en-GB"], .english),
        (["fr-FR", "ko-KR"], .korean),
        (["fr-FR", "de-DE"], .english),
        ([], .english),
    ] as [([String], AppLanguage)])
    func resolve(preferred: [String], expected: AppLanguage) {
        #expect(AppLanguage.resolve(preferred) == expected)
    }

    func reading(
        level: Int?, charge: ChargeState = .discharging, status: LinkStatus = .online,
        components: [BatteryComponent] = [], source: String = "Logi Bolt", age: TimeInterval = 0
    ) -> DeviceReading {
        DeviceReading(
            id: "x", name: "X", kind: .mouse, level: level, charge: charge, status: status,
            components: components, source: source, date: now.addingTimeInterval(-age)
        )
    }

    func detail(_ reading: DeviceReading, _ language: AppLanguage) -> String {
        RowPresentation(reading, now: now, strings: Strings(language)).detail
    }

    @Test("English status lines")
    func english() {
        #expect(detail(reading(level: 40, charge: .charging), .english) == "Charging")
        #expect(detail(reading(level: 100, charge: .full), .english) == "Fully charged")
        #expect(detail(reading(level: 20), .english) == "Low battery")
        #expect(detail(reading(level: 7), .english) == "Very low — charge soon")
        #expect(detail(reading(level: 86, status: .asleep, age: 3 * 3600), .english) == "Asleep · 3 hr ago")
        #expect(detail(reading(level: nil, status: .asleep), .english) == "Asleep — updates when it wakes")
        #expect(detail(reading(level: nil, status: .needsPermission), .english) == "Needs Input Monitoring")
        #expect(detail(reading(level: 80, source: "Bluetooth"), .english) == "Bluetooth")
    }

    @Test("Korean status lines")
    func korean() {
        #expect(detail(reading(level: 40, charge: .charging), .korean) == "충전 중")
        #expect(detail(reading(level: 100, charge: .full), .korean) == "충전 완료")
        #expect(detail(reading(level: 20), .korean) == "배터리 부족")
        #expect(detail(reading(level: 7), .korean) == "배터리 매우 부족 · 충전 필요")
        #expect(detail(reading(level: 86, status: .asleep, age: 3 * 3600), .korean) == "절전 중 · 3시간 전")
        #expect(detail(reading(level: nil, status: .asleep), .korean) == "절전 중 · 깨우면 업데이트")
        #expect(detail(reading(level: nil, status: .needsPermission), .korean) == "입력 모니터링 권한 필요")
        #expect(detail(reading(level: 80, source: "Bluetooth"), .korean) == "블루투스")
    }

    @Test("AirPods-style components use each language's labels")
    func components() {
        let buds = [
            BatteryComponent(role: .left, level: 100),
            BatteryComponent(role: .right, level: 92),
            BatteryComponent(role: .chargingCase, level: 41),
        ]
        #expect(detail(reading(level: 92, components: buds), .english) == "L 100% · R 92% · Case 41%")
        #expect(detail(reading(level: 92, components: buds), .korean) == "L 100% · R 92% · 케이스 41%")
        #expect(detail(reading(level: 92, components: buds), .simplifiedChinese) == "左 100% · 右 92% · 盒 41%")
    }

    @Test("relative ages", arguments: [
        (20, "just now", "방금", "刚刚"),
        (60, "1 min ago", "1분 전", "1 分钟前"),
        (2 * 3600, "2 hr ago", "2시간 전", "2 小时前"),
        (86_400, "1 day ago", "1일 전", "1 天前"),
        (3 * 86_400, "3 days ago", "3일 전", "3 天前"),
    ] as [(TimeInterval, String, String, String)])
    func ages(age: TimeInterval, english: String, korean: String, chinese: String) {
        let date = now.addingTimeInterval(-age)
        #expect(Strings(.english).age(of: date, now: now) == english)
        #expect(Strings(.korean).age(of: date, now: now) == korean)
        #expect(Strings(.simplifiedChinese).age(of: date, now: now) == chinese)
    }

    @Test("generic device names", arguments: AppLanguage.allCases)
    func genericNames(language: AppLanguage) {
        let strings = Strings(language)
        let names = [
            strings.rogDevice(kind: .mouse), strings.rogDevice(kind: .keyboard), strings.rogDevice(kind: .other),
            strings.logitechDevice, strings.wirelessMouse, strings.bluetoothDevice,
        ]
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
        #expect(names[0].hasPrefix("ROG"))
    }

    @Test("Korean and English generic names")
    func genericNameExamples() {
        #expect(Strings(.english).rogDevice(kind: .keyboard) == "ROG Keyboard")
        #expect(Strings(.korean).rogDevice(kind: .keyboard) == "ROG 무선 키보드")
        #expect(Strings(.korean).logitechDevice == "Logitech 기기")
        #expect(CompxProtocol.displayName(forProduct: " ", strings: Strings(.english)) == "Wireless Mouse")
    }
}
