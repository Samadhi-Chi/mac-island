import Foundation
import XCTest

@testable import Ping_Island

final class MacIslandConversationDetailTests: XCTestCase {
    func testDetailPreservesLatestUserAndMultilineAssistant() throws {
        let start = Date(timeIntervalSince1970: 100)
        let session = SessionState(
            sessionId: "detail-final",
            cwd: "/tmp/mac-island",
            provider: .codex,
            clientInfo: .codexApp(threadId: "detail-final"),
            phase: .idle,
            chatItems: [
                ChatHistoryItem(id: "u1", type: .user("继续"), timestamp: start),
                ChatHistoryItem(
                    id: "a1",
                    type: .assistant("已完成：\n\n- 修复状态\n- 恢复动效"),
                    timestamp: start.addingTimeInterval(1)
                ),
            ]
        )

        let detail = MacIslandConversationDetailBuilder.make(from: session)
        XCTAssertEqual(detail.userText, "继续")
        XCTAssertEqual(detail.assistantText, "已完成：\n\n- 修复状态\n- 恢复动效")
        XCTAssertNil(detail.activity)
    }

    func testDetailUsesArrayOrderWhenAppServerTimestampIsNotComparable() throws {
        let session = SessionState(
            sessionId: "detail-cross-source-order",
            cwd: "/tmp/mac-island",
            provider: .codex,
            clientInfo: .codexApp(threadId: "detail-cross-source-order"),
            phase: .idle,
            chatItems: [
                ChatHistoryItem(
                    id: "old-rollout-assistant",
                    type: .assistant("上一轮回复"),
                    timestamp: Date(timeIntervalSince1970: 1_000)
                ),
                ChatHistoryItem(
                    id: "latest-rollout-user",
                    type: .user("最新问题"),
                    timestamp: Date(timeIntervalSince1970: 1_100)
                ),
                ChatHistoryItem(
                    id: "latest-app-server-assistant",
                    type: .assistant("当前回复"),
                    timestamp: Date(timeIntervalSince1970: 105)
                ),
            ]
        )

        let detail = MacIslandConversationDetailBuilder.make(from: session)
        XCTAssertEqual(detail.userText, "最新问题")
        XCTAssertEqual(detail.assistantText, "当前回复")
    }

    func testDetailDoesNotReusePreviousAssistantWhenLatestUserHasNoReply() throws {
        let session = SessionState(
            sessionId: "detail-unanswered-turn",
            cwd: "/tmp/mac-island",
            provider: .codex,
            clientInfo: .codexApp(threadId: "detail-unanswered-turn"),
            phase: .processing,
            chatItems: [
                ChatHistoryItem(
                    id: "old-rollout-assistant",
                    type: .assistant("上一轮回复"),
                    timestamp: Date(timeIntervalSince1970: 1_000)
                ),
                ChatHistoryItem(
                    id: "latest-rollout-user",
                    type: .user("尚未回复的新问题"),
                    timestamp: Date(timeIntervalSince1970: 1_100)
                ),
            ]
        )

        let detail = MacIslandConversationDetailBuilder.make(from: session)
        XCTAssertEqual(detail.userText, "尚未回复的新问题")
        XCTAssertNil(detail.assistantText)
    }

    func testActiveDetailUsesLatestToolAsCurrentActivity() throws {
        let start = Date(timeIntervalSince1970: 200)
        let session = SessionState(
            sessionId: "detail-tool",
            cwd: "/tmp/mac-island",
            provider: .codex,
            clientInfo: .codexApp(threadId: "detail-tool"),
            phase: .processing,
            chatItems: [
                ChatHistoryItem(id: "u1", type: .user("修复状态"), timestamp: start),
                ChatHistoryItem(
                    id: "tool-1",
                    type: .toolCall(
                        ToolCallItem(
                            name: "apply_patch",
                            input: ["path": "/tmp/mac-island/SessionListView.swift"],
                            status: .running,
                            result: nil,
                            structuredResult: nil,
                            subagentTools: []
                        )),
                    timestamp: start.addingTimeInterval(1)
                ),
            ]
        )

        let detail = MacIslandConversationDetailBuilder.make(from: session)
        XCTAssertEqual(detail.activity?.kind, .runningTool)
        XCTAssertEqual(detail.activity?.text, "Apply Patch · SessionListView.swift")
        XCTAssertNil(detail.assistantText)
    }

    func testActiveDetailPrefersLatestCommentaryOverOlderTool() throws {
        let start = Date(timeIntervalSince1970: 300)
        let session = SessionState(
            sessionId: "detail-thinking",
            cwd: "/tmp/mac-island",
            provider: .codex,
            clientInfo: .codexApp(threadId: "detail-thinking"),
            phase: .processing,
            chatItems: [
                ChatHistoryItem(id: "u1", type: .user("继续"), timestamp: start),
                ChatHistoryItem(
                    id: "tool-1",
                    type: .toolCall(
                        ToolCallItem(
                            name: "exec_command",
                            input: ["command": "swift test"],
                            status: .success,
                            result: nil,
                            structuredResult: nil,
                            subagentTools: []
                        )),
                    timestamp: start.addingTimeInterval(1)
                ),
                ChatHistoryItem(
                    id: "thinking-1",
                    type: .thinking("测试已经通过，正在重新启动应用。"),
                    timestamp: start.addingTimeInterval(2)
                ),
            ]
        )

        let detail = MacIslandConversationDetailBuilder.make(from: session)
        XCTAssertEqual(detail.activity?.kind, .thinking)
        XCTAssertEqual(detail.activity?.text, "测试已经通过，正在重新启动应用。")
    }

    func testCompletedCursorDetailKeepsRecentExecutionTimeline() throws {
        let start = Date(timeIntervalSince1970: 400)
        let session = SessionState(
            sessionId: "cursor-progress",
            cwd: "/tmp/project",
            modelName: "grok-4.5",
            provider: .claude,
            clientInfo: SessionClientInfo(
                kind: .custom,
                profileID: "cursor-local",
                name: "Cursor"
            ),
            phase: .idle,
            chatItems: [
                ChatHistoryItem(id: "u1", type: .user("继续审查"), timestamp: start),
                ChatHistoryItem(
                    id: "thinking",
                    type: .thinking("正在定位关键字段"),
                    timestamp: start.addingTimeInterval(1)
                ),
                ChatHistoryItem(
                    id: "tool",
                    type: .toolCall(
                        ToolCallItem(
                            name: "read_file_v2",
                            input: ["path": "/tmp/project/review.hql"],
                            status: .success,
                            result: "ok",
                            structuredResult: nil,
                            subagentTools: []
                        )),
                    timestamp: start.addingTimeInterval(2)
                ),
                ChatHistoryItem(
                    id: "assistant",
                    type: .assistant("已完成字段核对。"),
                    timestamp: start.addingTimeInterval(3)
                ),
            ]
        )

        let detail = MacIslandConversationDetailBuilder.make(from: session)
        XCTAssertEqual(detail.activities.count, 2)
        XCTAssertEqual(detail.activities.first?.kind, .thinking)
        XCTAssertEqual(detail.activity?.kind, .completedTool)
        XCTAssertEqual(detail.assistantText, "已完成字段核对。")
    }
}
