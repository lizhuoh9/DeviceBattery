import Foundation

/// A language the widget's text is available in.
public enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case korean = "ko"
    case simplifiedChinese = "zh-Hans"

    /// The first of `preferred` (BCP 47 tags, most preferred first) that the widget speaks;
    /// English otherwise. Traditional Chinese falls back to Simplified Chinese.
    public static func resolve(_ preferred: [String]) -> AppLanguage {
        for tag in preferred.map({ $0.lowercased() }) {
            if tag.hasPrefix("en") { return .english }
            if tag.hasPrefix("ko") { return .korean }
            if tag.hasPrefix("zh") { return .simplifiedChinese }
        }
        return .english
    }
}

/// The user-facing text of the core, in one language.
///
/// Every entry lists English, Korean and Chinese side by side, so a translation cannot be
/// left out. The app target extends this with its menu and dialog text.
public struct Strings: Sendable {
    public let language: AppLanguage

    public init(_ language: AppLanguage) {
        self.language = language
    }

    /// The text for the current language.
    public func pick(_ english: String, _ korean: String, _ chinese: String) -> String {
        switch language {
        case .english: english
        case .korean: korean
        case .simplifiedChinese: chinese
        }
    }

    // MARK: - Status lines

    public var charging: String { pick("Charging", "충전 중", "充电中") }
    public var fullyCharged: String { pick("Fully charged", "충전 완료", "已充满") }
    public var lowBattery: String { pick("Low battery", "배터리 부족", "电量偏低") }
    public var criticalBattery: String { pick("Very low — charge soon", "배터리 매우 부족 · 충전 필요", "电量极低，请尽快充电") }
    public var needsInputMonitoring: String { pick("Needs Input Monitoring", "입력 모니터링 권한 필요", "需要“输入监控”权限") }
    public var asleepUntilWake: String { pick("Asleep — updates when it wakes", "절전 중 · 깨우면 업데이트", "休眠中，唤醒后更新") }

    public func asleep(since age: String) -> String {
        pick("Asleep · \(age)", "절전 중 · \(age)", "休眠 · \(age)")
    }

    public func component(_ role: BatteryComponent.Role) -> String {
        switch role {
        case .left: pick("L", "L", "左")
        case .right: pick("R", "R", "右")
        case .chargingCase: pick("Case", "케이스", "盒")
        }
    }

    /// Sources are brand names, except Bluetooth.
    public func source(_ raw: String) -> String {
        raw == BluetoothProfileParser.source ? pick("Bluetooth", "블루투스", "蓝牙") : raw
    }

    /// "just now", "5 min ago", "2 hr ago", "3 days ago".
    public func age(of date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60:
            return pick("just now", "방금", "刚刚")
        case ..<3600:
            let minutes = Int(seconds / 60)
            return pick("\(minutes) min ago", "\(minutes)분 전", "\(minutes) 分钟前")
        case ..<86_400:
            let hours = Int(seconds / 3600)
            return pick("\(hours) hr ago", "\(hours)시간 전", "\(hours) 小时前")
        default:
            let days = Int(seconds / 86_400)
            return pick(days == 1 ? "1 day ago" : "\(days) days ago", "\(days)일 전", "\(days) 天前")
        }
    }

    // MARK: - Names for devices that do not report one

    public func rogDevice(kind: DeviceKind) -> String {
        switch kind {
        case .mouse: pick("ROG Mouse", "ROG 무선 마우스", "ROG 无线鼠标")
        case .keyboard: pick("ROG Keyboard", "ROG 무선 키보드", "ROG 无线键盘")
        default: pick("ROG Device", "ROG 무선 기기", "ROG 无线设备")
        }
    }

    public var logitechDevice: String { pick("Logitech Device", "Logitech 기기", "Logitech 设备") }
    public var wirelessMouse: String { pick("Wireless Mouse", "무선 마우스", "无线鼠标") }
    public var bluetoothDevice: String { pick("Bluetooth Device", "블루투스 기기", "蓝牙设备") }
}
