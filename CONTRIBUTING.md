# Contributing to Mac Island

This independent source fork ships Mac Island. Read [AGENTS.md](AGENTS.md) and the current
product section of [README.md](README.md) before changing it. Retained upstream
features and release scripts are not the supported product contract.
The current public-distribution preparation and acceptance record is
[release readiness](docs/mac-island-release-readiness.md).

Source publication and binary distribution are separate. Ordinary bugs
use the issue template; security details follow [SECURITY.md](SECURITY.md).
Contributors may use their normal Git client; the maintainer's local delivery
workflow below uses GitHub Desktop. Follow [code style](docs/code-style.md) and
keep synthetic fixtures, credentials and machine-specific settings separate.
The website is documented in [GitHub Pages](docs/github-pages.md).

## Issues, branches and pull requests

Track a concrete problem and acceptance criteria in a new issue. Historical
iteration records remain in the private archive; they are not new-repository
issue numbers. See [source history](docs/source-history.md) and the historical
[iteration plan](docs/mac-island-iteration-plan.md).

Start a focused `codex/mac-island-<topic>` branch from the latest `main`. Preserve
unrelated local work. Keep commits reviewable (`fix:`, `feat:`, `test:`, `docs:` or
`chore:`) and include only files belonging to the issue. Open a draft PR after
implementation and targeted checks; describe the resulting behavior, evidence,
limitations and rollback. Link the issue with `Closes #…` only when its acceptance
criteria are met. Do not skip CI for product changes.

Before merging, inspect the final diff, resolve review threads, and verify that
the latest PR head has a successful `Mac Island Checks / validate` run and no
other required or failing checks. Revalidate after changes to the head or base.
Squash merge, then check the resulting `main` run before starting the next batch.
If a regression appears, pause dependent work and use a reviewed revert PR;
never rewrite shared history or bypass repository rules.

Use the maintainer's GitHub Desktop workflow for local branches, commits,
synchronization and merges. Read-only Git inspection may use the terminal.
Source-control delivery is distinct from publishing an application: a merged
PR or tag does not authorize an installation or a public download.

Repository protection and native auto-merge depend on GitHub permissions and
plan support. When unavailable, the authorized maintainer/agent must apply the
same gate and merge with an expected head SHA. This is a procedural safeguard,
not server-enforced branch protection. Do not change repository visibility or
purchase a plan to enable these features.

## Validation

Use `./scripts/test.sh` from the repository root. It builds the bridge, runs
serial Prototype tests, builds Mac Island Release and runs the product test
selection listed in that script. `BUILD_ROOT` chooses an ignored/external build
directory; `BUILD_JOBS` defaults to 2. Xcode 26.3 is the CI toolchain; Xcode 26+
with Swift 6.2+ default actor isolation is required for the app.

Add focused regression coverage for changed behavior and include relevant suites
in the shared gate. Pure documentation changes need link, path and consistency
checks. Test records must distinguish static review, fixtures, automated tests,
builds and real client/device checks. Record unrun checks and why. A URI accepted
by macOS is not proof that the intended conversation appeared.

For the current release-preparation iteration, finish the authorized changes
before one consolidated gate. Add regressions while developing, then run the
shared gate and applicable resource/package checks together. Rerun affected
checks only after a failure, repair or new change warrants it. Keep verification
marked pending until actually performed; historical passes are not evidence for
the new candidate.

Use synthetic databases and generic example paths. The gate disables live
Cursor database tests. Keep prompts, replies, tool bodies, credentials, signing
identities, user configuration and build artifacts out of Git and CI summaries.

## Runtime and release boundaries

Development and build authorization does not install the app, enable hooks,
change client configuration, sign, notarize or publish. Integrations remain
explicit user actions with backups and atomic writes. Mac Island remains local,
silent, and observational. Navigation and explicitly confirmed native CLI
continuation do not enable the legacy writable runtime or agent approvals.

Candidate preparation separates a read-only preflight from explicit execution.
Execution requires the actual release identity/configuration and may submit an
artifact to Apple for notarization. It must not install the app, create a public
Release or publish downloads. Credentials, identity files and candidate outputs
remain outside Git. The disabled upstream release workflow stays disabled.

Shipping a candidate also requires complete bundled licenses, offline help and
privacy information, real compatibility/permission checks, and an actual public
support/privacy destination before public distribution. Do not invent a domain
or use upstream contact/download links. The retained App Store lane is an
evaluation reference; sandbox adaptation and submission are separate work.

Every major feature updates AGENTS.md and affected documentation. Both docked
and detached surfaces share action semantics, including failure feedback.
