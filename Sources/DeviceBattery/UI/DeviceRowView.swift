import AppKit
import BatteryCore

/// One device: ring gauge, name with a status line, and the percentage.
final class DeviceRowView: NSView {
    private(set) var reading: DeviceReading?
    private let strings: Strings
    private let ring = BatteryRingView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "")
    private let highlight = CALayer()
    private var isHovered = false {
        didSet { updateHighlight() }
    }

    init(strings: Strings) {
        self.strings = strings
        super.init(frame: .zero)
        wantsLayer = true
        highlight.cornerRadius = Theme.rowCornerRadius
        highlight.cornerCurve = .continuous
        layer?.addSublayer(highlight)
        configureLabels()
        layoutContent()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(with reading: DeviceReading, now: Date) {
        let isSameDevice = self.reading?.id == reading.id
        self.reading = reading
        let presentation = RowPresentation(reading, now: now, strings: strings)
        nameLabel.stringValue = reading.name
        detailLabel.stringValue = presentation.detail
        detailLabel.textColor = Theme.detailColor(for: presentation.tone)
        percentLabel.attributedStringValue = percentText(presentation)
        ring.update(
            fraction: presentation.fraction, tone: presentation.tone,
            symbol: Theme.symbol(for: reading), animated: isSameDevice
        )
        let source = strings.source(reading.source)
        toolTip = "\(reading.name)\n\(strings.tooltip(source: source, age: strings.age(of: reading.date, now: now)))"
        setAccessibilityLabel(strings.accessibilityLabel(name: reading.name, level: reading.level, detail: presentation.detail))
    }

    /// The row handles the mouse as a whole; clicks and drags bubble up to the widget.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func layout() {
        super.layout()
        CATransaction.performWithoutAnimation { highlight.frame = bounds }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateHighlight()
    }

    private func updateHighlight() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            highlight.backgroundColor = isHovered ? NSColor.labelColor.withAlphaComponent(0.07).cgColor : nil
        }
    }

    // MARK: - Layout

    private func configureLabels() {
        nameLabel.font = Theme.nameFont
        nameLabel.textColor = .labelColor
        detailLabel.font = Theme.detailFont
        for label in [nameLabel, detailLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        percentLabel.alignment = .right
        percentLabel.setContentHuggingPriority(.required, for: .horizontal)
        percentLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func layoutContent() {
        let text = NSStackView(views: [nameLabel, detailLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        text.setClippingResistancePriority(.defaultLow, for: .horizontal)
        for view in [ring, text, percentLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Theme.rowHeight),
            widthAnchor.constraint(equalToConstant: Theme.width - 2 * Theme.outerPadding),
            ring.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.rowInset),
            ring.centerYAnchor.constraint(equalTo: centerYAnchor),
            ring.widthAnchor.constraint(equalToConstant: Theme.ringDiameter),
            ring.heightAnchor.constraint(equalToConstant: Theme.ringDiameter),
            text.leadingAnchor.constraint(equalTo: ring.trailingAnchor, constant: 10),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: percentLabel.leadingAnchor, constant: -8),
            percentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.rowInset - 2),
            percentLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func percentText(_ presentation: RowPresentation) -> NSAttributedString {
        let color = Theme.percentColor(for: presentation.tone)
        let text = NSMutableAttributedString(
            string: presentation.percent,
            attributes: [.font: Theme.percentFont, .foregroundColor: color]
        )
        if reading?.level != nil {
            let signColor = presentation.tone == .normal ? NSColor.secondaryLabelColor : color
            text.append(NSAttributedString(string: "%", attributes: [.font: Theme.percentSignFont, .foregroundColor: signColor]))
        }
        return text
    }
}
