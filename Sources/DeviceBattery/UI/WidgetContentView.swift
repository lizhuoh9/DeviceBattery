import AppKit
import BatteryCore

/// The widget's surface: Liquid Glass (or vibrancy before macOS 26) holding the rows.
///
/// Dragging anywhere moves the widget; a click without a drag is reported to `onClick`.
final class WidgetContentView: NSView {
    /// What the rows sit on: the live material, or a flat color for offscreen previews.
    enum Surface {
        case glass
        case solid(NSColor)
    }

    var onClick: ((DeviceReading?) -> Void)?
    var menuProvider: ((DeviceReading?) -> NSMenu?)?

    private static let dragThreshold: CGFloat = 3

    private let stack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "没有发现无线设备")
    private var rows: [DeviceRowView] = []

    init(surface: Surface = .glass) {
        super.init(frame: .zero)
        let content = NSView()
        installBackground(around: content, surface: surface)

        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = Theme.rowSpacing
        stack.setClippingResistancePriority(.defaultLow, for: .horizontal)
        stack.edgeInsets = NSEdgeInsets(
            top: Theme.outerPadding, left: Theme.outerPadding, bottom: Theme.outerPadding, right: Theme.outerPadding
        )
        emptyLabel.font = Theme.detailFont
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        for view in [stack, emptyLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            widthAnchor.constraint(equalToConstant: Theme.width),
            heightAnchor.constraint(greaterThanOrEqualToConstant: Theme.rowHeight + 2 * Theme.outerPadding),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows `readings`, reusing row views so rings animate between levels.
    func show(_ readings: [DeviceReading], now: Date) {
        let existing = Dictionary(rows.compactMap { row in row.reading.map { ($0.id, row) } }, uniquingKeysWith: { first, _ in first })
        let updated = readings.map { reading in
            let row = existing[reading.id] ?? DeviceRowView()
            row.update(with: reading, now: now)
            return row
        }
        if updated.map(ObjectIdentifier.init) != rows.map(ObjectIdentifier.init) {
            stack.setViews(updated, in: .top)
            rows = updated
        }
        emptyLabel.isHidden = !readings.isEmpty
    }

    // MARK: - Mouse

    /// Tracks the press until release: past a few points it is a drag, otherwise a click.
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let startMouse = NSEvent.mouseLocation
        let startOrigin = window.frame.origin
        var isDragging = false
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type != .leftMouseUp {
            let mouse = NSEvent.mouseLocation
            let offset = CGVector(dx: mouse.x - startMouse.x, dy: mouse.y - startMouse.y)
            if !isDragging && hypot(offset.dx, offset.dy) < Self.dragThreshold { continue }
            isDragging = true
            window.setFrameOrigin(NSPoint(x: startOrigin.x + offset.dx, y: startOrigin.y + offset.dy))
        }
        if !isDragging {
            onClick?(reading(at: event))
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?(reading(at: event))
    }

    override var mouseDownCanMoveWindow: Bool { false }

    private func reading(at event: NSEvent) -> DeviceReading? {
        let point = convert(event.locationInWindow, from: nil)
        return rows.first { $0.convert($0.bounds, to: self).contains(point) }?.reading
    }

    // MARK: - Background

    private func installBackground(around content: NSView, surface: Surface) {
        let background: NSView
        if case let .solid(color) = surface {
            background = NSView()
            background.wantsLayer = true
            background.layer?.backgroundColor = color.cgColor
            background.layer?.cornerRadius = Theme.cornerRadius
            background.layer?.cornerCurve = .continuous
            pin(content, to: background)
        } else if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Theme.cornerRadius
            glass.contentView = content
            background = glass
        } else {
            let vibrancy = NSVisualEffectView()
            vibrancy.material = .popover
            vibrancy.blendingMode = .behindWindow
            vibrancy.state = .active
            vibrancy.wantsLayer = true
            vibrancy.layer?.cornerRadius = Theme.cornerRadius
            vibrancy.layer?.cornerCurve = .continuous
            vibrancy.layer?.masksToBounds = true
            pin(content, to: vibrancy)
            background = vibrancy
        }
        pin(background, to: self)
    }

    private func pin(_ child: NSView, to parent: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }
}
