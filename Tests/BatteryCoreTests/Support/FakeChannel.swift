@testable import BatteryCore

/// A scripted HID interface: answers each request through `respond`.
@MainActor
final class FakeChannel: ReportChannel {
    typealias Responder = ([UInt8]) -> Result<[UInt8], ChannelError>

    private let respond: Responder
    private(set) var sent: [[UInt8]] = []

    init(_ respond: @escaping Responder) {
        self.respond = respond
    }

    func exchange(
        _ request: [UInt8],
        timeout: Duration,
        accept: @escaping ([UInt8]) -> Bool
    ) async throws(ChannelError) -> [UInt8] {
        sent.append(request)
        let reply = try respond(request).get()
        // A reply the reader would not claim is the same as no reply at all.
        guard accept(reply) else { throw .timeout }
        return reply
    }
}

/// Builds a report from `bytes`, zero-padded to `length`.
func report(_ bytes: [UInt8], length: Int) -> [UInt8] {
    bytes + [UInt8](repeating: 0, count: max(0, length - bytes.count))
}
