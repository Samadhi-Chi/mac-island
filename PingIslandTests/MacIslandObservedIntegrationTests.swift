import Darwin
import XCTest

@testable import Ping_Island

final class MacIslandObservedIntegrationTests: XCTestCase {
    func testSocketReaderConsumesBytesWhenPeerHalfClosesWriteSide() {
        XCTAssertTrue(HookSocketServer.shouldAttemptSocketRead(revents: Int16(POLLIN)))
        XCTAssertTrue(HookSocketServer.shouldAttemptSocketRead(revents: Int16(POLLHUP)))
        XCTAssertTrue(
            HookSocketServer.shouldAttemptSocketRead(
                revents: Int16(POLLIN) | Int16(POLLHUP)
            ))
        XCTAssertFalse(HookSocketServer.shouldAttemptSocketRead(revents: 0))
    }

    func testNativeSessionIdentityIsNamespacedByClientAndOrigin() {
        let nativeID = "shared-session-id"
        let claudeCLI = MacIslandProductPolicy.observedSessionKey(
            nativeSessionID: nativeID,
            clientInfo: claudeClient
        )
        var claudeDesktopClient = claudeClient
        claudeDesktopClient.profileID = "claude-desktop-code"
        claudeDesktopClient.origin = "desktop"
        let claudeDesktop = MacIslandProductPolicy.observedSessionKey(
            nativeSessionID: nativeID,
            clientInfo: claudeDesktopClient
        )
        let openCode = MacIslandProductPolicy.observedSessionKey(
            nativeSessionID: nativeID,
            clientInfo: openCodeClient
        )

        XCTAssertEqual(Set([claudeCLI, claudeDesktop, openCode]).count, 3)
        XCTAssertTrue(claudeCLI.hasSuffix(nativeID))
    }

    func testProductProjectionKeepsBoundedDisplayFieldsAndDropsControlData() {
        let event = makeEvent(
            sessionID: "claude-projection",
            event: "UserPromptSubmit",
            status: "processing",
            clientInfo: claudeClient,
            tool: "Bash",
            toolInput: ["command": AnyCodable("print secret")],
            message: "请检查本地构建",
            nativeTitle: "Release verification",
            providerName: "Anthropic",
            model: "claude-opus-4-1"
        )

        let safe = SessionMonitor.productSafeHookEvent(event)

        XCTAssertEqual(safe.message, "请检查本地构建")
        XCTAssertEqual(safe.nativeTitle, "Release verification")
        XCTAssertEqual(safe.serviceProvider, "Anthropic")
        XCTAssertEqual(safe.modelName, "claude-opus-4-1")
        XCTAssertNil(safe.toolInput)
        XCTAssertNil(safe.bridgeIntervention)
        XCTAssertFalse(safe.expectsResponse)
        XCTAssertTrue(safe.suppressInAppPrompt)
    }

    func testClaudeTurnProjectsQuestionReplyAndFiveRecentActivitiesInMemory() async throws {
        let store = SessionStore.shared
        let sessionID = "claude-observed-\(UUID().uuidString)"
        defer { Task { await store.process(.sessionArchived(sessionId: sessionID)) } }

        await store.process(
            .hookReceived(
                SessionMonitor.productSafeHookEvent(
                    makeEvent(
                        sessionID: sessionID,
                        event: "UserPromptSubmit",
                        status: "processing",
                        clientInfo: claudeClient,
                        message: "帮我检查构建",
                        nativeTitle: "Build check",
                        providerName: "Anthropic",
                        model: "claude-sonnet-4-5"
                    ))))

        for index in 0..<6 {
            let toolID = "tool-\(index)"
            await store.process(
                .hookReceived(
                    SessionMonitor.productSafeHookEvent(
                        makeEvent(
                            sessionID: sessionID,
                            event: "PreToolUse",
                            status: "running_tool",
                            clientInfo: claudeClient,
                            tool: "Read",
                            toolUseID: toolID
                        ))))
            await store.process(
                .hookReceived(
                    SessionMonitor.productSafeHookEvent(
                        makeEvent(
                            sessionID: sessionID,
                            event: "PostToolUse",
                            status: "processing",
                            clientInfo: claudeClient,
                            tool: "Read",
                            toolUseID: toolID
                        ))))
        }

        await store.process(
            .hookReceived(
                SessionMonitor.productSafeHookEvent(
                    makeEvent(
                        sessionID: sessionID,
                        event: "Stop",
                        status: "waiting_for_input",
                        clientInfo: claudeClient,
                        message: "构建通过，共检查六个文件。"
                    ))))

        let storedSession = await store.session(for: sessionID)
        let session = try XCTUnwrap(storedSession)
        let detail = MacIslandConversationDetailBuilder.make(from: session)
        XCTAssertEqual(session.sessionName, "Build check")
        XCTAssertEqual(session.serviceProviderName, "Anthropic")
        XCTAssertEqual(session.modelName, "claude-sonnet-4-5")
        XCTAssertEqual(detail.userText, "帮我检查构建")
        XCTAssertEqual(detail.assistantText, "构建通过，共检查六个文件。")
        XCTAssertEqual(detail.activities.count, 5)
        XCTAssertTrue(detail.activities.allSatisfy { $0.kind == .completedTool })
    }

    func testPermissionAndSubagentEventsStayObserverOnlyAndMergeIntoParent() async throws {
        let store = SessionStore.shared
        let sessionID = "hermes-observed-\(UUID().uuidString)"
        let client = hermesClient(origin: "desktop")
        defer { Task { await store.process(.sessionArchived(sessionId: sessionID)) } }

        await store.process(
            .hookReceived(
                SessionMonitor.productSafeHookEvent(
                    makeEvent(
                        sessionID: sessionID,
                        event: "SubagentStart",
                        status: "processing",
                        clientInfo: client,
                        tool: "Researcher",
                        toolUseID: "child-1",
                        message: "Researcher"
                    ))))
        await store.process(
            .hookReceived(
                SessionMonitor.productSafeHookEvent(
                    makeEvent(
                        sessionID: sessionID,
                        event: "PermissionRequest",
                        status: "waiting_for_approval",
                        clientInfo: client,
                        tool: "Approval",
                        toolInput: ["credential": AnyCodable("must disappear")],
                        toolUseID: "approval-1",
                        message: "需要终端确认"
                    ))))

        let storedSession = await store.session(for: sessionID)
        let session = try XCTUnwrap(storedSession)
        let detail = MacIslandConversationDetailBuilder.make(from: session)
        guard case .waitingForApproval(let permission) = session.phase else {
            return XCTFail("Expected needs-attention state")
        }
        XCTAssertNil(permission.toolInput)
        XCTAssertTrue(session.suppressInAppPromptControls)
        XCTAssertTrue(detail.activities.contains { $0.text.localizedCaseInsensitiveContains("Researcher") })
        let allSessions = await store.allSessions()
        let matchingSessions = allSessions.filter { $0.sessionId == sessionID }
        XCTAssertEqual(matchingSessions.count, 1)
    }

    func testUnknownQuotaNeverCreatesSyntheticUsage() {
        let session = SessionState(
            sessionId: "opencode-no-quota",
            cwd: "/tmp/project",
            modelName: "qwen3-coder",
            serviceProviderName: "OpenRouter",
            provider: .claude,
            clientInfo: openCodeClient
        )

        XCTAssertEqual(session.serviceProviderName, "OpenRouter")
        XCTAssertEqual(session.modelName, "qwen3-coder")
        XCTAssertTrue(UsageSummaryPresenter.providersFollowingActiveClient([], sessions: [session]).isEmpty)
    }

    private var claudeClient: SessionClientInfo {
        SessionClientInfo(
            kind: .claudeCode,
            profileID: "claude-code",
            name: "Claude Code",
            origin: "cli",
            originator: "Claude Code",
            threadSource: "claude-hooks"
        )
    }

    private var openCodeClient: SessionClientInfo {
        SessionClientInfo(
            kind: .custom,
            profileID: "opencode",
            name: "OpenCode",
            origin: "cli",
            originator: "OpenCode",
            threadSource: "opencode-plugin"
        )
    }

    private func hermesClient(origin: String) -> SessionClientInfo {
        SessionClientInfo(
            kind: .custom,
            profileID: "hermes",
            name: "Hermes",
            origin: origin,
            originator: "Hermes",
            threadSource: "hermes-plugin"
        )
    }

    private func makeEvent(
        sessionID: String,
        event: String,
        status: String,
        clientInfo: SessionClientInfo,
        tool: String? = nil,
        toolInput: [String: AnyCodable]? = nil,
        toolUseID: String? = nil,
        message: String? = nil,
        nativeTitle: String? = nil,
        providerName: String? = nil,
        model: String? = nil
    ) -> HookEvent {
        HookEvent(
            sessionId: sessionID,
            cwd: "/tmp/project",
            event: event,
            status: status,
            provider: .claude,
            clientInfo: clientInfo,
            pid: nil,
            tty: nil,
            tool: tool,
            toolInput: toolInput,
            toolUseId: toolUseID,
            notificationType: event == "Stop" ? "assistant_message" : nil,
            message: message,
            nativeTitle: nativeTitle,
            serviceProvider: providerName,
            modelName: model,
            bridgeExpectsResponse: event == "PermissionRequest",
            suppressInAppPrompt: true
        )
    }
}
