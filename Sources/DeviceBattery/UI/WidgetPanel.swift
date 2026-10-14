import AppKit

/// A borderless panel that lives on the desktop: below normal windows, on every Space,
/// never taking focus from the app you are using.
final class WidgetPanel: NSPanel {
    private static let autosaveName = "DeviceBatteryWidget"
    private static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    init(content: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Theme.width, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        contentView = content
        setPinnedOnTop(false)
        restorePosition()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Floats above other windows instead of sitting on the desktop.
    func setPinnedOnTop(_ onTop: Bool) {
        level = onTop ? .floating : Self.desktopLevel
    }

    /// Resizes to fit the rows, keeping the top edge where the user put it.
    func fitContent() {
        guard let contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        let size = contentView.fittingSize
        guard size != frame.size else { return }
        let top = frame.maxY
        setFrame(NSRect(x: frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    /// Uses the saved position, or the top-right corner of the main screen the first time
    /// (and whenever the saved spot is on a display that is no longer connected).
    private func restorePosition() {
        let restored = setFrameUsingName(Self.autosaveName)
        setFrameAutosaveName(Self.autosaveName)
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        guard !restored || !onScreen, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        setFrameTopLeftPoint(NSPoint(
            x: visible.maxX - frame.width - Theme.screenMargin,
            y: visible.maxY - Theme.screenMargin
        ))
    }
}
