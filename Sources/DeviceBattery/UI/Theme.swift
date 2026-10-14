import AppKit
import BatteryCore

/// Sizes, fonts and colors of the widget in one place.
@MainActor
enum Theme {
    static let width: CGFloat = 284
    static let cornerRadius: CGFloat = 20
    static let outerPadding: CGFloat = 8
    static let rowHeight: CGFloat = 46
    static let rowSpacing: CGFloat = 0
    static let rowInset: CGFloat = 8
    static let rowCornerRadius: CGFloat = 12
    static let ringDiameter: CGFloat = 32
    static let ringLineWidth: CGFloat = 3
    static let glyphPointSize: CGFloat = 13
    static let screenMargin: CGFloat = 24

    static let nameFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let detailFont = NSFont.systemFont(ofSize: 11)
    static let percentFont = rounded(size: 19, weight: .semibold)
    static let percentSignFont = rounded(size: 11, weight: .semibold)

    static let ringAnimation: CFTimeInterval = 0.45

    /// SF Pro Rounded with monospaced digits, so percentages do not jitter as they change.
    private static func rounded(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// Healthy levels stay neutral so only the rows that need attention carry color.
    private static let neutral = NSColor(name: "neutralRing") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.9)
            : NSColor(white: 0, alpha: 0.68)
    }

    /// Color for the ring and badge.
    static func accent(for tone: RowTone) -> NSColor {
        switch tone {
        case .normal: neutral
        case .low: .systemOrange
        case .critical: .systemRed
        case .charging: .systemGreen
        case .inactive: .tertiaryLabelColor
        case .attention: .systemOrange
        }
    }

    static func percentColor(for tone: RowTone) -> NSColor {
        switch tone {
        case .normal: .labelColor
        case .inactive: .secondaryLabelColor
        default: accent(for: tone)
        }
    }

    static func detailColor(for tone: RowTone) -> NSColor {
        switch tone {
        case .critical: .systemRed
        case .low, .attention: .systemOrange
        default: .secondaryLabelColor
        }
    }

    /// The badge drawn on the ring's lower-right edge, if any.
    static func badgeSymbol(for tone: RowTone) -> String? {
        switch tone {
        case .charging: "bolt.circle.fill"
        case .inactive: "moon.circle.fill"
        case .attention: "exclamationmark.circle.fill"
        default: nil
        }
    }

    static func symbol(for reading: DeviceReading) -> String {
        if let symbol = reading.symbol { return symbol }
        switch reading.kind {
        case .mouse: return "computermouse.fill"
        case .keyboard: return "keyboard.fill"
        case .trackpad: return "rectangle.and.hand.point.up.left.fill"
        case .headphones: return "headphones"
        case .gamepad: return "gamecontroller.fill"
        case .speaker: return "hifispeaker.fill"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }
}
