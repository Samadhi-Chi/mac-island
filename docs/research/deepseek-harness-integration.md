# DeepSeek Harness integration notes

Date: 2026-08-19

This document records Mac Island's clean, observation-only integration with
DeepSeek Harness (DSH). It describes the public plugin surface and locally
observable behavior; it does not copy DSH implementation code or assets.

## Compatibility baseline

- Upstream: `deepseek-ai/deepseek-harness`
- Locally tested package: `@deepseek-ai/dsh` 0.1.0-rc.7
- Local executable: `~/.npm-global/bin/dsh`
- License: MIT
- Upstream status: Developer Preview. The plugin API may still introduce
  breaking changes, so this version is an acceptance baseline rather than a
  permanent pin.

## Product boundary

- Supported: interactive DSH CLI sessions and the DSH local Web UI.
- Excluded: cron and internal maintenance work.
- Mac Island observes status only. It never sends a prompt, changes context,
  answers a question, or decides an approval.
- Permission requests become `needsAttention` and immediately return control to
  DSH. Mac Island is not part of the approval decision path.
- The app displays bounded prompt/reply excerpts, tool names, task state,
  provider, model, origin, and the five most recent activity rows in memory.
- Tool arguments, complete tool results, credentials, and compressed session
  transcripts are not read or forwarded.

## Installation and rollback

- Generated plugin: `~/.dsh/plugins/mac-island/index.mjs`
- Global activation file: `~/.dsh/cordis.patch.yml`
- Activation ID: `mac-island-observer`
- Installation is disabled by default and occurs only after an explicit action
  in Mac Island settings.
- The installer adds one clearly marked YAML patch block. It preserves every
  unrelated patch row and comment, and repeated installation is idempotent.
- Uninstall removes only the marked Mac Island block and managed plugin
  directory. If no YAML values remain, the file is restored to a valid empty
  array.
- Every change participates in the normal integration backup flow under
  `~/.mac-island/backups/integrations/<timestamp>/` and uses atomic writes.

## Event projection

The generated ESM plugin uses DSH's public `ctx.on(...)` event surface:

- Agent lifecycle: `agent/created`, `agent/session-start`, `agent/status`,
  `agent/error`, and `agent/disposed`.
- Session stream: `session/event` carrying user/assistant messages, turn and
  step lifecycle, tool call/result, todo updates, and approval requests.
- User text is accepted only when `source.kind == "user"`, avoiding system or
  synthetic messages being presented as a user prompt.
- Tool activity forwards only the tool name, native call ID, and compact state.
- Child agents are folded into their root DSH session instead of creating
  duplicate cards.
- Bridge delivery is detached, asynchronous, and discards stdout/stderr. A
  missing Mac Island process therefore does not delay or fail DSH.

## Identity, UI, and launch behavior

- Stable identity is `dsh + native session ID + origin`.
- Origin is `cli` when a terminal/TTY is present and `web` for the local Web UI.
- The card title follows the existing `project · thread` rule.
- The DSH glyph is an original blue pixel-wave mark; it moves only while the
  session is `working` and respects Reduce Motion and Mac Island's energy tier.
- CLI cards use captured terminal metadata for jump-back. Local Web cards open
  the recorded loopback URL. If a precise target is unavailable, launch
  behavior degrades to the corresponding DSH surface rather than inventing a
  session deep link.
- DSH currently exposes no trusted quota snapshot to this integration, so
  remaining usage displays `—` instead of an inferred percentage.

## Verification

The DSH-focused tests cover profile configuration, public event coverage,
sensitive-field exclusion, YAML preservation and idempotency, CLI/Web policy,
session identity, and working-only animation. Release acceptance additionally
requires the repository-wide `./scripts/test.sh` gate, generated-plugin syntax
validation, managed install health, and a launch check of the installed app.

## Primary reference

- [DeepSeek Harness official repository](https://github.com/deepseek-ai/deepseek-harness)
