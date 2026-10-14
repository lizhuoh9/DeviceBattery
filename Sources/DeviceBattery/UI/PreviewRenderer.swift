import AppKit
import BatteryCore

/// `DeviceBattery --render-preview out.png [--language en|ko|zh-Hans]` draws the widget with
/// sample devices in light and dark mode, side by side, for checking the design without a
/// screen capture (and for the README).
@MainActor
enum PreviewRenderer {
    static let argument = "--render-preview"
    private static let languageArgument = "--language"
    private static let scale: CGFloat = 2
    private static let gap: CGFloat = 24

    static func run(arguments: [String]) -> Bool {
        guard let path = value(after: argument, in: arguments) else { return false }
        let language = value(after: languageArgument, in: arguments).flatMap(AppLanguage.init(rawValue:))
        let strings = language.map(Strings.init) ?? .current
        guard let png = render(strings: strings) else {
            FileHandle.standardError.write(Data("preview rendering failed\n".utf8))
            return true
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            FileHandle.standardError.write(Data("could not write \(path): \(error.localizedDescription)\n".utf8))
        }
        return true
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func render(strings: Strings) -> Data? {
        let now = Date()
        let light = pane(appearance: .aqua, background: NSColor(white: 0.94, alpha: 1), strings: strings, now: now)
        let dark = pane(appearance: .darkAqua, background: NSColor(white: 0.17, alpha: 1), strings: strings, now: now)
        guard let light, let dark else { return nil }

        let margin = Int(gap * scale)
        let width = light.width + dark.width + margin * 3
        let height = max(light.height, dark.height) + margin * 2
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.setFillColor(NSColor(srgbRed: 0.42, green: 0.55, blue: 0.68, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(light, in: CGRect(x: margin, y: height - light.height - margin, width: light.width, height: light.height))
        context.draw(dark, in: CGRect(x: margin * 2 + light.width, y: height - dark.height - margin, width: dark.width, height: dark.height))
        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private static func pane(appearance name: NSAppearance.Name, background: NSColor, strings: Strings, now: Date) -> CGImage? {
        guard let appearance = NSAppearance(named: name) else { return nil }
        let view = WidgetContentView(strings: strings, surface: .solid(background))
        view.appearance = appearance
        view.show(samples(strings: strings, now: now), now: now)
        return snapshot(of: view, appearance: appearance)
    }

    private static func snapshot(of view: NSView, appearance: NSAppearance) -> CGImage? {
        // Layers only get their contents drawn inside a window; this one is never shown.
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        window.setContentSize(view.fittingSize)
        view.layoutSubtreeIfNeeded()
        window.display()
        guard let layer = view.layer, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let size = view.bounds.size
        guard let context = CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
            bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        appearance.performAsCurrentDrawingAppearance {
            layer.render(in: context)
        }
        return context.makeImage()
    }

    private static func samples(strings: Strings, now: Date) -> [DeviceReading] {
        let threeHoursAgo = now.addingTimeInterval(-3 * 3600)
        let buds: [BatteryComponent] = [
            BatteryComponent(role: .left, level: 18),
            BatteryComponent(role: .right, level: 22),
            BatteryComponent(role: .chargingCase, level: 64),
        ]
        return [
            DeviceReading(id: "1", name: "Wireless mouse 8k", kind: .mouse, level: 76, charge: .discharging,
                          status: .online, source: "Compx 2.4G", date: now),
            DeviceReading(id: "2", name: "ROG Harpe Ace Mini", kind: .mouse, level: 8, charge: .discharging,
                          status: .online, source: "ROG Omni", date: now),
            DeviceReading(id: "3", name: "MX Keys S", kind: .keyboard, level: 86, charge: .discharging,
                          status: .asleep, source: "Logi Bolt", date: threeHoursAgo),
            DeviceReading(id: "4", name: strings.rogDevice(kind: .keyboard), kind: .keyboard, level: 43,
                          charge: .charging, status: .online, source: "ROG Omni", date: now),
            DeviceReading(id: "5", name: strings.myAirPods, kind: .headphones, level: 18, status: .online,
                          components: buds, symbol: "airpods", source: BluetoothProfileParser.source, date: now),
            DeviceReading(id: "6", name: strings.wirelessMouse, kind: .mouse, level: nil,
                          status: .needsPermission, source: "Compx 2.4G", date: now),
        ]
    }
}
