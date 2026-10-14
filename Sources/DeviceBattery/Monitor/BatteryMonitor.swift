import AppKit
import BatteryCore
import OSLog

/// Owns the reading store and decides when to read what.
///
/// Every source is read once a minute while the widget is visible and every five minutes
/// while it is covered; receiver plug-in, device wake-up events and system wake trigger
/// an early read. Nothing polls in between.
@MainActor
final class BatteryMonitor {
    static let visibleInterval: TimeInterval = 60
    static let hiddenInterval: TimeInterval = 300
    private static let eventDelay: Duration = .milliseconds(1500)
    private static let eventAttempts = 3

    var onUpdate: (([DeviceReading]) -> Void)?

    private let settings: Settings
    private let notifier = Notifier()
    private let watcher = HIDDeviceWatcher()
    private let log = Logger(subsystem: "local.DeviceBattery", category: "monitor")
    private var store: ReadingStore
    private var alerts = LowBatteryPolicy()
    private var timer: Timer?
    private var isVisible = true
    private var isRefreshing = false
    private var refreshQueued = false
    private var pendingEvents: [String: Task<Void, Never>] = [:]
    private var lastRefresh = Date.distantPast
    private var lastPublished: [DeviceReading] = []
    private var askedForInputMonitoring = false

    init(settings: Settings) {
        self.settings = settings
        store = ReadingStore(remembered: settings.remembered)
    }

    func start() {
        watcher.onChange = { [weak self] change in self?.handle(change) }
        watcher.start()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSoon() }
        }
        scheduleTimer()
        refresh()
    }

    /// The widget became visible or covered; adjusts the cadence and catches up if stale.
    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        scheduleTimer()
        if visible && Date().timeIntervalSince(lastRefresh) > 30 { refresh() }
    }

    /// Re-publishes rows after a settings change (names, hidden devices).
    func republish() {
        publish()
    }

    func refresh() {
        guard !isRefreshing else {
            refreshQueued = true
            return
        }
        isRefreshing = true
        Task {
            for session in watcher.sessions.values.sorted(by: { $0.key < $1.key }) {
                await read(session)
            }
            if let bluetooth = await BluetoothSource.read() {
                store.apply(bluetooth, from: BluetoothSource.key)
            }
            lastRefresh = Date()
            publish()
            isRefreshing = false
            if refreshQueued {
                refreshQueued = false
                refresh()
            }
        }
    }

    // MARK: - Private

    /// Reads one receiver into the store; false when it was busy with another read.
    @discardableResult
    private func read(_ session: ReceiverSession) async -> Bool {
        guard let readings = await session.read() else { return false }
        guard watcher.sessions[session.key] != nil else { return true }  // unplugged meanwhile
        store.apply(readings, from: session.key)
        if readings.contains(where: { $0.status == .needsPermission }) {
            requestInputMonitoringOnce()
        }
        return true
    }

    private func handle(_ change: HIDDeviceWatcher.Change) {
        switch change {
        case let .added(session):
            session.onEvent = { [weak self, key = session.key] in self?.readSoon(key) }
            readSoon(session.key)
        case let .removed(key):
            pendingEvents.removeValue(forKey: key)?.cancel()
            store.removeSource(key)
            publish()
        }
    }

    /// Reads one receiver shortly; repeated events collapse into a single read, and an event
    /// that lands during another read is retried rather than dropped.
    private func readSoon(_ key: String) {
        pendingEvents[key]?.cancel()
        pendingEvents[key] = Task { [weak self] in
            for _ in 0..<Self.eventAttempts {
                try? await Task.sleep(for: Self.eventDelay)
                guard !Task.isCancelled, let self, let session = watcher.sessions[key] else { return }
                if await read(session) {
                    publish()
                    break
                }
            }
            self?.pendingEvents[key] = nil
        }
    }

    private func refreshSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.refresh()
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = isVisible ? Self.visibleInterval : Self.hiddenInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Pushes rows to the UI (always, so "3 小时前" stays current); logs, persists and
    /// alerts only when a level, state or name actually changed.
    private func publish() {
        let rows = store.rows(customNames: settings.customNames, hidden: settings.hidden)
        onUpdate?(rows)
        let previous = Set(lastPublished.map(\.signature))
        let changed = rows.filter { !previous.contains($0.signature) }
        lastPublished = rows
        guard !changed.isEmpty else { return }
        for row in changed {
            // Device names can identify the owner ("某某的 AirPods"), so they stay private.
            log.notice("\(row.source, privacy: .public) \(row.kind.rawValue, privacy: .public) \(row.name, privacy: .private): \(row.level ?? -1, privacy: .public)% \(row.charge.rawValue, privacy: .public) \(row.status.rawValue, privacy: .public)")
        }
        settings.remembered = store.memorySnapshot
        guard settings.lowBatteryAlerts else { return }
        for alert in alerts.evaluate(changed) {
            notifier.post(alert)
        }
    }

    private func requestInputMonitoringOnce() {
        guard !askedForInputMonitoring else { return }
        askedForInputMonitoring = true
        InputMonitoring.requestIfUndetermined()
    }
}

private extension DeviceReading {
    /// Everything that matters to the user, without the timestamp.
    var signature: String {
        "\(id)|\(name)|\(kind)|\(level ?? -1)|\(charge)|\(status)|\(components.map(\.level))"
    }
}
