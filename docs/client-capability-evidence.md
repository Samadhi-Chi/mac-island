# Client capability evidence

Checked 2026-09-26. This record distinguishes local package/command inspection
from actual session navigation. No user session was resumed, no message was
sent, and no hooks, permissions or client configuration were changed.

## Priority desktop clients

| Client | Local package evidence | Navigation boundary | Real session acceptance |
| --- | --- | --- | --- |
| Codex Desktop | Application named `ChatGPT.app`, bundle `com.openai.codex`, version `26.924.22138` / build `11645`; registers `codex` | Official `codex://threads/<ID>` route; OS acceptance is only a request | Not performed |
| Cursor | No matching package found under standard system/user Applications directories | Existing Island project/terminal routing is retained; this inspection establishes no composer-ID route | Not performed; installed version unavailable |
| Hermes Desktop | Bundle `com.nousresearch.hermes.setup`, package version/build `0.0.1`; no `CFBundleURLTypes` entry | Application activation and metadata recovery; no verified external exact-session route for this package | Not performed |

Hermes's package version is the launcher package's value and must not be confused
with the CLI/core version. The missing URL registration describes this package,
not all Hermes releases. The official Desktop documentation describes shared
session state, but that is not evidence of an external deep link for an exact ID.
The [official Desktop description](https://hermes-agent.nousresearch.com/docs/user-guide/desktop)
and [Codex command routes](https://learn.chatgpt.com/docs/reference/commands)
were consulted. [Cursor's documented deeplinks](https://prod.cursor.com/docs/reference/deeplinks)
cover sharing prompts, commands and rules; no existing-composer route was
established by that reference. These routes are not executed during this check.

## CLI contract checks

Only `--version` and `--help` / `resume --help` were run, outside a project folder.
Outputs below contain version/contract facts only; personal install paths and
configuration were not copied into the repository.

| Client | Observed version | Advertised contract | Execution certification |
| --- | --- | --- | --- |
| Codex CLI on PATH | `0.156.0` | `codex resume [OPTIONS] [SESSION_ID] [PROMPT]` | None |
| Codex CLI bundled in the desktop app | `0.158.0-alpha.2.1` | `codex resume [OPTIONS] [SESSION_ID] [PROMPT]` | None |
| Claude Code CLI | `2.1.267` | `-r, --resume [value]` | None |
| OpenCode CLI | `1.18.32` | `-s, --session` | None |
| Hermes CLI | `0.21.4` | `--resume SESSION, -r SESSION` | None |

The installed Codex PATH entry is a version-manager shim. The continuation
resolver uses direct executables, including the desktop bundle's current
`Contents/Resources/codex-cli/bin/codex` layout and older resource layout where
available, and checks whichever actual version is selected. It does not treat a
PATH version as proof of the bundled executable's version.

The Codex CLI version probe returned a warning that it could not create PATH
aliases in the restricted environment; its version/help command exited normally.
No alias configuration was changed for this check.

## Outstanding real acceptance

For each supported desktop, verify a dedicated session from docked and detached
Island, including closed application, multiple windows, missing target, denied
Automation/Accessibility permissions, and sleep/wake. Record actual target
identity and the observed result category, not merely that the application opened.

For each CLI, verify a dedicated inactive session in a valid project and worktree,
confirm the original ID is restored, and verify no prompt, approval-policy change
or replay was introduced. Include deleted cwd, changed binary/version, missing
session, repeated clicks, cancelled preview and no-receipt behavior. The normal
test gate uses fakes and does not replace these checks.

Until those records exist, all CLI adapters support preview/copy only. This
matrix is not a declaration that plan batch 07's real UI acceptance is complete.
