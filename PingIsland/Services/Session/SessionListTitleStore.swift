import Combine
import Foundation

/// Only the open list requests native metadata. No disk cache, inferred names,
/// thread resume, conversation reads, or background polling while closed.
@MainActor
final class SessionListTitleStore: ObservableObject {
    nonisolated deinit {}
    typealias Reader = @Sendable (RecentSessionRecord) async throws -> String?

    private struct Entry: Equatable {
        let title: SessionListTitle
        let observedName: String?
        let checkedAt: Date
    }

    @Published private var entries: [String: Entry] = [:]
    private let reader: Reader
    private let now: () -> Date
    private var generation: UInt64 = 0

    init(reader: Reader? = nil, now: @escaping () -> Date = Date.init) {
        self.now = now
        // Hosted tests and fixture playback must never touch a real client.
        let isolated = !SessionMonitor.allowsLiveMonitoring()
        self.reader =
            reader ?? { record in
                guard !isolated else { throw CancellationError() }
                return try await CodexReadOnlyClient.shared.readThreadName(threadId: record.nativeSessionID)
            }
    }

    func title(for record: RecentSessionRecord, observedSession: SessionState?) -> SessionListTitle {
        let observed = observedSession.flatMap {
            RecentSessionRecord(session: $0)?.id == record.id ? $0.sessionName : nil
        }
        if let entry = entries[record.id], entry.observedName == observed {
            return entry.title
        }
        // A live rename arriving during an older metadata read wins immediately.
        return .fromNativeName(observed)
    }

    func title(for session: SessionState) -> SessionListTitle {
        guard let record = RecentSessionRecord(session: session) else {
            return .fromNativeName(session.sessionName)
        }
        return title(for: record, observedSession: session)
    }

    func refresh(records: [RecentSessionRecord], observedSessions: [SessionState]) async {
        generation &+= 1
        let requestGeneration = generation
        let date = now()
        let unique = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        entries = entries.filter { unique[$0.key] != nil }
        let candidates = unique.values.filter { record in
            (record.client == .codexDesktop || record.client == .codexCLI)
                && record.origin != "unknown"
                && (entries[record.id].map { date.timeIntervalSince($0.checkedAt) >= 30 } ?? true)
        }.sorted { $0.id < $1.id }
        let reader = self.reader
        // Four outstanding summary-only reads at most; retain only this list's
        // identities. Cancelled / superseded batches cannot publish late names.
        await withTaskGroup(of: (RecentSessionRecord, SessionListTitle).self) { group in
            var remaining = candidates.makeIterator()
            func enqueue(_ record: RecentSessionRecord) {
                group.addTask {
                    let title: SessionListTitle
                    do { title = .fromNativeName(try await reader(record)) } catch { title = .unavailable }
                    return (record, title)
                }
            }
            for _ in 0..<4 { if let record = remaining.next() { enqueue(record) } }
            for await (record, title) in group {
                guard !Task.isCancelled, requestGeneration == generation else {
                    group.cancelAll()
                    return
                }
                let observed = SessionListPresentation.observedSession(for: record, in: observedSessions)
                // A failed read preserves an observed native name, but cannot
                // invent a title for a metadata-only historical record.
                entries[record.id] = Entry(
                    title: title == .unavailable ? .fromNativeName(observed?.sessionName) : title,
                    observedName: observed?.sessionName, checkedAt: date
                )
                if let record = remaining.next() { enqueue(record) }
            }
        }
    }
}
