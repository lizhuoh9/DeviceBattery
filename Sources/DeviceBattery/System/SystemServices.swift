import AppKit
import BatteryCore
import IOKit.hid
import OSLog
import ServiceManagement
import UserNotifications

/// Posts low-battery notifications; asks for permission on the first one.
@MainActor
final class Notifier {
    private let log = Logger(subsystem: "local.DeviceBattery", category: "notifier")

    func post(_ alert: LowBatteryAlert) {
        let content = UNMutableNotificationContent()
        content.title = "\(alert.name) 电量低"
        content.body = "剩余 \(alert.level)%，记得充电。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "low.\(alert.id).\(alert.threshold)", content: content, trigger: nil)
        let log = log
        Task {
            let center = UNUserNotificationCenter.current()
            do {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else { return }
                try await center.add(request)
            } catch {
                log.error("Notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// "Open at Login", through the system's login items.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Input Monitoring: macOS requires it to open dongle interfaces that include keyboard
/// usages (the Compx mouse dongle). The widget never reads keystrokes.
enum InputMonitoring {
    static var isGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Shows the system prompt the first time; does nothing once the user has decided.
    static func requestIfUndetermined() {
        guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown else { return }
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }
}
