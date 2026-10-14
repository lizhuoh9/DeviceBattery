import BatteryCore
import Foundation

/// The app's menu, dialog and notification text, in English, Korean and Chinese.
extension Strings {
    /// The language of the user's macOS settings (including a per-app choice in
    /// System Settings → General → Language & Region).
    static var current: Strings {
        Strings(AppLanguage.resolve(Locale.preferredLanguages))
    }

    var noDevices: String { pick("No wireless devices found", "무선 기기를 찾지 못했습니다", "没有发现无线设备") }

    // MARK: - Menu

    var refreshNow: String { pick("Refresh Now", "지금 새로고침", "立即刷新") }
    var openInputMonitoring: String { pick("Open Input Monitoring Settings…", "입력 모니터링 설정 열기…", "打开“输入监控”设置…") }
    var keepOnTop: String { pick("Keep Above Other Windows", "다른 윈도우 위에 유지", "置于其他窗口之上") }
    var lowBatteryAlerts: String { pick("Low Battery Alerts", "배터리 부족 알림", "低电量提醒") }
    var openAtLogin: String { pick("Open at Login", "로그인 시 열기", "登录时打开") }
    var quit: String { pick("Quit Device Battery", "Device Battery 종료", "退出") }

    func rename(_ name: String) -> String {
        pick("Rename “\(name)”…", "“\(name)” 이름 변경…", "重命名“\(name)”…")
    }

    func hide(_ name: String) -> String {
        pick("Hide “\(name)”", "“\(name)” 숨기기", "隐藏“\(name)”")
    }

    func showHidden(_ count: Int) -> String {
        pick("Show Hidden Devices (\(count))", "숨긴 기기 보기 (\(count))", "显示已隐藏的设备（\(count)）")
    }

    // MARK: - Dialogs

    var renameTitle: String { pick("Rename Device", "기기 이름 변경", "重命名设备") }
    var renameHint: String { pick("Leave empty to restore the default name.", "비워 두면 기본 이름으로 돌아갑니다.", "留空则恢复默认名称。") }
    var ok: String { pick("OK", "확인", "好") }
    var cancel: String { pick("Cancel", "취소", "取消") }
    var loginItemError: String { pick("Couldn’t change “Open at Login”", "‘로그인 시 열기’를 변경할 수 없습니다", "无法更改“登录时打开”") }

    // MARK: - Notifications

    func lowBatteryTitle(_ name: String) -> String {
        pick("\(name) battery low", "\(name) 배터리 부족", "\(name) 电量低")
    }

    func lowBatteryBody(_ level: Int) -> String {
        pick("\(level)% left. Time to charge.", "\(level)% 남았습니다. 충전해 주세요.", "剩余 \(level)%，记得充电。")
    }

    // MARK: - Rows

    func tooltip(source: String, age: String) -> String {
        pick("\(source) · updated \(age)", "\(source) · \(age) 업데이트됨", "\(source) · 更新于 \(age)")
    }

    func accessibilityLabel(name: String, level: Int?, detail: String) -> String {
        guard let level else {
            return pick("\(name), battery level unknown, \(detail)", "\(name), 배터리 잔량 알 수 없음, \(detail)", "\(name)，电量未知，\(detail)")
        }
        return pick("\(name), battery \(level)%, \(detail)", "\(name), 배터리 \(level)%, \(detail)", "\(name)，电量 \(level)%，\(detail)")
    }

    /// Sample name used by the preview renderer.
    var myAirPods: String { pick("My AirPods", "내 AirPods", "我的AirPods") }
}
