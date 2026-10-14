import AppKit
import BatteryCore

/// `DeviceBattery --render-preview out.png` draws the widget with sample devices in light
/// and dark mode, side by side, for checking the design without a screen capture.
@MainActor
enum PreviewRenderer {
    static let argument = "--render-preview"
    private static let scale: CGFloat = 2
    private static let gap: CGFloat = 24

    static func run(arguments: [String]) -> Bool {
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else {
            return false
        }
        let url = URL(fileURLWithPath: arguments[index + 1])
        guard let png = render() else {
            FileHandle.standardError.write(Data("preview rendering failed\n".utf8))
            return true
        }
        do {
            try png.write(to: url)
        } catch {
            FileHandle.standardError.write(Data("could not write \(url.path): \(error.localizedDescription)\n".utf8))
        }
        return true
    }

    private static func render() -> Data? {
        let now = Date()
        let panes = [NSAppearance.Name.aqua, .darkAqua].compactMap { name -> CGImage? in
            guard let appearance = NSAppearance(named: name) else { return nil }
            let view = WidgetContentView(surface: .solid(name == .aqua ? NSColor(white: 0.94, alpha: 1) : NSColor(white: 0.17, alpha: 1)))
            view.appearance = appearance
            view.show(samples(now: now), now: now)
            return snapshot(of: view, appearance: appearance)
        }
        guard panes.count == 2 else { return nil }
        let width = panes.reduce(0) { $0 + $1.width } + Int(gap * scale) * 3
        let height = (panes.map(\.height).max() ?? 0) + Int(gap * scale) * 2
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(NSColor(srgbRed: 0.42, green: 0.55, blue: 0.68, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var x = Int(gap * scale)
        for pane in panes {
            context.draw(pane, in: CGRect(x: x, y: height - pane.height - Int(gap * scale), width: pane.width, height: pane.height))
            x += pane.width + Int(gap * scale)
        }
        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
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
        guard let layer = view.layer else { return nil }
        let size = view.bounds.size
        guard let context = CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        appearance.performAsCurrentDrawingAppearance {
            layer.render(in: context)
        }
        return context.makeImage()
    }

    private static func samples(now: Date) -> [DeviceReading] {
        let hour: TimeInterval = 3600
        return [
            DeviceReading(id: "1", name: "Wireless mouse 8k", kind: .mouse, level: 76, charge: .discharging, status: .online, source: "Compx 2.4G", date: now),
            DeviceReading(id: "2", name: "ROG Harpe Ace Mini", kind: .mouse, level: 8, charge: .discharging, status: .online, source: "ROG Omni", date: now),
            DeviceReading(id: "3", name: "MX Keys S", kind: .keyboard, level: 86, charge: .discharging, status: .asleep, source: "Logi Bolt", date: now - 3 * hour),
            DeviceReading(id: "4", name: "ROG 无线键盘", kind: .keyboard, level: 43, charge: .charging, status: .online, source: "ROG Omni", date: now),
            DeviceReading(id: "5", name: "我的AirPods", kind: .headphones, level: 18,
                          status: .online, components: [.init(label: "左", level: 18), .init(label: "右", level: 22), .init(label: "盒", level: 64)],
                          symbol: "airpods", source: "蓝牙", date: now),
            DeviceReading(id: "6", name: "Compx 鼠标", kind: .mouse, level: nil, status: .needsPermission, source: "Compx 2.4G", date: now),
        ]
    }
}
