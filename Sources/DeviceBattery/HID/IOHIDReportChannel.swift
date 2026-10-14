import BatteryCore
import Foundation
import IOKit.hid

/// A `ReportChannel` over one IOHIDDevice, with input delivered on the main run loop.
///
/// The device is opened lazily and non-exclusively, so normal input keeps working and
/// vendor apps can talk to it too. Input reports that answer nothing pending go to
/// `onUnsolicitedReport` (e.g. HID++ connection notifications).
@MainActor
final class IOHIDReportChannel: ReportChannel {
    private struct Pending {
        let token: Int
        let accept: ([UInt8]) -> Bool
        let continuation: CheckedContinuation<Result<[UInt8], ChannelError>, Never>
        let timeout: Task<Void, Never>
    }

    /// Lets the device cross to the background queue that sends output reports.
    private struct SendableDevice: @unchecked Sendable {
        let device: IOHIDDevice
    }

    var onUnsolicitedReport: (([UInt8]) -> Void)?

    // The IOKit objects below are also touched by the nonisolated deinit, which only runs
    // once nothing else references the channel.
    nonisolated(unsafe) private let device: IOHIDDevice
    nonisolated(unsafe) private let buffer: UnsafeMutablePointer<UInt8>
    nonisolated(unsafe) private var isOpen = false
    private let bufferSize: Int
    private var isInvalidated = false
    private var pending: Pending?
    private var nextToken = 0

    /// Common modes, so replies still arrive while a menu or an alert is open.
    private static let runLoopMode = CFRunLoopMode.commonModes.rawValue

    init(device: IOHIDDevice) {
        self.device = device
        let maxInput = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 64
        bufferSize = max(maxInput, 64)
        buffer = .allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
    }

    deinit {
        // Safety net: owners close channels first, but a callback must never outlive the buffer.
        if isOpen {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        buffer.deallocate()
    }

    func close() {
        if isOpen {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), Self.runLoopMode)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            isOpen = false
        }
        finish(with: .failure(.closed))
    }

    /// Closes for good: the device was unplugged, so an in-flight read must not reopen it.
    func invalidate() {
        isInvalidated = true
        close()
    }

    func exchange(
        _ request: [UInt8],
        timeout: Duration,
        accept: @escaping ([UInt8]) -> Bool
    ) async throws(ChannelError) -> [UInt8] {
        try open()
        guard pending == nil, let reportID = request.first else { throw .ioFailure(kIOReturnBusy) }
        nextToken += 1
        let token = nextToken
        let result = await withCheckedContinuation { continuation in
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.expire(token)
            }
            pending = Pending(token: token, accept: accept, continuation: continuation, timeout: timeoutTask)
            send(request, reportID: reportID, token: token)
        }
        return try result.get()
    }

    // MARK: - Private

    private func open() throws(ChannelError) {
        guard !isInvalidated else { throw .closed }
        guard !isOpen else { return }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw result == kIOReturnNotPermitted ? .notPermitted : .ioFailure(result)
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, { context, _, _, _, _, report, length in
            guard let context else { return }
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            MainActor.assumeIsolated {
                Unmanaged<IOHIDReportChannel>.fromOpaque(context).takeUnretainedValue().receive(bytes)
            }
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), Self.runLoopMode)
        isOpen = true
    }

    /// Output reports go out on a background queue: the call blocks until the report is
    /// issued, and a wedged dongle must not freeze the widget. The timeout still applies.
    private func send(_ request: [UInt8], reportID: UInt8, token: Int) {
        let target = SendableDevice(device: device)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = request.withUnsafeBufferPointer { bytes in
                IOHIDDeviceSetReport(target.device, kIOHIDReportTypeOutput, CFIndex(reportID), bytes.baseAddress!, bytes.count)
            }
            guard result != kIOReturnSuccess else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.pending?.token == token else { return }
                    self.finish(with: .failure(result == kIOReturnNotPermitted ? .notPermitted : .ioFailure(result)))
                }
            }
        }
    }

    private func receive(_ report: [UInt8]) {
        if let pending, pending.accept(report) {
            finish(with: .success(report))
        } else {
            onUnsolicitedReport?(report)
        }
    }

    private func expire(_ token: Int) {
        guard pending?.token == token else { return }
        finish(with: .failure(.timeout))
    }

    private func finish(with result: Result<[UInt8], ChannelError>) {
        guard let pending else { return }
        self.pending = nil
        pending.timeout.cancel()
        pending.continuation.resume(returning: result)
    }
}
