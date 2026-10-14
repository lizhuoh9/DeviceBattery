import Foundation

/// Why a report exchange failed.
public enum ChannelError: Error, Equatable, Sendable {
    /// No matching input report arrived in time.
    case timeout
    /// macOS refused to open the interface (Input Monitoring is not granted).
    case notPermitted
    /// The OS returned an IOKit error code.
    case ioFailure(Int32)
    /// The device went away.
    case closed
}

/// One HID interface that accepts output reports and answers with input reports.
///
/// Byte 0 of every request and reply is the report ID.
@MainActor
public protocol ReportChannel: AnyObject {
    /// Sends `request` and returns the first input report `accept` claims as its answer.
    func exchange(
        _ request: [UInt8],
        timeout: Duration,
        accept: @escaping ([UInt8]) -> Bool
    ) async throws(ChannelError) -> [UInt8]
}

/// Something that can report the batteries of the devices behind it.
@MainActor
public protocol BatteryReader: AnyObject {
    func read() async -> [DeviceReading]
}

extension Array where Element == UInt8 {
    /// The array zero-padded (or truncated) to `length` bytes.
    func padded(to length: Int) -> [UInt8] {
        count >= length ? Array(prefix(length)) : self + [UInt8](repeating: 0, count: length - count)
    }

    /// The byte at `index`, or 0 when the report is shorter.
    func byte(at index: Int) -> UInt8 {
        indices.contains(index) ? self[index] : 0
    }

    /// Uppercase hex without separators, e.g. `1A2B3C4D`.
    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}
