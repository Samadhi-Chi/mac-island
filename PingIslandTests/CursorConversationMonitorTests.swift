import XCTest

@testable import Ping_Island

final class CursorConversationMonitorTests: XCTestCase {
    func testLiveCursorDatabaseReaderForLocalDevelopment() async throws {
        guard ProcessInfo.processInfo.environment["MAC_ISLAND_LIVE_CURSOR_TEST"] == "1" else {
            throw XCTSkip("Local Cursor database validation is opt-in")
        }
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User", isDirectory: true)
        let snapshots = await CursorConversationMonitor(userDataRoot: root).readRecentSnapshots()
        XCTAssertFalse(snapshots.isEmpty)
        XCTAssertTrue(snapshots.allSatisfy { !$0.threadName.isEmpty && $0.cwd != "/" })
        XCTAssertTrue(
            snapshots.contains { snapshot in
                snapshot.historyItems.contains { item in
                    switch item.type {
                    case .thinking, .toolCall:
                        true
                    case .user, .assistant, .interrupted:
                        false
                    }
                }
            })
    }

    func testParsesProjectThreadModelAndLocalConversationDetails() throws {
        let header = """
            {
              "composerId": "cursor-thread-1",
              "name": "mac_island",
              "createdAt": 1785060000000,
              "lastUpdatedAt": 1785060060000,
              "workspaceIdentifier": {
                "uri": { "fsPath": "/Users/Shared/Dev" }
              }
            }
            """
        let composer = """
            {
              "status": "completed",
              "modelConfig": { "modelName": "claude-sonnet-4-6" },
              "fullConversationHeadersOnly": [
                {
                  "bubbleId": "user-1",
                  "type": 1,
                  "createdAt": "2026-07-26T10:00:00Z",
                  "grouping": { "textPreview": "修复 Cursor 会话抓取" }
                },
                {
                  "bubbleId": "assistant-1",
                  "type": 2,
                  "createdAt": "2026-07-26T10:00:02Z",
                  "grouping": { "textPreview": "已经完成只读适配。" }
                }
              ]
            }
            """

        let snapshot = try XCTUnwrap(
            CursorConversationParser.parse(
                composerId: "cursor-thread-1",
                workspaceId: "workspace-1",
                createdAtMilliseconds: 0,
                updatedAtMilliseconds: 0,
                headerJSON: header,
                composerJSON: composer,
                fallbackWorkspacePath: nil
            ))

        XCTAssertEqual(snapshot.cwd, "/Users/Shared/Dev")
        XCTAssertEqual(snapshot.threadName, "mac_island")
        XCTAssertEqual(snapshot.modelName, "claude-sonnet-4-6")
        XCTAssertEqual(snapshot.phase, .idle)
        XCTAssertEqual(snapshot.conversationInfo.firstUserMessage, "修复 Cursor 会话抓取")
        XCTAssertEqual(snapshot.conversationInfo.lastMessage, "已经完成只读适配。")
        XCTAssertEqual(snapshot.conversationInfo.lastMessageRole, "assistant")
        XCTAssertEqual(snapshot.historyItems.count, 2)
    }

    func testGeneratingConversationIsWorkingAndDraftIsIgnored() throws {
        let header = """
            {"name":"active-thread","workspaceIdentifier":{"uri":{"fsPath":"/tmp/dev"}}}
            """
        let active = """
            {"status":"none","generatingBubbleIds":["assistant-1"]}
            """
        let draft = """
            {"isDraft":true,"status":"none"}
            """

        XCTAssertEqual(
            CursorConversationParser.parse(
                composerId: "active",
                workspaceId: nil,
                createdAtMilliseconds: 1,
                updatedAtMilliseconds: 2,
                headerJSON: header,
                composerJSON: active,
                fallbackWorkspacePath: nil
            )?.phase,
            .processing
        )
        XCTAssertNil(
            CursorConversationParser.parse(
                composerId: "draft",
                workspaceId: nil,
                createdAtMilliseconds: 1,
                updatedAtMilliseconds: 2,
                headerJSON: header,
                composerJSON: draft,
                fallbackWorkspacePath: nil
            ))
    }

    func testCurrentGenerationOverridesStaleCompletedStatus() throws {
        let header = """
            {"name":"active-thread","workspaceIdentifier":{"uri":{"fsPath":"/tmp/dev"}}}
            """
        let active = """
            {
              "status":"completed",
              "chatGenerationUUID":"current-generation",
              "latestChatGenerationUUID":"previous-generation"
            }
            """
        let completed = """
            {
              "status":"completed",
              "latestChatGenerationUUID":"current-generation"
            }
            """

        XCTAssertEqual(
            CursorConversationParser.parse(
                composerId: "active",
                workspaceId: nil,
                createdAtMilliseconds: 1,
                updatedAtMilliseconds: 2,
                headerJSON: header,
                composerJSON: active,
                fallbackWorkspacePath: nil
            )?.phase,
            .processing
        )
        XCTAssertEqual(
            CursorConversationParser.parse(
                composerId: "completed",
                workspaceId: nil,
                createdAtMilliseconds: 1,
                updatedAtMilliseconds: 2,
                headerJSON: header,
                composerJSON: completed,
                fallbackWorkspacePath: nil
            )?.phase,
            .idle
        )
    }

    func testParsesFullCursorBubbleStreamWithThinkingAndTools() throws {
        let header = """
            {
              "name": "review",
              "workspaceIdentifier": { "uri": { "fsPath": "/tmp/dev" } }
            }
            """
        let composer = """
            {
              "status": "completed",
              "modelConfig": { "modelName": "grok-4.5" },
              "fullConversationHeadersOnly": [
                {"bubbleId":"user-1","type":1,"createdAt":"2026-07-28T03:00:00Z","grouping":{}},
                {"bubbleId":"think-1","type":2,"createdAt":"2026-07-28T03:00:01Z","grouping":{}},
                {"bubbleId":"tool-1","type":2,"createdAt":"2026-07-28T03:00:02Z","grouping":{}},
                {"bubbleId":"assistant-1","type":2,"createdAt":"2026-07-28T03:00:03Z","grouping":{}}
              ]
            }
            """
        let bubbles = [
            "user-1": """
            {"type":1,"createdAt":"2026-07-28T03:00:00Z","text":"审查需求"}
            """,
            "think-1": """
            {"type":2,"createdAt":"2026-07-28T03:00:01Z","text":"","thinking":{"text":"正在定位关键字段","signature":"local"}}
            """,
            "tool-1": #"""
            {"type":2,"createdAt":"2026-07-28T03:00:02Z","text":"","toolFormerData":{"name":"read_file_v2","status":"completed","params":"{\"targetFile\":\"/tmp/dev/review.hql\"}","result":"ok"}}
            """#,
            "assistant-1": """
            {"type":2,"createdAt":"2026-07-28T03:00:03Z","text":"已完成字段核对。"}
            """,
        ]

        let snapshot = try XCTUnwrap(
            CursorConversationParser.parse(
                composerId: "cursor-rich",
                workspaceId: nil,
                createdAtMilliseconds: 0,
                updatedAtMilliseconds: 0,
                headerJSON: header,
                composerJSON: composer,
                fallbackWorkspacePath: nil,
                bubbleJSONByID: bubbles
            ))

        XCTAssertEqual(snapshot.modelName, "grok-4.5")
        XCTAssertEqual(snapshot.historyItems.count, 4)
        XCTAssertEqual(snapshot.conversationInfo.lastMessage, "已完成字段核对。")
        XCTAssertEqual(snapshot.conversationInfo.lastToolName, "read_file_v2")
        guard case .thinking(let thinking) = snapshot.historyItems[1].type else {
            return XCTFail("Expected Cursor thinking bubble")
        }
        XCTAssertEqual(thinking, "正在定位关键字段")
        guard case .toolCall(let tool) = snapshot.historyItems[2].type else {
            return XCTFail("Expected Cursor tool bubble")
        }
        XCTAssertEqual(tool.status, .success)
        XCTAssertEqual(tool.input["path"], "/tmp/dev/review.hql")
    }

    func testAbortedComposerDoesNotMarkLingeringToolAsCompleted() throws {
        let header = #"{"name":"review","workspaceIdentifier":{"uri":{"fsPath":"/tmp/dev"}}}"#
        let composer =
            #"{"status":"aborted","fullConversationHeadersOnly":[{"bubbleId":"tool-1","type":2,"grouping":{}}]}"#
        let bubbles = [
            "tool-1":
                #"{"type":2,"toolFormerData":{"name":"run_terminal_command_v2","status":"loading","params":"{\"command\":\"swift test\"}"}}"#
        ]

        let snapshot = try XCTUnwrap(
            CursorConversationParser.parse(
                composerId: "cursor-aborted",
                workspaceId: nil,
                createdAtMilliseconds: 0,
                updatedAtMilliseconds: 0,
                headerJSON: header,
                composerJSON: composer,
                fallbackWorkspacePath: nil,
                bubbleJSONByID: bubbles
            ))

        guard case .toolCall(let tool) = try XCTUnwrap(snapshot.historyItems.first).type else {
            return XCTFail("Expected Cursor tool bubble")
        }
        XCTAssertEqual(tool.status, .interrupted)
    }
}
