# Vibe Island compatibility analysis

Date: 2026-07-26  
Installed build observed: Vibe Island 1.0.42 (`app.vibeisland.macos`)

## Boundary

This is compatibility-oriented, clean-room-style research for a personally
installed copy. It records public behavior, bundle metadata, exported symbols,
local IPC characteristics, and resource inventory. It does not bypass licensing
or DRM, extract reusable source, copy artwork or sounds, or commit any Vibe Island
binary.

Labels used below:

- **Observed**: directly verified from the installed bundle or a read-only runtime snapshot.
- **Inference**: a design conclusion consistent with the observations, but not proof of implementation details.
- **Adopt**: behavior Mac Island will implement independently or inherit from Apache-licensed Ping Island code.
- **Avoid**: deliberately outside the first runnable build.

## Findings

### Native window and presentation

- **Observed**: the executable is a signed and hardened Universal Mach-O app with a macOS 14 minimum deployment target. It links AppKit and SwiftUI and exports names including `NotchPanel`, `NotchWindowController`, and `NotchViewModel`.
- **Observed**: bundle strings reference `NSPanel`, mouse-event pass-through, notch geometry offsets, multiple displays, and screen-saver transitions.
- **Inference**: the compact surface is a non-activating AppKit panel hosting SwiftUI content, with its mouse behavior changed between collapsed and expanded states.
- **Adopt**: use Ping Island's Apache-licensed borderless non-activating `NSPanel`, all-Spaces/full-screen auxiliary behavior, and collapsed-state hit-test pass-through. Use a detached top-center capsule on displays without a notch.
- **Observed**: user-supplied screenshots show a wide black top panel with rounded lower corners, a compact header, a primary session row, right-aligned client/status badges, a large conversation card, and a license upsell card.
- **Adopt**: independently implement the general hierarchy—wide top workspace, quiet black materials, inset session cards, concise badges, and persistent header controls—using SwiftUI and SF Symbols.
- **Avoid**: the exact measurements, mascot pixels, copywriting, paid-unlock card, and any screenshot-derived asset.
- **Observed**: Vibe Island's visible panel is localized around the notch instead of keeping a screen-wide high-level backing surface alive while collapsed.
- **Observed**: an earlier Mac Island build used a transparent `screen.width × 750pt` panel at `.mainMenu + 3`; opening macOS Notification Center then produced a nearly black compositor backdrop in the panel's footprint.
- **Adopt**: the monitor-only build uses a top-centered localized presentation surface (696 × 624pt on the current 1710 × 1112 display) at `.statusBar` level. Hit testing is clipped to that local surface. This preserves the compact island while no longer covering Notification Center's right-side material with an oversized high-level window.
- **Adopt**: use short hover intent and dismissal delays, one expanded detail target at a time, non-activating hover, and focus only after an explicit click. These are independently tuned interaction principles; no Vibe code, timing constants, or private assets are copied.
- **Adopt**: lifecycle, permission, completion, and compaction events update only the compact status surface. They never expand or bounce the panel automatically; rich detail appears after pointer hover or another explicit user interaction.
- **Adopt**: preserve the latest local Codex commentary, running-tool state, and final multi-line response as a chronological in-memory projection. App-server and rollout records are merged by timestamp with a narrow cross-source duplicate window; legitimate repeated prompts in different turns remain distinct.
- **Adopt**: the four-tile Codex mark animates only while the selected session is working, using independently implemented rotation, subtle scale, breathing opacity, and tile-brightness phases. The same component is used in the collapsed island, session rows, hover preview, and detached presentation.

### Hook and IPC path

- **Observed**: Vibe Island installs a separate Universal `vibe-island-bridge` and platform-specific hook binaries. The bridge accepts source, event, socket, and timeout arguments.
- **Observed**: the running app listened on `~/.vibe-island/run/vibe-island.sock` and loopback TCP `127.0.0.1:17891`; no external connection was present in the runtime snapshot.
- **Observed**: bridge strings show fire-and-forget, acknowledgement, and wait-for-response modes plus explicit connection and response timeouts.
- **Inference**: non-blocking lifecycle events use a quick local send, while approval-capable integrations may keep a response channel open.
- **Adopt**: a small hook bridge, local Unix socket, bounded payload, and fail-open behavior. Mac Island V1 always uses observation-only delivery and never holds a permission request open.

### Session identity and jump routing

- **Observed**: the bridge collects terminal variables such as TTY, iTerm, Warp, WezTerm, Zellij, cmux, and IDE/Cursor identifiers. It also reads Cursor's local state database and Codex session metadata.
- **Observed**: the app requests Apple Events permission specifically to focus the matching terminal window, tab, and session. Public documentation describes an IDE extension for precise VS Code-family window matching.
- **Inference**: jump behavior is adapter-based: exact terminal/IDE focus where metadata exists, application activation otherwise.
- **Adopt**: keep jump routing separate from session state. Prefer `codex://threads/<id>` for Codex Desktop and the Cursor extension/workspace URI for Cursor; clearly expose degraded activation-only routing.

### Privacy and network boundary

- **Observed**: the bundle contains Sparkle and Sentry frameworks, while the main executable's direct dependency list includes Sparkle but not Sentry.
- **Observed**: preferences contain local `analytics.*` behavior counters and the bundle enables update checks. This alone does not establish that those counters are transmitted.
- **Observed**: the vendor privacy policy states that hook events, JSONL files, and terminal metadata are processed locally and that code, prompts, and responses are not uploaded.
- **Adopt**: Mac Island has no telemetry endpoint, does not start the update manager, does not persist full hook payloads, and defaults hook debug logging off. Runtime network QA must show only local IPC.
- **Observed**: the supplied expanded-panel screenshots visibly expose user messages, answer text, code/table names, and filenames to anyone who can see the desktop.
- **Observed**: the user explicitly chose progress visibility over an on-screen privacy mask for this personal local build.
- **Adopt**: the expanded UI shows the recent local instruction plus current response/status by default and exposes a larger detail card on hover or selection. The `Private` screen label is removed.
- **Adopt**: the data boundary remains content-minimizing even though the screen is detailed: full prompts and outputs are not written to usage caches, routing associations, diagnostics, telemetry, or Bridge logs; there is no external telemetry or update check. Screen disclosure and data persistence are treated as separate policies.
- **Adopt**: the Codex provider and real remaining quota are read through the local read-only app-server rate-limit endpoint, without reading API credentials. Unknown or stale quota is rendered as unavailable instead of being fabricated as `100%`.
- **Adopt**: after the user opted into richer on-screen progress, read-only `thread/read` may request turns. Those turns remain memory-only; diagnostic session snapshots redact the local thread name, preview, response, project label, subagent label, working directory, and transcript path for supported Codex/Cursor sessions. Unified logs record only path-presence booleans, not the paths themselves.

## Product decisions

- **Adopt**: native windowing, event-driven local IPC, source precedence, session deduplication, low-power polling fallback, adapter-based focus, local progress details, and read-only provider quota projection.
- **Avoid**: in-island approvals and answers, API credential reads, SSH forwarding, broad multi-agent support, remote update feeds, telemetry, copied mascot art, sound packs, and complex onboarding.
- **Avoid**: copying Vibe Island strings, layout measurements, artwork, sounds, executable code, signing material, or license logic.

## Public references

- [Vibe Island product page](https://vibeisland.app/)
- [Vibe Island privacy policy](https://vibeisland.app/privacy/)
- [Vibe Island precise jump documentation](https://vibeisland.app/precise-jump/)
