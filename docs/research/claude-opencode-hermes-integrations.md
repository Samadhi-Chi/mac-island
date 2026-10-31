# Claude Code, OpenCode, and Hermes integration notes

Date: 2026-08-19; recovery semantics updated 2026-09-26.

This document records the implementation boundary for Mac Island 0.27.0. It
describes observable protocols and local metadata only; it is not a copy of any
client implementation.

## Product boundary

- Supported: Claude Code CLI, Claude Desktop Code, OpenCode CLI/Desktop, and
  Hermes CLI/Desktop, alongside Codex and Cursor.
- Excluded: ordinary Claude Chat, Cowork, web sessions, Hermes cron/gateway
  maintenance, and any non-interactive OpenCode/Hermes work.
- All integrations are observation-only. Permission events immediately return
  control to the client; Mac Island never approves, denies, answers, starts, or
  resumes agent work.
- Recent prompts, reply excerpts, and five compact activity rows are held only
  in `SessionState`. They are excluded from diagnostics, routing associations,
  usage caches, Bridge logs, and telemetry.
- The app is silent. Audio playback is blocked centrally even if an old user
  preference says that sounds were enabled.

## Local compatibility baseline

The implementation was checked against the locally installed clients:

- Claude Code 2.1.228
- OpenCode 1.17.3
- Hermes 0.20.1
- Claude Desktop bundle: `com.anthropic.claudefordesktop`
- OpenCode Desktop bundle: `ai.opencode.desktop`
- Hermes Desktop bundle: `com.nousresearch.hermes.setup`

These versions are an acceptance baseline, not a permanent version pin.

## Event projection

Every client is projected to the same display-only shape: native session ID,
client, CLI/Desktop origin, project, native title, provider, model, state,
bounded display text, tool label, and timestamp. The stable key is:

`client + native session ID + CLI/Desktop origin`

OpenCode child sessions and Hermes subagents emit activity on the parent card.
They never create independent primary cards.

### Claude Code

- Configuration: `~/.claude/settings.json`
- Events: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`,
  `PostToolUseFailure`, `PermissionRequest`, `Notification`, subagent/task
  lifecycle, `Stop`, `StopFailure`, and `SessionEnd`.
- The existing custom status line is preserved. Mac Island only displays Claude
  5h/7d quota when its own status-line cache is installed and no older than
  fifteen minutes.
- CLI sessions use captured terminal routing. Desktop Code activates Claude;
  there is no invented deep link for an existing Code session.

### OpenCode

- Plugin: `~/.config/opencode/plugins/mac-island.js`
- OpenCode auto-loads that directory, so installation does not modify
  `opencode.json`.
- The plugin accepts current and compatibility events, including
  `session.status`, `session.idle`, message/part/tool/todo events, legacy and v2
  permission/question events, and errors.
- Bridge delivery is asynchronous and ignores stdout/stderr. Missing Mac Island
  therefore cannot block OpenCode.
- The restart fallback reads only parent-row metadata from
  `~/.local/share/opencode/opencode.db`. It never queries message or part tables.
- That metadata schema does not identify the originating surface. Recovery uses
  `unknown` origin and shows “来源未知”; running OpenCode Desktop is not evidence
  that all database rows belong to Desktop. Navigation remains disabled until a
  live event identifies the surface; unknown rows are not routing associations.
- A live event consumes the matching native ID's unknown recovery card and keeps
  missing title/model/provider metadata. Live origin, working directory, state,
  activity and supplied metadata win. Already known CLI/Desktop cards remain
  separate. A recovery snapshot arriving after a known card is ignored, including
  while live event processing is suspended, so it cannot recreate a duplicate.

### Hermes

- Plugin: `~/.hermes/plugins/mac_island/`
- Installation uses `hermes plugins enable mac_island`; validation uses
  `hermes plugins doctor mac_island --ci`.
- Callbacks accept `**kwargs`, return `None`, and forward only interactive
  `cli`/`desktop` activity. They do not alter LLM, tool, approval, or subagent
  behavior.
- The restart fallback reads only parent-row title, source, model, provider,
  working directory, and last-activity metadata from `~/.hermes/state.db`.
- Selection, filtering and ordering all use
  `COALESCE(last_activity_at, started_at)`. A recent parent with a NULL activity
  field keeps its start timestamp instead of appearing as a 1970 session.

## Installation and rollback

- First launch never changes a client configuration. Installation is an
  explicit settings action, either per client or “install all”.
- Before every install, update, uninstall, or rollback, affected paths are
  backed up under `~/.mac-island/backups/integrations/<timestamp>/`.
- Writes are atomic. Repeated install/uninstall is idempotent.
- Uninstall removes only Mac Island-managed entries and files. It preserves
  unrelated Claude hooks, custom status lines, OpenCode configuration, and
  other Hermes plugins such as Vibe Island.

## Read-only recovery safety

`ObservedSessionRecovery` opens SQLite with the read-only flag and verifies an
explicit required-column set before querying. If either client changes its
schema, the fallback returns no rows instead of guessing. Live hook monitoring
continues independently. Both queries retain the 30-minute/20-parent bounds.
`ObservedSessionRecoveryTests` covers NULL timestamps, cutoff/ordering, schema
changes, child/non-interactive filtering, unknown routing and both event arrival
orders. These synthetic fixtures do not establish real-client UI acceptance.

## Primary protocol references

- [Claude Code hooks](https://code.claude.com/docs/en/hooks)
- [Claude Desktop Code](https://code.claude.com/docs/en/desktop)
- [OpenCode plugins](https://opencode.ai/docs/plugins/)
- [Hermes event hooks](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/hooks.md)
