import Foundation

/// The small transport boundary also lets lifecycle tests use in-memory messages
/// without opening a socket or starting a Codex process.
nonisolated protocol CodexMonitorTransport: AnyObject, Sendable {
    func resume()
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

extension URLSessionWebSocketTask: CodexMonitorTransport {}
