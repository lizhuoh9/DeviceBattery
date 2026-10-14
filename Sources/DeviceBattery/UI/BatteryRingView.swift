import AppKit
import BatteryCore

/// A circular level gauge with the device glyph inside and a status badge on its edge.
final class BatteryRingView: NSView {
    private let track = CAShapeLayer()
    private let progress = CAShapeLayer()
    private let glyph = NSImageView()
    private let badge = NSImageView()
    private var tone = RowTone.normal

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for ring in [track, progress] {
            ring.fillColor = nil
            ring.lineWidth = Theme.ringLineWidth
            ring.lineCap = .round
            layer?.addSublayer(ring)
        }
        progress.strokeEnd = 0
        glyph.imageScaling = .scaleProportionallyDown
        badge.imageScaling = .scaleProportionallyDown
        addSubview(glyph)
        addSubview(badge)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Theme.ringDiameter, height: Theme.ringDiameter)
    }

    override func layout() {
        super.layout()
        let inset = Theme.ringLineWidth / 2
        let circle = bounds.insetBy(dx: inset, dy: inset)
        // Start at 12 o'clock and run clockwise, like the system battery widget.
        let path = CGMutablePath()
        path.addArc(
            center: CGPoint(x: circle.midX, y: circle.midY), radius: circle.width / 2,
            startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true
        )
        track.path = path
        progress.path = path
        glyph.frame = bounds.insetBy(dx: 8, dy: 8)
        let badgeSize: CGFloat = 13
        badge.frame = NSRect(x: bounds.maxX - badgeSize + 2, y: bounds.minY - 2, width: badgeSize, height: badgeSize)
    }

    func update(fraction: Double?, tone: RowTone, symbol: String, animated: Bool) {
        self.tone = tone
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: Theme.glyphPointSize, weight: .medium))
        badge.image = Theme.badgeSymbol(for: tone).flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }?
            .withSymbolConfiguration(.init(paletteColors: [.white, Theme.accent(for: tone)]))
        badge.isHidden = badge.image == nil
        applyColors()

        let target = CGFloat(fraction ?? 0)
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, progress.strokeEnd != target else {
            CATransaction.performWithoutAnimation { progress.strokeEnd = target }
            return
        }
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = progress.presentation()?.strokeEnd ?? progress.strokeEnd
        animation.toValue = target
        animation.duration = Theme.ringAnimation
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        progress.strokeEnd = target
        progress.add(animation, forKey: "level")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    /// CALayer colors are not dynamic; resolve them for the current appearance.
    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.performWithoutAnimation {
                track.strokeColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
                progress.strokeColor = Theme.accent(for: tone).cgColor
            }
        }
        glyph.contentTintColor = tone == .inactive ? .tertiaryLabelColor : .labelColor
    }
}

extension CATransaction {
    static func performWithoutAnimation(_ changes: () -> Void) {
        begin()
        setDisableActions(true)
        changes()
        commit()
    }
}
