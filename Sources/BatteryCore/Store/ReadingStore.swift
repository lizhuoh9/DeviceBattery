import Foundation

/// The widget's model: what each source reported last, plus the last known level of
/// every device seen with one.
///
/// A device that cannot be reached keeps its last known level (and the name and kind
/// learned while it was awake), so a sleeping keyboard still shows "86%, 3 hours ago",
/// even after its receiver was replugged or the app relaunched.
public struct ReadingStore: Sendable {
    /// Latest batch per source (one receiver, or Bluetooth).
    private var sources: [String: [DeviceReading]] = [:]
    /// Latest reading with a level, per device ID.
    private var memory: [String: DeviceReading]

    private static let kindOrder = Dictionary(
        uniqueKeysWithValues: DeviceKind.allCases.enumerated().map { ($1, $0) }
    )

    public init(remembered: [DeviceReading] = []) {
        memory = Dictionary(
            remembered.filter { $0.level != nil }.map { ($0.id, $0) },
            uniquingKeysWith: { first, second in first.date >= second.date ? first : second }
        )
    }

    /// Replaces everything `source` reported before with `readings`.
    public mutating func apply(_ readings: [DeviceReading], from source: String) {
        sources[source] = readings
        for reading in readings where reading.status == .online && reading.level != nil {
            memory[reading.id] = reading
        }
    }

    /// Forgets what `source` reported (its receiver was unplugged); levels stay remembered.
    public mutating func removeSource(_ source: String) {
        sources[source] = nil
    }

    /// What to show: one row per device, custom names applied, hidden devices removed,
    /// sorted by kind, then name, then ID.
    public func rows(customNames: [String: String] = [:], hidden: Set<String> = []) -> [DeviceReading] {
        var best: [String: DeviceReading] = [:]
        for reading in sources.values.joined() where !hidden.contains(reading.id) {
            best[reading.id] = best[reading.id].map { Self.better($0, reading) } ?? reading
        }
        return best.values
            .map { reading in
                let shown = Self.merged(reading, over: memory[reading.id])
                return customNames[shown.id].map(shown.renamed) ?? shown
            }
            .sorted(by: Self.displayOrder)
    }

    /// Every device worth remembering across launches.
    public var memorySnapshot: [DeviceReading] {
        Array(memory.values)
    }

    /// When two sources report the same device, an answering one wins, then the newer.
    private static func better(_ lhs: DeviceReading, _ rhs: DeviceReading) -> DeviceReading {
        if (lhs.status == .online) != (rhs.status == .online) {
            return lhs.status == .online ? lhs : rhs
        }
        return rhs.date > lhs.date ? rhs : lhs
    }

    /// An unreachable device shows what we knew, with the newer status and source.
    private static func merged(_ reading: DeviceReading, over remembered: DeviceReading?) -> DeviceReading {
        guard reading.status != .online, let remembered else { return reading }
        return DeviceReading(
            id: reading.id,
            name: remembered.name,
            kind: remembered.kind == .other ? reading.kind : remembered.kind,
            level: remembered.level,
            charge: remembered.charge,
            status: reading.status,
            components: remembered.components,
            symbol: remembered.symbol ?? reading.symbol,
            source: reading.source,
            date: remembered.date
        )
    }

    private static func displayOrder(_ lhs: DeviceReading, _ rhs: DeviceReading) -> Bool {
        let (left, right) = (kindOrder[lhs.kind] ?? 0, kindOrder[rhs.kind] ?? 0)
        if left != right { return left < right }
        switch lhs.name.localizedStandardCompare(rhs.name) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.id < rhs.id
        }
    }
}
