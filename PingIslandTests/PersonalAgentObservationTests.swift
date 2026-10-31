import XCTest

@testable import Ping_Island

final class PersonalAgentObservationTests: XCTestCase {
    func testGrokBotKeepsAgentNameSeparateFromMissingTaskIdentityAndTitle() throws {
        let row = try XCTUnwrap(rows(.grokBot, [PersonalAgentSyntheticUI.grok]).first)
        XCTAssertEqual(row.agentName, "Example Bot")
        XCTAssertNil(row.nativeTaskTitle)
        XCTAssertNil(row.nativeTaskID)
        XCTAssertNil(row.lastActivity)
        XCTAssertFalse(row.countsAsRunning)
        XCTAssertFalse(row.canNavigateToTask)
        XCTAssertEqual(row.scope, .visibleConversation)
    }

    func testConversationContentsAndInputsCannotBecomeTitlesOrTasks() {
        let privateNode = PersonalAgentAXNode(
            role: "AXGroup", label: "Conversation transcript", children: [PersonalAgentSyntheticUI.grok])
        let input = PersonalAgentAXNode(role: "AXTextArea", label: "Prompt", children: [PersonalAgentSyntheticUI.grok])
        XCTAssertTrue(rows(.grokBot, [privateNode, input]).isEmpty)
        let chats = PersonalAgentAXNode(
            role: "AXGroup", label: "Chat messages", children: [PersonalAgentSyntheticUI.muse])
        XCTAssertTrue(rows(.muse, [chats]).isEmpty)
    }

    func testBotListIsNotTheCurrentConversation() {
        let list = PersonalAgentAXNode(role: "AXList", label: "Bot list", children: [PersonalAgentSyntheticUI.grok])
        XCTAssertTrue(rows(.grokBot, [list]).isEmpty)
    }

    func testNativeActivityLabelIsPreservedWithoutGuessingStatusOrTimestamp() throws {
        let label = "Research a failed build example Successful analysis 10:12 am"
        let result = rows(.muse, [PersonalAgentSyntheticUI.muse(labels: [label])])
        let row = try XCTUnwrap(result.first)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(row.agentName, "Example Muse")
        XCTAssertEqual(row.nativeActivityLabels, [label])
        XCTAssertNil(row.nativeTaskTitle)
        XCTAssertNil(row.lastActivity)
        XCTAssertNil(row.nativeTaskID)
        XCTAssertEqual(row.statusLocalizationKey, "personal-agent.status.unknown")
        XCTAssertFalse(row.countsAsRunning)
    }

    func testRepeatedActivitiesStayInsideOneBotAndIDsAreSnapshotOnly() {
        let label = "Example task Example result 10:12 am"
        let window = PersonalAgentSyntheticUI.muse(labels: [label, label])
        let result = rows(.muse, [window])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.nativeActivityLabels, [label, label])
        XCTAssertTrue(result.allSatisfy { $0.nativeTaskID == nil })
        let next = PersonalAgentAdapter.observations(
            client: .muse, version: "4.1", windows: [window], observedAt: .distantPast, epoch: 2)
        XCTAssertTrue(Set(result.map(\.id)).isDisjoint(with: Set(next.map(\.id))))
    }

    func testApprovalOrActivityEntryAloneIsNotPendingWork() {
        let result = rows(.muse, [PersonalAgentSyntheticUI.muse(selected: false)])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.agentName, "Example Muse")
        XCTAssertEqual(result.first?.nativeActivityLabels, [])
        XCTAssertEqual(result.first?.scope, .visibleConversation)
        let onlyEntry = PersonalAgentAXNode(
            role: "AXGroup",
            children: [
                .init(role: "AXCheckBox", label: "Activity", selected: true),
                .init(role: "AXButton", label: "Example task Example result 10:12 am"),
            ])
        XCTAssertTrue(rows(.muse, [onlyEntry]).isEmpty)
    }

    func testMuseRejectsUnrecognizedActivityLayoutAndNonActivityControls() {
        let window = PersonalAgentSyntheticUI.muse(
            labels: ["Search", "Message", "Task without native time"], name: nil)
        XCTAssertTrue(rows(.muse, [window]).isEmpty)
    }

    func testSevenActivitiesProduceOneBotCardInSourceOrder() throws {
        let labels = (1...7).map { "Example activity \($0) Native result 10:12 am" }
        let result = rows(.muse, [PersonalAgentSyntheticUI.muse(labels: labels)])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(try XCTUnwrap(result.first).nativeActivityLabels, labels)
    }

    func testSameNamedBotsInSeparateWindowsOrPanelsAreNotMerged() {
        let bot = PersonalAgentSyntheticUI.muse
        XCTAssertEqual(rows(.muse, [bot, bot]).count, 2)
        let multiPanel = PersonalAgentAXNode(role: "AXWindow", children: [bot, bot])
        let result = rows(.muse, [multiPanel])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.id)).count, 2)
        XCTAssertEqual(rows(.grokBot, [PersonalAgentSyntheticUI.grok, PersonalAgentSyntheticUI.grok]).count, 2)
    }

    func testNamedBotRemainsOneCardWhenNoActivitiesAreVisible() {
        let result = rows(.muse, [PersonalAgentSyntheticUI.muse(labels: [])])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.agentName, "Example Muse")
        XCTAssertEqual(result.first?.nativeActivityLabels, [])
        XCTAssertFalse(result.first?.countsAsRunning ?? true)
    }

    func testMissingNameDoesNotBorrowActivityOrUnrelatedStaticText() {
        var bot = PersonalAgentSyntheticUI.muse(name: nil)
        bot.children.append(.init(role: "AXStaticText", label: "Unrelated name Connected"))
        let result = rows(.muse, [bot])
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result.first?.agentName)
        XCTAssertEqual(result.first?.nativeActivityLabels.count, 1)
    }

    func testMuseIdentityRequiresExactAdjacentHeaderAndOnlyStripsConnectionBadge() {
        let original = PersonalAgentSyntheticUI.muse(name: "Example Connected")
        XCTAssertEqual(rows(.muse, [original]).first?.agentName, "Example Connected")
        var missingAvatar = original
        missingAvatar.children[0].label = "Unverified avatar"
        XCTAssertNil(rows(.muse, [missingAvatar]).first?.agentName)
        var unknownBadge = original
        unknownBadge.children[2].label = "Example Connected Unverified"
        XCTAssertNil(rows(.muse, [unknownBadge]).first?.agentName)
        var projected: [PersonalAgentAXNode?] = original.children.map { Optional($0) }
        projected[2] = nil
        XCTAssertEqual(PersonalAgentAdapter.museIdentityTextRange(in: projected), 2..<3)
        projected[1] = .init(role: "AXGroup", label: "Edit avatar and name")
        XCTAssertNil(PersonalAgentAdapter.museIdentityTextRange(in: projected))
    }

    func testMuseSeparateNameAndBadgeLeavesRemainOneNativeBotName() {
        var bot = PersonalAgentSyntheticUI.muse(name: "Example Connected")
        bot.children[1] = .init(role: "AXButton", label: "Edit avatar and name")
        bot.children[2].label = "Example Connected"
        bot.children.insert(.init(role: "AXStaticText", label: "Connected"), at: 3)
        let result = rows(.muse, [bot])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.agentName, "Example Connected")
        XCTAssertEqual(result.first?.nativeActivityLabels.count, 1)
        var projected = bot.children.map { Optional($0) }
        projected[2] = nil
        projected[3] = nil
        XCTAssertEqual(PersonalAgentAdapter.museIdentityTextRange(in: projected), 2..<4)
    }

    func testMuseIdentityRejectsUnknownBadgeAndExtraTextBeforeTabs() {
        var bot = PersonalAgentSyntheticUI.muse()
        bot.children[2].label = "Example Muse"
        bot.children.insert(.init(role: "AXStaticText", label: "Unverified"), at: 3)
        XCTAssertNil(rows(.muse, [bot]).first?.agentName)
        bot.children[3].label = "Connected"
        bot.children.insert(.init(role: "AXStaticText", label: "Unrelated text"), at: 4)
        XCTAssertNil(PersonalAgentAdapter.museIdentityTextRange(in: bot.children.map { Optional($0) }))
    }

    func testMuseNativeWrappedHeaderKeepsOneBotAcrossActivityTabs() {
        let label = "Example task Native result 10:12 am"
        var bot = PersonalAgentSyntheticUI.muse(labels: [label, label])
        bot.children[1] = .init(role: "AXGroup", children: [bot.children[1]])
        bot.children[2] = .init(
            role: "AXGroup",
            children: [
                .init(role: "AXStaticText", label: "Example Connected"),
                .init(role: "AXStaticText", label: "Connected"),
            ])
        let active = rows(.muse, [bot])
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.agentName, "Example Connected")
        XCTAssertEqual(active.first?.nativeActivityLabels, [label, label])
        var unread = bot.children.map { Optional($0) }
        unread[2] = .init(role: "AXGroup")
        XCTAssertEqual(PersonalAgentAdapter.museIdentityTextRange(in: unread), 2..<3)

        bot.children[3].selected = false
        bot.children[4].selected = true
        let otherTab = rows(.muse, [bot])
        XCTAssertEqual(otherTab.count, 1)
        XCTAssertEqual(otherTab.first?.agentName, "Example Connected")
        XCTAssertEqual(otherTab.first?.nativeActivityLabels, [])
        XCTAssertEqual(otherTab.first?.scope, .visibleConversation)
    }

    func testMuseWrappedIdentityRejectsInputsPrivateGroupsAndDeeperText() {
        var bot = PersonalAgentSyntheticUI.muse()
        bot.children[1] = .init(role: "AXGroup", children: [bot.children[1]])
        let name = PersonalAgentAXNode(role: "AXStaticText", label: "Example Muse")
        let badge = PersonalAgentAXNode(role: "AXStaticText", label: "Connected")
        let unverified: [PersonalAgentAXNode] = [
            .init(role: "AXGroup", children: [name, badge, name]),
            .init(role: "AXGroup", children: [.init(role: "AXTextField", label: "Example Muse"), badge]),
            .init(role: "AXGroup", children: [.init(role: "AXGroup", children: [name, badge])]),
            .init(role: "AXGroup", label: "Conversation transcript", children: [name, badge]),
            .init(role: "AXGroup", children: [name, .init(role: "AXStaticText", label: "Unknown")]),
        ]
        for group in unverified {
            bot.children[2] = group
            let result = rows(.muse, [bot])
            XCTAssertEqual(result.count, 1)
            XCTAssertNil(result.first?.agentName)
            XCTAssertEqual(result.first?.nativeActivityLabels.count, 1)
        }
        bot.children[2] = .init(role: "AXGroup", children: [name, badge])
        bot.children[1].children.append(.init(role: "AXButton", label: "Unrelated control"))
        XCTAssertNil(rows(.muse, [bot]).first?.agentName)
    }

    func testDotNeverClaimsOrdinaryCodexOrOtherClientsAsDotWork() {
        XCTAssertFalse(PersonalAgentClient.dot.canObserve)
        XCTAssertTrue(rows(.dot, [PersonalAgentSyntheticUI.grok, PersonalAgentSyntheticUI.muse]).isEmpty)
    }

    func testMuse60MirroredAvatarsAreOneBotWithoutReadingChatsOrActivities() throws {
        let result = muse60Rows([PersonalAgentSyntheticUI.muse60])
        XCTAssertEqual(result.count, 1)
        let row = try XCTUnwrap(result.first)
        XCTAssertEqual(row.agentName, "Example Muse")
        XCTAssertTrue(row.nativeActivityLabels.isEmpty)
        XCTAssertNil(row.nativeTaskTitle)
        XCTAssertNil(row.nativeTaskID)
        XCTAssertFalse(row.countsAsRunning)
        XCTAssertFalse(row.canNavigateToTask)
        XCTAssertEqual(row.scope, .visibleConversation)
    }

    func testMuse60RejectsUnknownVersionOrTheOtherMuseContract() {
        XCTAssertTrue(muse60Rows([PersonalAgentSyntheticUI.muse60], version: "6.1").isEmpty)
        XCTAssertTrue(muse60Rows([PersonalAgentSyntheticUI.muse60], version: "4.1").isEmpty)
        XCTAssertTrue(muse60Rows([PersonalAgentSyntheticUI.muse], version: "6.0").isEmpty)
    }

    func testMuse60RequiresNavigationAndAdjacentMatchingLeafAvatarControls() {
        let original = PersonalAgentSyntheticUI.muse60
        var candidates: [PersonalAgentAXNode] = []
        var missingRail = original
        missingRail.children[0].children.removeLast()
        candidates.append(missingRail)
        var wrongLink = original
        wrongLink.children[0].children[0].label = "Open conversation"
        candidates.append(wrongLink)
        var mismatch = original
        mismatch.children[3].label = "Other Bot"
        candidates.append(mismatch)
        var missingMirror = original
        missingMirror.children.removeLast()
        candidates.append(missingMirror)
        var nestedText = original
        nestedText.children[2].children = [.init(role: "AXStaticText", label: "Unverified text")]
        candidates.append(nestedText)
        var inputComposer = original
        inputComposer.children[1].children = [.init(role: "AXTextArea", label: "Prompt")]
        candidates.append(inputComposer)
        var separate = original
        separate.children.insert(.init(role: "AXGroup"), at: 3)
        candidates.append(separate)
        for candidate in candidates { XCTAssertTrue(muse60Rows([candidate]).isEmpty) }
        let privateChat = PersonalAgentAXNode(role: "AXGroup", label: "Chat messages", children: [original])
        let privateInput = PersonalAgentAXNode(role: "AXTextField", children: [original])
        XCTAssertTrue(muse60Rows([privateChat, privateInput]).isEmpty)
    }

    func testMuse60NotificationBadgeAndApprovalDecorationNeverBecomeExecutionState() {
        var context = PersonalAgentSyntheticUI.muse60
        context.children[0].children[0].label = "Chat, 2 notifications"
        context.children[2].label = "Example Muse, needs approval"
        context.children[3].label = context.children[2].label
        let result = muse60Rows([context])
        XCTAssertEqual(result.first?.agentName, "Example Muse")
        XCTAssertEqual(result.first?.statusLocalizationKey, "personal-agent.status.unknown")
        XCTAssertEqual(result.first?.countsAsRunning, false)
        context.children[2].label = "Agent avatar"
        context.children[3].label = "Agent avatar"
        let nameless = muse60Rows([context])
        XCTAssertEqual(nameless.count, 1)
        XCTAssertNil(nameless.first?.agentName)
    }

    func testMuse60SameNameWindowsRemainDistinctSnapshotContexts() {
        let result = muse60Rows([PersonalAgentSyntheticUI.muse60, PersonalAgentSyntheticUI.muse60])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.id)).count, 2)
    }

    private func muse60Rows(_ windows: [PersonalAgentAXNode], version: String = "6.0") -> [PersonalAgentObservation] {
        PersonalAgentAdapter.observations(
            client: .muse, version: version, windows: windows, observedAt: .distantPast, epoch: 1)
    }

    func testMultipleWindowsAndRenamedAgentsKeepDistinctObservations() {
        var second = PersonalAgentSyntheticUI.grok
        second.children[0].children[0].label = "Renamed Bot"
        let result = rows(.grokBot, [PersonalAgentSyntheticUI.grok, second])
        XCTAssertEqual(result.map(\.agentName), ["Example Bot", "Renamed Bot"])
        XCTAssertEqual(Set(result.map(\.id)).count, 2)
    }

    func testNativeReaderRejectsHostedTestsBeforeReadingAnyRealApplication() async {
        let result = await PersonalAgentAccessibilityReader().read(
            .init(
                client: .muse, processID: 999_999, bundleID: PersonalAgentClient.muse.bundleID, version: "4.1"
            ))
        switch result.outcome {
        case .failed: break
        default: XCTFail("Hosted tests must not perform live AX reads")
        }
        XCTAssertTrue(result.windows.isEmpty)
    }

    func testBothIslandSurfacesShowInterfaceObservationsWithoutChangingAttentionPriority() {
        for surface in [IslandExpandedSurface.docked, .floating] {
            XCTAssertEqual(
                IslandExpandedRouteResolver.resolve(
                    surface: surface, trigger: .hover,
                    contentType: .instances, sessions: [], hasPersonalAgentObservations: true), .sessionList)
            var pending = SessionState(sessionId: "synthetic-attention", cwd: "/example/project")
            pending.phase = .waitingForInput
            pending.intervention = .init(
                id: "synthetic-question", kind: .question, title: "Choose an option",
                message: "Choose an option", options: [], questions: [], supportsSessionScope: false, metadata: [:])
            XCTAssertEqual(
                IslandExpandedRouteResolver.resolve(
                    surface: surface, trigger: .hover,
                    contentType: .instances, sessions: [pending], hasPersonalAgentObservations: true),
                .attentionNotification(pending))
        }
    }

    private func rows(_ client: PersonalAgentClient, _ windows: [PersonalAgentAXNode]) -> [PersonalAgentObservation] {
        PersonalAgentAdapter.observations(
            client: client, version: client == .muse ? "4.1" : "0.68.1",
            windows: windows, observedAt: .distantPast, epoch: 1)
    }
}

nonisolated enum PersonalAgentSyntheticUI {
    static var muse60: PersonalAgentAXNode {
        .init(
            role: "AXGroup",
            children: [
                .init(
                    role: "AXGroup",
                    children: [
                        .init(role: "AXLink", label: "Chat"),
                        .init(role: "AXButton", label: "Search"),
                        .init(
                            role: "AXGroup", label: "Side chats",
                            children: [
                                .init(role: "AXButton", label: "Example side-chat title")
                            ]),
                        .init(role: "AXPopUpButton", label: "Settings"),
                    ]),
                .init(role: "AXButton", label: PersonalAgentAdapter.muse60ComposerLabel),
                .init(role: "AXButton", label: "Example Muse"),
                .init(role: "AXButton", label: "Example Muse"),
            ])
    }
    static var grok: PersonalAgentAXNode {
        .init(
            role: "AXWindow",
            children: [
                .init(
                    role: "AXButton", label: "View conversation details",
                    children: [
                        .init(role: "AXStaticText", label: "Example Bot")
                    ])
            ])
    }
    static var muse: PersonalAgentAXNode { muse(labels: ["Example research Finished summary 10:12 am"]) }
    static func muse(
        labels: [String] = ["Example research Finished summary 10:12 am"], selected: Bool = true,
        name: String? = "Example Muse"
    ) -> PersonalAgentAXNode {
        .init(
            role: "AXWindow",
            children: [
                .init(role: "AXImage", label: "Muse avatar"),
                .init(role: "AXPopUpButton", label: "Edit avatar and name"),
                .init(role: "AXStaticText", label: name.map { "\($0) Connected" } ?? ""),
                .init(role: "AXCheckBox", label: "Activity", selected: selected),
                .init(role: "AXCheckBox", label: "Approvals"),
                .init(role: "AXCheckBox", label: "Upcoming"),
                .init(role: "AXCheckBox", label: "Identity", selected: !selected),
                .init(role: "AXHeading", label: "Today"),
            ] + labels.map { .init(role: "AXButton", label: $0) })
    }
}
