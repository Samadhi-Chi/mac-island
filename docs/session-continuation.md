# Native session continuation

Implementation and contract check date: 2026-09-26. Related plan batches: 07–09.

## Delivered boundary

`SessionContinuationPreviewView` displays the client, exact native ID, working
directory, resolved executable, version, and command. Opening a preview only
performs local metadata and `--version`/`--help` checks. Copying uses the clipboard
and never starts a client. The confirmation button calls a separate action
service; monitoring, `monitorOnly`, hook installation, and the dormant writable
runtime are unchanged.

**All four production execution certifications are currently absent.** The
confirmation button stays disabled, and the service also rejects direct calls.
Documentation, help output, synthetic tests and a successful build are not real
session acceptance. There is no user preference that silently bypasses this gate.

The adapters generate exactly:

| Client | Arguments after the absolute executable |
| --- | --- |
| Codex CLI | `resume <native UUID>` |
| Claude Code CLI | `--resume <native UUID>` |
| OpenCode CLI | `--session <native ses_ ID>` |
| Hermes CLI | `--resume <native timestamp ID>` |

No prompt, permission override, fallback to “latest”, cross-client conversion or
saved input is added. Desktop, web, remote and unknown-origin records are rejected.
Hermes Desktop records therefore never become CLI commands. An active session or
a known live terminal asks the user to return to the original session first.

## Confirmation and execution

A preview token binds the exact target and command for five minutes. Confirmation
checks the current observed identity and working directory again, repeats version
and help checks, and compares the executable's resolved path/device/inode/size/time
and the working directory's identity. Linked worktrees must have a valid `.git`
pointer and Git HEAD. When `commondir` is present, its shared repository,
objects/refs directories and `gitdir` return link must also exist and identify
this worktree. The common directory and both link files are fingerprinted;
changes require a new preview. Expiration is checked again after asynchronous
validation, immediately before dispatch. Missing directories and
broken worktrees are not recreated automatically. Context-dependent `shims`
executables are rejected because their effective program can change with cwd.

A future certified version uses Terminal.app's `do script` without an existing
window target, opening a new window. Arguments use single-quote escaping, the
command is wrapped in fixed `/bin/zsh -f -c` syntax, and AppleScript string escaping
is applied independently. No input is injected into an existing terminal.

The service claims only **request submitted** after Apple Events succeeds.
Timeouts and errors can leave delivery uncertain; they do not authorize automatic
replay. A per-session guard remains until a later real observation acknowledges
activity. Neither a successful process exit nor a successful URL open proves that
the intended session is visible.

These checks reduce accidental stale-target launches but cannot lock an external
client's history or filesystem for the duration of its startup. Native clients
remain responsible for finding the ID and applying their saved session settings.
In particular, Hermes may restore its saved cwd, and Codex may ask which cwd to
use. The preview does not claim to override those client choices.

## UI integration

Inactive CLI records expose “续接预览” in their shared session menu. The action
opens `SessionContinuationWindowController`, one reusable native window shared by
current and recent records on both Island surfaces. Closing or replacing the
window cancels pending preparation. Its content is:

```swift
SessionContinuationPreviewView(session: selectedSession, onClose: dismissPreview)
```

Docked and detached surfaces use this same view/service. Models return
localization keys; the UI resolves all labels and feedback in the application
language (English or Simplified Chinese). Do not call `confirm`
from session events or startup. `SessionMonitor` passes hook/app-server activity
timestamps to `SessionContinuationService.shared.noteObservedActivity(sessionKey:at:)`;
metadata-only recovery does not clear a pending request. No user messages or tool
payloads are needed by this API.

## Verification

`SessionContinuationTests` is included in `scripts/test.sh`. It covers exact
arguments, native ID rejection, surface separation, version/help recognition,
production gates, shell/AppleScript quoting, missing directories, broken and
changed worktrees, explicit confirmation, changed targets, duplicate requests,
uncertain delivery, expiration during revalidation, cancellation, and probe
errors. Synthetic worktree fixtures cover a missing common repository and a
mismatched return link. The quoting test
executes only a temporary fixture executable with synthetic arguments. Terminal
and client launch behavior uses fakes.

Real client and UI acceptance remains separate; see
[client capability evidence](client-capability-evidence.md). To certify a version,
record a dedicated test session and exact version, verify the restored ID and
workspace in Terminal, ensure nothing was sent or approved, exercise permission
denial and duplicate clicks, then add the exact client/version pair to
`SessionContinuationExecutionPolicy.production` in a reviewed change. Never infer
certification from `--help` alone.

## Official command references

- [Codex interactive resume](https://learn.chatgpt.com/docs/developer-commands#codex-resume)
- [Claude Code CLI reference](https://code.claude.com/docs/en/cli-reference)
- [OpenCode CLI flags](https://opencode.ai/docs/cli/)
- [Hermes session resume and cwd behavior](https://hermes-agent.nousresearch.com/docs/user-guide/sessions)
