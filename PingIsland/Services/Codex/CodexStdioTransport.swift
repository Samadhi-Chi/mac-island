import Darwin
import Foundation

/// A private, bounded JSONL channel attached only to the child we launch.
/// It never discovers a listener or connects to another user's/client's server.
nonisolated final class CodexStdioTransport: CodexMonitorTransport, @unchecked Sendable {
    private let input: FileHandle
    private let output: FileHandle
    private let lock = NSLock()
    private let writes = DispatchQueue(label: "MacIsland.CodexStdio.write")
    private let maximumBytes: Int
    private var buffer = Data()
    private var messages: [Data] = []
    private var queuedBytes = 0
    private var pendingWriteBytes = 0
    private var pendingWriteCount = 0
    private var waiter: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?
    private var closed = false
    private var started = false

    init(input: FileHandle, output: FileHandle, maximumBytes: Int = 32 * 1024 * 1024) {
        self.input = input
        self.output = output
        self.maximumBytes = maximumBytes
        _ = fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1)
        _ = fcntl(input.fileDescriptor, F_SETFL, fcntl(input.fileDescriptor, F_GETFL) | O_NONBLOCK)
        _ = fcntl(output.fileDescriptor, F_SETFL, fcntl(output.fileDescriptor, F_GETFL) | O_NONBLOCK)
    }

    func resume() {
        lock.lock()
        guard !closed, !started else {
            lock.unlock()
            return
        }
        started = true
        output.readabilityHandler = { [weak self] handle in
            self?.readAvailable(handle)
        }
        lock.unlock()
    }

    private func readAvailable(_ handle: FileHandle) {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        var bytes = [UInt8](repeating: 0, count: 65_536)
        let count = read(handle.fileDescriptor, &bytes, bytes.count)
        let temporaryFailure = count < 0 && (errno == EAGAIN || errno == EINTR)
        lock.unlock()
        if temporaryFailure { return }
        accept(count > 0 ? Data(bytes.prefix(count)) : Data())
    }

    private func accept(_ data: Data) {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        guard !data.isEmpty, data.count <= maximumBytes - buffer.count - queuedBytes else {
            lock.unlock()
            cancel(with: .goingAway, reason: nil)
            return
        }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if !line.isEmpty {
                messages.append(line)
                queuedBytes += line.count
            }
            // Tiny frames are bounded too, independently of the byte budget.
            if messages.count > 1_024 {
                lock.unlock()
                cancel(with: .messageTooBig, reason: nil)
                return
            }
        }
        let continuation = waiter
        let next = continuation == nil || messages.isEmpty ? nil : messages.removeFirst()
        if let next {
            queuedBytes -= next.count
            waiter = nil
        }
        lock.unlock()
        if let next { continuation?.resume(returning: .data(next)) }
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if closed {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                } else if !messages.isEmpty {
                    let next = messages.removeFirst()
                    queuedBytes -= next.count
                    lock.unlock()
                    continuation.resume(returning: .data(next))
                } else if waiter != nil {
                    lock.unlock()
                    continuation.resume(throwing: URLError(.cannotParseResponse))
                } else {
                    waiter = continuation
                    lock.unlock()
                }
            }
        } onCancel: {
            self.cancel(with: .goingAway, reason: nil)
        }
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let bytes): data = bytes
        @unknown default: throw CocoaError(.coderInvalidValue)
        }
        guard data.count < maximumBytes, !data.contains(10) else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            guard !closed, pendingWriteCount < 1_024, data.count + 1 <= maximumBytes - pendingWriteBytes else {
                lock.unlock()
                continuation.resume(throwing: URLError(.networkConnectionLost))
                return
            }
            pendingWriteBytes += data.count + 1
            pendingWriteCount += 1
            lock.unlock()
            writes.async { [self] in
                defer {
                    lock.lock()
                    pendingWriteBytes -= data.count + 1
                    pendingWriteCount -= 1
                    lock.unlock()
                }
                do {
                    try writeFrame(data + Data([10]))
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                    cancel(with: .goingAway, reason: nil)
                }
            }
        }
    }

    private func writeFrame(_ frame: Data) throws {
        // Retain a descriptor under the same lock as cancellation. Closing the
        // transport cannot redirect a queued write to a newly reused descriptor.
        let descriptor = lock.withLock { closed ? -1 : dup(input.fileDescriptor) }
        guard descriptor >= 0 else { throw CancellationError() }
        defer { Darwin.close(descriptor) }
        _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
        let deadline = Foundation.ProcessInfo.processInfo.systemUptime + 10
        try frame.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                guard lock.withLock({ !closed }) else { throw CancellationError() }
                guard Foundation.ProcessInfo.processInfo.systemUptime < deadline else { throw URLError(.timedOut) }
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count > 0 {
                    offset += count
                    continue
                }
                if count < 0 && errno == EINTR { continue }
                guard count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) else {
                    throw URLError(.networkConnectionLost)
                }
                var event = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
                _ = poll(&event, 1, 50)
            }
        }
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        closed = true
        let continuation = waiter
        waiter = nil
        buffer.removeAll()
        messages.removeAll()
        queuedBytes = 0
        lock.unlock()
        output.readabilityHandler = nil
        try? input.close()
        try? output.close()
        continuation?.resume(throwing: CancellationError())
    }
}
