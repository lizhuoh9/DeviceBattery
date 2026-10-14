import AppKit
import BatteryCore

/// Connects the monitor to the panel and handles the widget's menu.
@MainActor
final class WidgetController: NSObject {
    private let settings: Settings
    private let monitor: BatteryMonitor
    private let content = WidgetContentView()
    private lazy var panel = WidgetPanel(content: content)
    private var rows: [DeviceReading] = []

    init(settings: Settings, monitor: BatteryMonitor) {
        self.settings = settings
        self.monitor = monitor
    }

    func start() {
        content.onClick = { [weak self] reading in self?.handleClick(on: reading) }
        content.menuProvider = { [weak self] reading in self?.menu(for: reading) }
        monitor.onUpdate = { [weak self] rows in self?.show(rows) }
        panel.setPinnedOnTop(settings.alwaysOnTop)
        show(rows)
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.monitor.setVisible(self.panel.occlusionState.contains(.visible))
            }
        }
        monitor.start()
    }

    private func show(_ rows: [DeviceReading]) {
        self.rows = rows
        content.show(rows, now: Date())
        panel.fitContent()
    }

    private func handleClick(on reading: DeviceReading?) {
        if reading?.status == .needsPermission {
            InputMonitoring.openSettings()
        } else {
            monitor.refresh()
        }
    }

    // MARK: - Menu

    private func menu(for reading: DeviceReading?) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("立即刷新", #selector(refresh)))
        if let reading {
            menu.addItem(.separator())
            menu.addItem(item("重命名“\(reading.name)”…", #selector(rename), id: reading.id))
            menu.addItem(item("隐藏“\(reading.name)”", #selector(hide), id: reading.id))
            if reading.status == .needsPermission {
                menu.addItem(item("打开“输入监控”设置…", #selector(openInputMonitoring)))
            }
        }
        let hiddenCount = settings.hidden.count
        if hiddenCount > 0 {
            menu.addItem(item("显示已隐藏的设备（\(hiddenCount)）", #selector(showHidden)))
        }
        menu.addItem(.separator())
        menu.addItem(item("置于其他窗口之上", #selector(toggleOnTop), on: settings.alwaysOnTop))
        menu.addItem(item("低电量提醒", #selector(toggleAlerts), on: settings.lowBatteryAlerts))
        menu.addItem(item("登录时打开", #selector(toggleLoginItem), on: LoginItem.isEnabled))
        menu.addItem(.separator())
        menu.addItem(item("退出", #selector(quit)))
        return menu
    }

    private func item(_ title: String, _ action: Selector, id: String? = nil, on: Bool? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = id
        if let on { item.state = on ? .on : .off }
        return item
    }

    @objc private func refresh() {
        monitor.refresh()
    }

    @objc private func rename(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let reading = rows.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "重命名设备"
        alert.informativeText = "留空则恢复默认名称。"
        let field = NSTextField(string: settings.customNames[id] ?? reading.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        settings.setCustomName(field.stringValue, for: id)
        monitor.republish()
    }

    @objc private func hide(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.hidden.insert(id)
        monitor.republish()
    }

    @objc private func showHidden() {
        settings.hidden = []
        monitor.republish()
    }

    @objc private func openInputMonitoring() {
        InputMonitoring.openSettings()
    }

    @objc private func toggleOnTop() {
        settings.alwaysOnTop.toggle()
        panel.setPinnedOnTop(settings.alwaysOnTop)
    }

    @objc private func toggleAlerts() {
        settings.lowBatteryAlerts.toggle()
    }

    @objc private func toggleLoginItem() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "无法更改“登录时打开”"
            NSApp.activate()
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
