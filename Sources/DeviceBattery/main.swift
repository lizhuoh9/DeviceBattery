import AppKit
import BatteryCore

/// Starts the widget. The app has no Dock icon or menu bar (LSUIElement);
/// everything lives in the widget's right-click menu.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: WidgetController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = Settings()
        let strings = Strings.current
        let controller = WidgetController(
            settings: settings, monitor: BatteryMonitor(settings: settings, strings: strings), strings: strings
        )
        controller.start()
        self.controller = controller
    }
}

let app = NSApplication.shared
if PreviewRenderer.run(arguments: CommandLine.arguments) {
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
