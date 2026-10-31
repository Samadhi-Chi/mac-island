import Foundation
import XCTest

@testable import Ping_Island

final class CodexConversationMergeTests: XCTestCase {
    func testEmptyAppServerHistoryDoesNotEraseRichRolloutHistory() {
        let existing = [
            ChatHistoryItem(
                id: "rollout-user",
                type: .user("继续"),
                timestamp: Date(timeIntervalSince1970: 10)
            ),
            ChatHistoryItem(
                id: "rollout-status",
                type: .thinking("正在修复最新状态"),
                timestamp: Date(timeIntervalSince1970: 11)
            ),
        ]

        XCTAssertEqual(
            SessionStore.mergedCodexHistory(existing: existing, incoming: []),
            existing
        )
    }

    func testAppServerNarrativeMergesWithoutDuplicatingRolloutText() {
        let existing = [
            ChatHistoryItem(
                id: "rollout-status",
                type: .thinking("正在修复最新状态"),
                timestamp: Date(timeIntervalSince1970: 10)
            )
        ]
        let incoming = [
            ChatHistoryItem(
                id: "app-server-status",
                type: .thinking("正在修复最新状态"),
                timestamp: Date(timeIntervalSince1970: 10.5)
            ),
            ChatHistoryItem(
                id: "app-server-final",
                type: .assistant("修复完成"),
                timestamp: Date(timeIntervalSince1970: 21)
            ),
        ]

        let merged = SessionStore.mergedCodexHistory(
            existing: existing,
            incoming: incoming
        )
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.last?.type, .assistant("修复完成"))
    }

    func testRepeatedTextAcrossTurnsIsPreservedAndHistoryRemainsChronological() {
        let existing = [
            ChatHistoryItem(
                id: "rollout-first-user",
                type: .user("继续"),
                timestamp: Date(timeIntervalSince1970: 1_000)
            ),
            ChatHistoryItem(
                id: "rollout-first-final",
                type: .assistant("第一轮完成"),
                timestamp: Date(timeIntervalSince1970: 1_020)
            ),
            ChatHistoryItem(
                id: "rollout-second-user",
                type: .user("继续"),
                timestamp: Date(timeIntervalSince1970: 1_040)
            ),
            ChatHistoryItem(
                id: "rollout-latest-status",
                type: .thinking("正在处理第二轮"),
                timestamp: Date(timeIntervalSince1970: 1_050)
            ),
        ]
        let incoming = [
            ChatHistoryItem(
                id: "app-first-user",
                type: .user("继续"),
                timestamp: Date(timeIntervalSince1970: 101)
            ),
            ChatHistoryItem(
                id: "app-first-final",
                type: .assistant("第一轮完成"),
                timestamp: Date(timeIntervalSince1970: 102)
            ),
            ChatHistoryItem(
                id: "app-second-user",
                type: .user("继续"),
                timestamp: Date(timeIntervalSince1970: 103)
            ),
            ChatHistoryItem(
                id: "app-latest-status",
                type: .thinking("正在处理第二轮"),
                timestamp: Date(timeIntervalSince1970: 104)
            ),
            ChatHistoryItem(
                id: "app-second-final",
                type: .assistant("第二轮完成"),
                timestamp: Date(timeIntervalSince1970: 105)
            ),
        ]

        let merged = SessionStore.mergedCodexHistory(
            existing: existing,
            incoming: incoming
        )

        XCTAssertEqual(
            merged.map(\.id),
            [
                "rollout-first-user",
                "rollout-first-final",
                "rollout-second-user",
                "rollout-latest-status",
                "app-second-final",
            ]
        )
        XCTAssertEqual(
            merged.filter { item in
                if case .user("继续") = item.type { return true }
                return false
            }.count, 2)
        XCTAssertEqual(merged.last?.type, .assistant("第二轮完成"))
    }

    func testDuplicateToolKeepsTerminalStatusAndOriginalChronology() {
        let running = ChatHistoryItem(
            id: "rollout-tool",
            type: .toolCall(
                ToolCallItem(
                    name: "exec_command",
                    input: ["command": "xcodebuild test"],
                    status: .running,
                    result: nil,
                    structuredResult: nil,
                    subagentTools: []
                )),
            timestamp: Date(timeIntervalSince1970: 12)
        )
        let completed = ChatHistoryItem(
            id: "app-server-tool",
            type: .toolCall(
                ToolCallItem(
                    name: "exec_command",
                    input: ["command": "xcodebuild test"],
                    status: .success,
                    result: "passed",
                    structuredResult: nil,
                    subagentTools: []
                )),
            timestamp: Date(timeIntervalSince1970: 12.4)
        )

        let merged = SessionStore.mergedCodexHistory(
            existing: [completed],
            incoming: [running]
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.timestamp, completed.timestamp)
        guard case .toolCall(let tool) = merged.first?.type else {
            return XCTFail("Expected merged tool")
        }
        XCTAssertEqual(tool.status, .success)
        XCTAssertEqual(tool.result, "passed")
    }

    func testRepeatedSameToolAcrossTurnsMatchesByOccurrenceNotSyntheticTime() {
        func tool(id: String, status: ToolStatus, timestamp: TimeInterval) -> ChatHistoryItem {
            ChatHistoryItem(
                id: id,
                type: .toolCall(
                    ToolCallItem(
                        name: "exec_command",
                        input: ["command": "git status"],
                        status: status,
                        result: status == .success ? "done" : nil,
                        structuredResult: nil,
                        subagentTools: []
                    )),
                timestamp: Date(timeIntervalSince1970: timestamp)
            )
        }

        let rollout = [
            tool(id: "rollout-old", status: .success, timestamp: 1_000),
            tool(id: "rollout-new", status: .running, timestamp: 2_000),
        ]
        let appServer = [
            tool(id: "app-old", status: .success, timestamp: 101),
            tool(id: "app-new", status: .running, timestamp: 102),
        ]
        let merged = SessionStore.mergedCodexHistory(
            existing: rollout,
            incoming: appServer
        )

        XCTAssertEqual(merged.count, 2)
        guard case .toolCall(let oldTool) = merged[0].type,
            case .toolCall(let newTool) = merged[1].type
        else {
            return XCTFail("Expected two separate tool occurrences")
        }
        XCTAssertEqual(oldTool.status, .success)
        XCTAssertEqual(newTool.status, .running)
    }
}
