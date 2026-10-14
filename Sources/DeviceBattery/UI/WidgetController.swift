import AppKit
import BatteryCore

/// Connects the monitor to the panel and handles the widget's menu.
@MainActor
final class WidgetController: NSObject {
    private let settings: Settings
    private let monitor: BatteryMonitor
    private let strings: Strings
    private let content: WidgetContentView
    private lazy var panel = WidgetPanel(content: content)
    private var rows: [DeviceReading] = []

    init(settings: Settings, monitor: BatteryMonitor, strings: Strings) {
        self.settings = settings
        self.monitor = monitor
        self.strings = strings
        content = WidgetContentView(strings: strings)
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
        menu.addItem(item(strings.refreshNow, #selector(refresh)))
        if let reading {
            menu.addItem(.separator())
            menu.addItem(item(strings.rename(reading.name), #selector(rename), id: reading.id))
            menu.addItem(item(strings.hide(reading.name), #selector(hide), id: reading.id))
            if reading.status == .needsPermission {
                menu.addItem(item(strings.openInputMonitoring, #selector(openInputMonitoring)))
            }
        }
        let hiddenCount = settings.hidden.count
        if hiddenCount > 0 {
            menu.addItem(item(strings.showHidden(hiddenCount), #selector(showHidden)))
        }
        menu.addItem(.separator())
        menu.addItem(item(strings.keepOnTop, #selector(toggleOnTop), on: settings.alwaysOnTop))
        menu.addItem(item(strings.lowBatteryAlerts, #selector(toggleAlerts), on: settings.lowBatteryAlerts))
        menu.addItem(item(strings.openAtLogin, #selector(toggleLoginItem), on: LoginItem.isEnabled))
        menu.addItem(.separator())
        menu.addItem(item(strings.quit, #selector(quit)))
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
        alert.messageText = strings.renameTitle
        alert.informativeText = strings.renameHint
        let field = NSTextField(string: settings.customNames[id] ?? reading.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: strings.ok)
        alert.addButton(withTitle: strings.cancel)
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
            alert.messageText = strings.loginItemError
            NSApp.activate()
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
