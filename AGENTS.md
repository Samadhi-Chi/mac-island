# AGENTS.md

This file is a routing layer for coding agents working in this repo. Keep it short. Put long-lived detail in nearby code, focused docs, or tests.

## Mission

- This fork ships the local `Mac Island` app. Product policy lives in
  `PingIsland/Core/MacIslandProductPolicy.swift`: the supported surface is
  Codex, Cursor, Claude Code (CLI and Desktop Code), OpenCode, Hermes, and
  DeepSeek Harness (DSH CLI and local Web UI);
  it is monitor-only, local-only, silent, and does not start telemetry or
  update services. Keep those constraints intact during upstream merges.
- The retained upstream `PingIsland` code supports additional clients and writable
  flows; those are not the Mac Island product contract. Its old README is archived
  at `docs/history/upstream-readme.md`.
- The main runtime path is:
  - hook or app-server events
  - monitoring and service layers
  - `SessionStore`
  - `SessionMonitor` and `NotchViewModel`
  - SwiftUI notch UI
- There are two important codepaths:
  - `PingIsland/`: the shipping Xcode app
  - `Prototype/`: a SwiftPM prototype with focused tests and reference implementations

## Start Here

- Product overview: `README.md`
- Public-distribution preparation and pending acceptance: `docs/mac-island-release-readiness.md`.
  No public download or App Store approval is implied by a successful build.
- Public source/Pages review: `docs/public-readiness-2026-10-31.md`, `SECURITY.md`,
  `docs/github-pages.md` and `docs/code-style.md`. Deploy only `site/`; never expose
  the full checkout or historical docs as the website. Keep source disclosure,
  Pages deployment and signed binary distribution as distinct verified results.
  All Swift source, tests and scripts use the strict repository-wide formatting baseline.
- App icon: `docs/design/mac-island-app-icon.md`; the selected Clean Notch PNG at `docs/images/mac-island-app-icon.png` is the source for `scripts/render-app-icons.sh`. Preserve transparent outer corners when regenerating the complete macOS AppIcon asset set.
- GitHub delivery rules: `CONTRIBUTING.md`; active iteration and acceptance boundaries: `docs/mac-island-iteration-plan.md`; delivered behavior, validation evidence and outstanding real acceptance: `docs/mac-island-iteration-validation.md`
- Personal Agent interface observation: `docs/personal-agent-integration-plan.md` and `docs/personal-agent-observation.md`; model: `PingIsland/Models/PersonalAgentObservation.swift`; owned reader/monitor: `PingIsland/Services/PersonalAgents/`; shared UI: `PingIsland/UI/Views/PersonalAgentViews.swift`. Muse 4.1 / 6.0 and Grok Bot 0.68.1 are opt-in experimental current-interface contracts, independent of hook clients. Dot has only an app entry, no verified independent task source. Never label ordinary Codex sessions Dot.
  - Read-only allowlist, bounded off-main AX reads, pruned conversation/input subtrees, version mismatch fails closed, coalesced notifications and EnergyGovernor polling/suspension. A weak snapshot row ID is never a native task ID or recent-record identity; keep observations/names in memory. Native Activity labels are combined source labels, not independently available task titles/status/timestamps. Hosted tests and fixtures reject real AX reads. Only the explicit permission button prompts; only the explicit app button activates the source. Shutdown removes Island observers without controlling external agents.
  - One card per verified current Bot context, with native activities collapsed inside; activities never multiply session counts. Muse identity text is read only in the exact avatar/name-control/tab sibling header (at most two name/badge leaves, including the verified one-level native wrappers), not throughout the pane. Validate leaf roles before values. Preserve activity order/duplicates; never merge different windows or panels by display name. Snapshot changes reset disclosure state; no stable native Bot identity or account-wide discovery is claimed.
  - Muse 6.0 uses a separate English-layout contract: a known Chat/Search/Settings rail plus a fixed composer anchor immediately followed by two matching leaf avatar buttons. Mirrored avatars yield one Bot; Side chats are never Bot names. Skip all static text/heading values and composer descendants; no 6.0 Activity support is claimed. Unknown versions/layouts fail closed. Read source versions afresh instead of trusting Bundle's cached info dictionary. Enabled unavailable sources have explicit status cards on both expanded surfaces, without session IDs, counts or recent records.
- App entry: `PingIsland/App/PingIslandApp.swift`, `PingIsland/App/AppDelegate.swift`
  - Normal quit uses `applicationShouldTerminate` and `AppTerminationCoordinator` to keep AppKit alive for asynchronous cleanup, with a five-second deadline and one reply for repeated requests. Do not launch unawaited cleanup from `applicationWillTerminate`.
- Mac Island product constraints: `PingIsland/Core/MacIslandProductPolicy.swift`
- Vibe Island compatibility research: `docs/research/vibe-island-analysis.md`
- Claude/OpenCode/Hermes protocol boundary: `docs/research/claude-opencode-hermes-integrations.md`
- DeepSeek Harness plugin boundary: `docs/research/deepseek-harness-integration.md`
- Docked/detached presentation orchestration: `PingIsland/App/IslandPresentationCoordinator.swift`, `PingIsland/App/WindowManager.swift`
- First-run surface-mode onboarding and mode-switch UI: `PingIsland/App/AppDelegate.swift`, `PingIsland/UI/Window/SettingsWindowController.swift`, `PingIsland/UI/Views/SettingsWindowView.swift`
  - `Models/MacIslandOnboarding.swift` and `UI/Views/MacIslandOnboardingView.swift`
    own independent three-step onboarding. Prepare its markers before Settings
    writes migration defaults; upgrades must not unexpectedly reopen it. The
    health step reads existing state only. `HookWalkthroughDemoRunner` now shows
    isolated synthetic examples, never inserts SessionStore/history entries,
    starts a client, installs hooks or requests approval.
- Screen privacy: `PingIsland/Models/ScreenContentVisibility.swift`,
  `UI/Components/ScreenPrivacyViews.swift`, `IslandOpenedContentView` and
  `IslandExpandedRouteResolver`. Fresh installs default to native titles;
  established installs preserve their previous details setting once. Shared
  observable state controls both surfaces, compact text, recent rows, Bots and
  already-open metadata/continuation views. Temporary hiding is memory-only and
  restores the user's selected level. Persisted/diagnostic privacy never weakens
  when rich screen content is enabled.
- Offline help/privacy/notices: `Models/MacIslandDocumentation.swift`,
  `UI/Views/MacIslandDocumentationView.swift`, `Resources/Legal/` and
  `docs/third-party-notices.md`. Preserve complete upstream/dependency licenses;
  `scripts/verify-distribution-legal.py` checks source and built-bundle consistency.
  Unconfigured support/download links stay absent rather than pointing upstream.
- User-triggered diagnostic export: `Services/Diagnostics/MacIslandDiagnosticsReport.swift`
  is a typed version/health allowlist. The monitor-only branch of
  `DiagnosticsExporter.exportArchive` must short-circuit the old raw collectors;
  no client configuration, logs, session data or paths enter that export.
- Native settings shell: `SettingsWindowController` owns the standard titled macOS window, while `SettingsWindowView` owns the System Settings-style searchable sidebar, adaptive detail header, grouped rows, and light/dark appearance. Keep the standard traffic-light controls, semantic AppKit colors, accessibility identifiers, and existing integration actions when changing settings UI.
  - Local integration badges are neutral and shared; regular actions use the system accent, and uninstall uses the destructive role/system red. Do not reuse client brand colors for installation state or configuration actions. See `docs/design/mac-island-integration-colors.md`.
- Main state hub: `PingIsland/Services/State/SessionStore.swift`
- Recent session metadata: `PingIsland/Services/State/RecentSessionIndex.swift` owns a versioned allowlist index (7 days / 200 by default; 24 hours / 100, session-only or disabled in Settings). `SessionMonitor` records observations and prunes with existing maintenance. Clearing keeps a cutoff to reject unchanged history; tests and fixture launches use memory only. No names, prompts, replies, derived titles, launch URLs, PID or TTY enter this index. `SessionListPresentation` excludes currently displayed native identities from history without mutating the index; client and origin stay distinct. Both surfaces default to Current sessions, with Recent records as a secondary entry. See `docs/design/mac-island-session-list.md`.
- Session association cache: `PingIsland/Services/State/SessionAssociationStore.swift`
- Usage/quota snapshots for Claude status-line caches, Claude-family transcript token totals, and Codex rollout logs: `PingIsland/Services/Usage/`
- Explicit native continuation preview: `PingIsland/Models/SessionContinuation.swift`, `PingIsland/Services/Continuation/`, `PingIsland/UI/Views/SessionContinuationPreviewView.swift`; implementation and certification boundary: `docs/session-continuation.md`, local contract evidence: `docs/client-capability-evidence.md`.
  - Production execution certification is empty. Keep unverified adapters preview/copy-only, desktop/unknown records out of CLI conversion, and monitoring read-only. Recheck preview expiration after asynchronous validation; linked-worktree checks include the common repository and return link. Models expose localization keys for UI feedback. A Terminal request never proves that a session was restored.
- Native runtime rollout scaffold: `PingIsland/Services/Runtime/`, `PingIsland/Core/FeatureFlags.swift`
- Session bridge for UI: `PingIsland/Services/Session/SessionMonitor.swift`
  - `startMonitoring` and `refreshUsageState` themselves reject XCTest, UI-test mode and fixture playback: docked/detached views call these from `onAppear`, so AppDelegate's launch gate alone is insufficient. Hosted window tests must never start real app-server, hook, quota or database reads.
- Notch state and layout: `PingIsland/Core/NotchViewModel.swift`, `PingIsland/UI/Views/NotchView.swift`
- App-wide low-power policy for background polling, event monitoring, UI animation tiers, and silent update gating: `PingIsland/Core/EnergyGovernor.swift`
- User idle protection for temporarily routing blocking approvals/questions back to terminals: `PingIsland/Core/UserIdleAutoProtection.swift`, `PingIsland/Core/Settings.swift`, `PingIsland/Services/Hooks/BridgeRuntimeConfigWriter.swift`
- Detached floating capsule: `PingIsland/UI/Window/DetachedIslandWindowController.swift`, `PingIsland/UI/Views/DetachedIslandPanelView.swift`, `PingIsland/UI/Views/IslandOpenedContentView.swift`
  - Detached pet interactions now keep the pet anchored in place while hover/click previews expand sideways as message-bubble lists; trace both the panel layout and window-anchor math together when changing this flow
  - Expanded content routing is shared with the docked notch through `IslandOpenedContentView` + `IslandExpandedRouteResolver`; keep hover/click/notification semantics aligned instead of reintroducing detached-only content priorities
- Local hide state: `SessionQuickActions.swift` filters presentation by session ID and activity time; fresh activity restores visibility without deleting SessionStore state. Shared quick actions copy the native ID, open a local folder, or hide only in Island. New return/next-attention global shortcuts are unassigned by default; `IslandPresentationCoordinator` handles them for both surfaces and `GlobalShortcutManager` exposes registration failures.
- Global shortcuts and shortcut persistence: `PingIsland/Services/Shared/GlobalShortcutManager.swift`, `PingIsland/Utilities/GlobalShortcut.swift`, `PingIsland/Core/Settings.swift`, `PingIsland/UI/Views/SettingsWindowView.swift`
- Claude hook ingress: `Prototype/Sources/IslandBridge/`, `PingIsland/Services/Hooks/HookInstaller.swift`, `PingIsland/Services/Hooks/HookSocketServer.swift`
  - `PingIslandBridge` is the unified Claude/Codex hook entrypoint and is responsible for terminal, tmux, SSH-remote, and IDE terminal context capture before envelopes hit Swift code
- Codex ingress: `PingIsland/Services/Codex/`, `PingIsland/UI/Views/CodexSessionView.swift`
  - `CodexExecutableResolver` prefers the running/registered `com.openai.codex` app, supports current `codex-cli` and legacy resource layouts, then searches application directories and CLI PATH. Keep discovery independent of the visible app name and a shell-initialized PATH; resolver tests use synthetic apps only.
  - `CodexMonitorHealth` owns content-free health and retry policy. Connection attempts, requests and subscriptions carry a generation; old/cancelled work must not update current health. `SessionMonitor` forwards EnergyGovernor suspension. Reconnect only the Island subscription; never kill an externally owned client.
  - Production monitoring uses only the owned child’s private stdio JSONL channel; never attach to a discovered loopback listener. Keep framing, writes and shutdown bounded.
  - Retire failed connection attempts before scheduling retry, discard transport-owned approval requests on disconnect, and reset retry backoff only after a successful data read. `CodexMonitorTransport` enables offline lifecycle tests with delayed reads and stale notifications; these must never start a real client.
  - Application shutdown permanently closes the monitor before awaiting its owned observer. Ordinary stop remains restartable. Cleanup uses only the retained child `Process`, with bounded graceful termination and escalation; never discover or terminate processes by name, port, or external client identity.
  - Integration settings expose read-only Bridge checks and Codex reconnect. Health queries must not install or repair launcher files; explicit integration installation remains separate.
  - Hook-less fallback parsing for Codex sessions lives in `PingIsland/Services/Codex/CodexRolloutParser.swift`
- Cursor local ingress: `PingIsland/Services/Cursor/CursorConversationMonitor.swift`
  - It opens Cursor's `state.vscdb` read-only and joins lightweight composer headers with local `cursorDiskKV` bubble records so model identity, thinking, tool progress, and assistant output can be projected in memory. Keep conversation bodies out of caches, diagnostics, and telemetry.
- OpenCode/Hermes restart recovery: `PingIsland/Services/Session/ObservedSessionRecovery.swift`
  - Recovery is metadata-only, opens SQLite read-only, validates required table columns, excludes child rows, and disables itself when a schema changes. Never add message/history/tool-body reads to this fallback.
  - OpenCode recovery has unknown origin until a live event identifies CLI/Desktop; do not infer origin from a running desktop app. Unknown rows cannot navigate and are not persisted as routing associations. `SessionStore` consumes only the same native ID's unknown card; known CLI/Desktop identities remain separate. Hermes uses the same fallback timestamp for selection, filtering and ordering.
- Terminal and focus control: `PingIsland/Services/Tmux/`, `PingIsland/Services/Window/`, `PingIsland/Utilities/TerminalVisibilityDetector.swift`
  - Terminal focus flows currently cover iTerm2, Ghostty, Terminal.app, tmux, and IDE-hosted terminals
- Remote SSH forwarding and remote-host management: `PingIsland/Services/Remote/`
  - Remote hosts can bootstrap a bridge on the SSH target, rewrite remote hooks, install managed plugin-directory integrations such as Hermes under the remote home directory, and attach a bidirectional forwarding channel back into PingIsland
  - The remote bridge forwards recent Codex app-server thread activity from the SSH target's `~/.codex/state_*.sqlite` through the existing remote hook-event channel
- Provider/client routing: bridge envelopes are normalized in `PingIsland/Services/Hooks/HookSocketServer.swift`, stored on `SessionState`, and launched via `PingIsland/Services/Window/SessionLauncher.swift`
- Client profile registry: installable hook clients and runtime client branding / recognition are centralized in `PingIsland/Models/ClientProfile.swift`
- VS Code-compatible IDE focus extension install / URI launch: `PingIsland/Services/Window/IDEExtensionInstaller.swift`, `PingIsland/Services/Window/TerminalSessionFocuser.swift`
- Explicit session navigation: `SessionActionController` is the shared in-memory action/feedback owner for list, keyboard, hover and chat controls. `SessionLauncher` and `TerminalSessionFocuser` propagate `SessionNavigationResult`: terminal confirmation, unconfirmed request, app-only activation, unavailable or failure. Never upgrade URL acceptance, workspace routing or tmux command success to exact-session confirmation. Keep failure context visible through `IslandOpenedContentView` on both surfaces; do not close before a result. Inject `SessionNavigating` for deterministic tests; preserve in-flight deduplication and generation checks.
  - The controller's value/reference-only destruction uses `nonisolated deinit` for older macOS runtime compatibility; keep synchronous feedback tests in the gate.
- Session list UI: `PingIsland/UI/Views/SessionListView.swift`
  - `SessionListTitleStore` keeps native names in memory; missing names never fall back to prompts, summaries or folders. Codex name reads use the existing connection and summary-only `thread/read`, without importing a session. Preserve bounded concurrency, cancellation, live-rename precedence and test/fixture isolation.
  - Explicit client-open buttons navigate; clicking a row selects it. List feedback stays with the matching native identity, with a header fallback for removed/hidden rows. Other expanded routes retain shared feedback.
  - Inactive CLI session menus open `SessionContinuationWindowController` for an explicit preview; it reuses one native window across both Island surfaces and cancels preparation on close.
  - List keyboard handling uses `SessionListKeyboardScope` to match the hosting window on both surfaces; other windows, text editors and modified shortcuts keep their keys.
- Client mascot system: `PingIsland/UI/Components/MascotView.swift`, `PingIsland/UI/Views/MascotSettingsView.swift`
- Mac Island selected client glyph and motion specification: `docs/design/mac-island-client-glyphs.md`
  - `MacIslandPersonalAgentPixelArt.swift` shares original Muse/Grok Bot frames with the native glyph view and `scripts/render-personal-agent-glyphs.sh`. Bot cards animate only during hover, independently of unknown execution state; settings stay static. Preserve reduce-motion/EnergyGovernor gates and the existing working-only rule for coding clients. Dot remains a fallback without a verified independent source.
- App updates and release notes: `PingIsland/Services/Update/`, `PingIsland/UI/Views/ReleaseNotesWindowView.swift`, `PingIsland/UI/Window/ReleaseNotesWindowController.swift`
- Sparkle build configuration: `Config/App.xcconfig`, `Config/LocalSecrets.xcconfig`, `docs/sparkle-release.md`
- Mac App Store distribution lane: `PingIslandAppStore` target / scheme, `PingIsland/Info-AppStore.plist`, `PingIsland/Resources/PingIsland-AppStore.entitlements`, `Config/AppStore.xcconfig`, `scripts/build-app-store.sh`, and `docs/mac-app-store-submission.md`

## Repo Map

- `PingIsland/App`: app lifecycle, window setup, screen observation
- `PingIsland/Core`: notch geometry, shared state, app settings, selectors
- `PingIsland/Models`: domain models for sessions, events, tools, phases
- `PingIsland/Services`: ingestion, socket handling, state management, tmux, windows, updates
- `PingIsland/Services/Usage`: Claude status-line quota cache readers, Claude-family transcript token parsing, and Codex rollout quota readers for UI usage summaries
- `PingIsland/Services/Runtime`: isolated native Claude/Codex runtime work. This path should coexist with the current implementation behind feature flags until parity is proven.
- `PingIsland/Services/Remote`: remote endpoint persistence, SSH bootstrap / attach, and remote hook forwarding
  - Remote bootstrap currently covers JSON hook configs, managed hook directories, and managed plugin directories (for example remote Hermes installs under `~/.hermes/plugins/ping_island`)
- `PingIsland/Services/Update`: Sparkle updater bridge, appcast/release-notes loading, update state publishing
- `PingIsland/Services/Window/IDEExtensionInstaller.swift`: installs the VS Code-compatible terminal-focus extension used by Cursor / VS Code / CodeBuddy / Qoder / Qoder CN style IDE hosts (`QoderWork` is hook-only, not an IDE extension host)
- `PingIsland/UI`: SwiftUI views, reusable components, AppKit-backed window controllers
- `PingIsland/Resources`: hook assets, entitlements, bundled fonts
- `Prototype`: Swift package prototype and testbed
- `Prototype/Tests`: logic-level unit tests plus process/socket e2e coverage for `IslandBridge`, hook mapping, and install flows
- `scripts`: release, signing, and packaging automation
- `Config`: checked-in build configuration defaults plus optional local-only secrets overrides

## Change Routing

- If you change hook payload shape or hook event semantics, update these together:
  - `Prototype/Sources/IslandBridge/`
  - `PingIsland/Services/Hooks/HookSocketServer.swift`
  - `PingIsland/Models/SessionEvent.swift`
  - `PingIsland/Services/State/SessionStore.swift`
  - the affected UI under `PingIsland/UI/`
- If you change provider/client detection or click-through behavior, trace through `HookSocketServer`, `SessionStore`, `SessionState`, `SessionLauncher`, and the session list / hover UI so labels and launch targets stay in sync.
- If you add a Claude-compatible hook client, start in `PingIsland/Models/ClientProfile.swift` and wire any truly client-specific behavior from there before adding new ad-hoc switches elsewhere.
  - Gemini CLI hooks are managed through `~/.gemini/settings.json`; its `BeforeTool` / `AfterTool` matchers are regex-based, so use `.*` rather than Claude-style `*`.
  - Antigravity CLI is managed as a generated native plugin under `~/.gemini/antigravity-cli/plugins/ping-island/`, with `plugin.json` plus namespaced `hooks.json`. Its camelCase hook payloads use `conversationId`, `workspacePaths`, and `toolCall`; keep those normalized at the bridge boundary. Ping Island's observational `PreToolUse` hook must return `ask` so Antigravity's native permission engine remains authoritative, including when the Island socket is unavailable.
  - Hermes uses the official plugin under `~/.hermes/plugins/mac_island/`, enabled and checked through `hermes plugins`. Keep callbacks observation-only, accept `**kwargs`, return `None`, ignore cron/gateway sources, and merge subagents into their parent session. Hermes Desktop is `com.nousresearch.hermes.setup`.
  - Qwen Code hooks are managed through `~/.qwen/settings.json`; follow the official Qwen Code hook event names (`PreToolUse`, `PostToolUseFailure`, `Notification`, `Stop`, etc.) and remember that `Notification` matcher values are exact notification types such as `permission_prompt`, `idle_prompt`, and `auth_success`.
  - OpenClaw hooks are managed as a generated internal hook directory under `~/.openclaw/hooks/<hook-name>/` and require the paired enablement entry in `~/.openclaw/openclaw.json`; treat it as a directory-discovery integration, not a JSON hook list.
  - Gemini `Notification` hooks are observability-only in the upstream protocol; do not treat them as actionable approval callbacks unless the bridge grows explicit Gemini response handling.
  - Qoder-family hook installs currently cover Qoder IDE and Qoder CLI as separate profiles that share `~/.qoder/settings.json`, plus QoderWork under `~/.qoderwork/settings.json`. Keep Qoder IDE and Qoder CLI hook semantics independent even though they share a file; app launch should refresh only the Qoder CLI managed entries when `qodercli -v` is newer than 0.2.5 while preserving Qoder IDE hooks and unrelated JSON settings. New Qoder CLI uses Claude Code-compatible blocking hooks and response payloads; Qoder IDE and QoderWork remain notify-only and must not create Island-side blocking question or approval responses.
  - Qoder CN is a separate product identity: its desktop app uses bundle identifier `com.aliyun.lingma.ide`, URI scheme `qoder-cn`, and `.qoder-cn` data root, while its CLI executable is `~/.local/bin/qoderclicn`. Keep `qoder-cn` and `qoder-cn-cli` separate from the international Qoder profiles even though the CN desktop and CLI share `~/.qoder-cn/settings.json`; the desktop remains notify-only while the CLI uses blocking Claude-compatible responses.
  - CodeBuddy-family hook installs currently cover CodeBuddy IDE and CodeBuddy CLI as separate profiles that share `~/.codebuddy/settings.json`, plus WorkBuddy under `~/.workbuddy/settings.json`. Keep CodeBuddy IDE and CodeBuddy CLI hook semantics independent even though they share a file; CodeBuddy CLI uses its Claude-compatible hook response shape and must preserve CodeBuddy IDE hooks plus unrelated JSON settings.
  - OpenCode is managed as an auto-loaded generated plugin file under `~/.config/opencode/plugins/mac-island.js`; never add it to or otherwise rewrite `opencode.json`. Support both current and compatibility event names (`session.idle`, permission/question v2, etc.), and route `parentID` child sessions into parent activity instead of creating duplicate cards.
  - DeepSeek Harness is managed as a generated observation-only ESM plugin under `~/.dsh/plugins/mac-island/index.mjs`, activated by a marked block in the global `~/.dsh/cordis.patch.yml`. Preserve all user-owned patch rows and comments, never forward tool arguments/results, never decide approvals, and treat DSH `cron` work as out of scope. DSH is still a Developer Preview, so keep event compatibility covered by tests and fail open when a future version changes the plugin API.
  - Kimi CLI hooks are managed primarily through `~/.kimi-code/config.toml`, with `~/.kimi/config.toml` retained as a legacy fallback; use `[[hooks]]` array-of-tables syntax. The installer preserves all non-Island TOML content (providers, models, loop_control, etc.) and only manipulates the `[[hooks]]` sections. Event names follow the Claude Code convention (`SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Notification`, `Stop`).
  - Pi Agent is managed as a generated TypeScript extension under `~/.pi/agent/extensions/ping_island/index.ts`; treat it as an official Pi extension integration that forwards events through the Claude-compatible bridge with `client-kind=pi`, not as JSON/RPC polling or process scanning. Pi has a dedicated `MascotKind.pi`, so trace mascot changes through `ClientProfile`, `SessionProvider`, `MascotView`, and mascot settings together.
  - `QoderWork` should not be added to `ideExtensionProfiles` unless it actually ships VS Code-compatible extension support in the future.
- If you change how sessions are associated across relaunches or between hook/app-server ingress paths, inspect both `SessionStore` and `SessionAssociationStore` so cached client metadata stays compatible.
  - Claude Code/OpenCode/Hermes/DSH identity is `client + native session ID + origin`. Do not add a second product-specific prefix before `MacIslandProductPolicy.observedSessionKey` namespaces it.
- If you change integration installation, preserve the explicit-user-action gate, atomic writes, and backups under `~/.mac-island/backups/integrations/`. Uninstall only Mac Island-managed entries and preserve custom Claude status lines, unrelated hooks, OpenCode config, and existing Hermes plugin state.
- Rich prompt/reply/tool progress may be shown in memory, but must not enter diagnostics, Bridge logs, routing associations, usage caches, or telemetry. Tool arguments, complete tool output, and credentials are never part of the observed projection.
- If you change the new native runtime rollout path, keep it isolated from the legacy hook/app-server flow. Reuse shared `SessionState`-driven views, but keep runtime orchestration, persistence, and feature gating under `PingIsland/Services/Runtime/` and `PingIsland/Core/FeatureFlags.swift`.
- If you change session lifecycle or transitions, start in `SessionStore`. Avoid ad-hoc state mutation elsewhere.
  - Current rule: provider-originated end events should preserve the session in `.ended` so it stays visible in the list; only explicit user archive/removal should delete it from `SessionStore`.
  - Supported clients have stable native IDs: another session in the same directory is not restart/death evidence. Do not apply the legacy provider + cwd orphan-removal heuristic to product sessions.
  - Primary list rule: sessions with no new activity for 30 minutes should auto-hide from the primary list until fresh hook/file/app-server activity updates `lastActivity`; sessions that need manual attention should stay visible.
- If you change notch sizing, opening behavior, or visibility, inspect both `NotchViewModel` and `NotchView`.
- Automatic panel presentation is product-disabled: session lifecycle, permission, completion, compaction, and startup events may update only the compact surface. Rich detail opens after hover or another explicit user interaction, and docked plus detached paths must keep this rule aligned.
- If you change docked/detached Island transitions or drag-to-detach behavior, trace through `IslandPresentationCoordinator`, `WindowManager`, `NotchViewModel`, `NotchWindowController`, and `DetachedIslandWindowController` together so gesture gating, content resolution, and re-docking stay aligned.
- If you change the persisted surface mode or first-run onboarding, trace through `AppDelegate`, `WindowManager`, `IslandPresentationCoordinator`, `SettingsWindowController`, `SettingsWindowView`, and `Settings.swift` together so launch-time routing and in-app switching stay aligned.
- If you change global shortcuts, shortcut persistence, or shortcut hints, trace through `PingIsland/Services/Shared/GlobalShortcutManager.swift`, `PingIsland/Utilities/GlobalShortcut.swift`, `PingIsland/Core/Settings.swift`, `PingIsland/UI/Views/SettingsWindowView.swift`, `PingIsland/UI/Components/GlobalShortcutHintView.swift`, and the relevant notch/chat/session-list views together so registration, customization, and visible hints stay aligned.
- If you change the settings shell, verify both the SwiftUI `Settings` scene and `SettingsWindowController` presentation paths. The sidebar must remain keyboard/accessibility navigable, searchable, and visually adaptive in the system light and dark appearances; do not reintroduce a forced color scheme or custom fake window controls.
- If you change background polling, global event monitors, silent update scheduling, or idle animation behavior, inspect `PingIsland/Core/EnergyGovernor.swift` plus the affected service/view so active sessions stay responsive while quiet, locked, or sleeping periods remain low-power.
- Mac Island is forced silent. If upstream sound code changes, preserve the shared playback guard in `PingIsland/Core/Settings.swift`, the disabled settings state, and `MacIslandProductPolicy.soundsEnabled == false`.
- If you change client mascot selection or mascot animations, trace through `PingIsland/Models/ClientProfile.swift`, `PingIsland/Core/Settings.swift`, `PingIsland/UI/Components/MascotView.swift`, and the mascot callsites in `NotchView`, `SessionListView`, `SessionHoverPreviewView`, and `MascotSettingsView` so runtime overrides and previews stay aligned.
- If you change completion-result popup behavior, trace through `SessionStore`, `SessionMonitor`, `PingIsland/UI/Views/NotchView.swift`, and `PingIsland/UI/Views/SessionCompletionNotificationView.swift` so completion detection, queueing, and auto-dismiss timing stay aligned.
- If you change tmux or terminal focusing, trace through `Services/Tmux`, `Services/Window`, and `TerminalVisibilityDetector`.
- If you change IDE terminal jump behavior, inspect both `TerminalSessionFocuser` and `IDEExtensionInstaller`, plus the integration settings UI so install state and URI schemes stay aligned.
- If you change Codex behavior, verify both the monitor layer under `PingIsland/Services/Codex/` and the UI under `PingIsland/UI/Views/CodexSessionView.swift`.
  - Long Codex/subagent prompts, results, tool details, and transcript rows must keep full data in `SessionStore` / snapshots and apply bounded display text only at SwiftUI rendering boundaries. Prefer `SessionTextSanitizer.boundedDisplayText` for inline `Text` / Markdown content, add or preserve tests for truncation behavior, and avoid passing unbounded transcripts directly into expanded Island detail views.
- If you change app updates or release notes, trace through `PingIsland/Services/Update/`, `PingIsland/Info.plist`, the settings UI, and `scripts/create-release.sh` so appcast assets, runtime config, and update messaging stay aligned.
- If you change Sparkle configuration keys or hosting assumptions, update `Config/App.xcconfig`, `Config/LocalSecrets.example.xcconfig`, `scripts/generate-keys.sh`, and `docs/sparkle-release.md` together.
- If you change App Store distribution behavior, keep the `PingIslandAppStore` target isolated from the regular `PingIsland` Developer ID/Sparkle lane, and update `docs/mac-app-store-submission.md` plus `scripts/build-app-store.sh` together.
- If you only need logic-level confidence, prefer adding or updating tests under `Prototype/Tests`.

## Build And Test

- Authoritative Mac Island product gate (Prototype + Release build + product suites listed in the script):
  - `./scripts/test.sh`
- App debug build:
  - `xcodebuild -project PingIsland.xcodeproj -scheme MacIsland -configuration Debug build`
- App release build:
  - `xcodebuild -project PingIsland.xcodeproj -scheme MacIsland -configuration Release build`
- The historical App Store wrapper is disabled and exits before changing files.
  Store adaptation requires a separate plan; it is not a validation command.
- Full upstream Xcode unit compatibility audit (non-gating for Mac Island):
  - `xcodebuild -project PingIsland.xcodeproj -scheme MacIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
- Upstream Xcode UI compatibility audit (non-gating; requires local signing):
  - `xcodebuild -project PingIsland.xcodeproj -scheme MacIsland -configuration Debug CODE_SIGN_IDENTITY=- test -only-testing:PingIslandUITests`
  - macOS may block the UI test runner until a valid local signing identity is available; if `PingIslandUITests-Runner` stays launch-suspended, inspect `amfid` and `AppleSystemPolicy` logs before treating it as an app regression
- Prototype tests:
  - `swift test --package-path Prototype`
- Bridge-focused e2e slice:
  - `swift test --package-path Prototype --filter IslandBridgeE2ETests`
- Mascot GIF export for docs/resources:
  - `./scripts/render-mascots.sh`
- Retained upstream release automation (not a Mac Island release authorization):
  - `./scripts/build.sh`
  - `./scripts/package-release.sh`
  - `./scripts/package-unsigned.sh`
  - `./scripts/create-release.sh`
  - `./scripts/generate-keys.sh`
  - Disabled upstream archive: `.github/workflows/release-packages.yml.disabled` previously imported a Developer ID certificate from repository secrets, notarizes the exported app, publishes signed `dmg` / `zip` assets plus a zipped Linux `PingIslandBridge` remote-agent payload to the matching GitHub Release for a `v*` tag or manual dispatch, and treated the DMG as the primary manual-install artifact. This workflow is disabled; current CI calls `scripts/test.sh` and never publishes
- Release scripts assume local signing and notarization tooling. They may modify `build/`, `releases/`, and `.sparkle-keys/`.
- Current candidate-release tooling is documented in `docs/mac-island-release-readiness.md`.
  Keep preflight separate from explicit execution; signing/notarization is not
  routine testing. Candidate execution may upload to Apple for notarization but
  must not create a public GitHub Release, publish downloads or install the app.

## Working Rules

- Respect existing uncommitted changes. Do not revert unrelated work.
- For this maintainer workflow, use GitHub Desktop for local branch, commit,
  synchronization and merge operations. Read-only Git inspection is fine;
  maintain the Issue/PR/final-head CI gates in `CONTRIBUTING.md`.
- This is the clean source-publication repository `Samadhi-Chi/mac-island`.
  The former repository's history remains in private `mac-island-private-archive`;
  never merge/import its Git history into this repository. Preserve LICENSE,
  NOTICE and upstream attribution. See `docs/source-history.md`. Source publication
  does not enable telemetry, hooks, binary releases or installation.
- Use the actual Git root of this checkout; old machine paths in historical records are not migration instructions. Build caches may use an external disk via `BUILD_ROOT`; `BUILD_JOBS` defaults to 2.
- Keep user authentication, `~/.codex`, Keychain material, and `Config/Local.xcconfig` out of Git. Use `Config/Local.example.xcconfig` for optional local signing settings; never activate the old shared-machine profile.
- Prefer narrow edits. This repo currently has active changes in UI and session-flow files.
- Treat documentation upkeep as part of the change, not follow-up work.
- When writing or updating tests, do not use the user's local filesystem paths as example values; prefer repo-relative, generic, or clearly synthetic paths instead.
- Every major feature change or refactor must review and update `AGENTS.md` plus any affected adjacent docs, tests, scripts, or inline code comments that describe the old behavior.
- Prefer code search over guesswork:
  - `rg "process\\(" PingIsland`
  - `rg "Hook|hook" PingIsland`
  - `rg "Codex" PingIsland Prototype`
  - `rg "tmux|Tmux" PingIsland`
- When adding new state, decide deliberately whether it belongs in:
  - SwiftUI view-local `@State`
  - shared `ObservableObject` state
  - actor-owned `SessionStore` state
- Keep localization lookups at UI or other actor-appropriate boundaries. `AppLocalization.string` is main-actor isolated on CI toolchains, so nonisolated utilities such as sanitizers, parsers, stores, and model helpers should expose localization keys or plain data instead of calling localization APIs directly.
- When adding bundled assets or fonts, make sure app startup initializes them.
- Keep this file high-signal. If a section becomes long, move the durable detail into a dedicated markdown doc and link it here.

## Verification Checklist

- Can the main Xcode scheme still build?
- If the change is a major feature or refactor, was `AGENTS.md` reviewed and updated to reflect the new structure, ownership, entrypoints, or verification steps?
- If session ingestion changed, do both Claude and Codex sessions still appear and update?
- If session lifecycle changed, do ended sessions remain visible until the user archives them, and do final Claude/Codex messages still land before the row settles into `.ended`?
- If idle-session visibility changed, do sessions auto-hide after 30 minutes of inactivity and reappear when a new message or hook/app-server event arrives?
- If detached Island behavior changed, can the docked notch still click-open normally, drag-detach from closed/opened states, and re-dock cleanly without duplicate windows?
- If approval or intervention flows changed, do approve, deny, and answer paths still resolve cleanly?
- If focus logic changed, does tmux and non-tmux behavior still degrade safely?
- If release tooling changed, avoid running notarization or signing steps unless the task explicitly requires them.

## Current Reality

- The main shipping target is the Xcode project, not the Swift package under `Prototype/`.
- The root project now includes `PingIslandTests` and `PingIslandUITests` targets for app-level state and settings-window coverage.
- `Prototype/Tests` remains the fastest place for logic-level unit tests plus process/socket e2e coverage.
- Sparkle remains linked in the regular target for upstream compatibility, but
  Mac Island disables its update service. Historical appcast and App Store
  upload notes do not configure or authorize this product's distribution.
- The worktree may already be dirty. Check `git status` before broad edits.
