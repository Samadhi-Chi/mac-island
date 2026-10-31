# Mac Island publication review — 2026-10-31

[简体中文](public-readiness-2026-10-31.md) · **English**

## Pre-migration review snapshot

This record preserves the review state before the clean repository was created.
Old SHAs, PR #39 and Issue #40 belong to the private archive, not this repository.
See [source history](source-history.md), current
[CI](https://github.com/Samadhi-Chi/mac-island/actions/workflows/pr-checks.yml) and
[Pages deployments](https://github.com/Samadhi-Chi/mac-island/actions/workflows/pages.yml).

The single-pass source review is complete and repairs are implemented in the
working candidate. **The repository remains private; Pages is not deployed.**
Private screenshots remain reachable in Git history. Deleting current files
does not make that history safe to publish. Final-head CI, history isolation and
publication settings remain pending. The maintainer approved retaining a private
archive and creating an independent same-name repository from reviewed source,
without rewriting shared history.

The baseline is `ae412ab9aa04fc48d956f41cc15df6689fcfcc8f` on
`codex/mac-island-release-readiness`; changes remain uncommitted. Default main is
`97db382ea72bcd42b1c329f97de4a160f21d9eb2`. Draft PR #39 carries implementation
and Issue #40 tracks publication. Source, Pages and binary release are separate gates.

## Review and repairs

The maintainer stopped the stalled deep scan and selected one complete Standard
review. Completed scan `118c1c2a-079c-4417-b86f-c4d8963f80d2` covers all 660 tracked
baseline files and records 17 validated findings: 4 medium and 13 low. The sealed
result is preserved; repairs do not retroactively make it a zero-finding scan.
Detailed evidence and follow-up reports remain outside the repository.

Changes cover monitor-only approval boundaries, private owned stdio, bounded
process shutdown/file reads, exact session identity, script arguments, logging
and retention, numeric validation, test isolation and local network policy.
One independent investigation and one candidate review were performed. The
review's quota alias/cache and legacy log-retention findings were repaired and
their affected tests pass.

| Scope | Evidence and limits |
| --- | --- |
| Current source | Gitleaks 8.30.1 found no matching credentials in the exported candidate; refresh the exact manifest when final assets are added |
| History | 46 refs, 582 commits, 3,788 unique blobs; commit diffs and all 3,330 text blobs (about 105.5 MB) scanned without matching credentials |
| Archives | ZIP/7z inventories and extracted text checked without executing files; no matching credentials |
| Images | Historical image versions reviewed through deduplicated previews; GIF first/middle/last frames sampled. Five private or unreviewed images removed from the current tree, still reachable in history |
| GitHub text/logs | 21 issues, 19 PR bodies and retrieved comments; about 0.92 MB metadata and 14.36 MB logs across 51 runs scanned. Automated checks are not sentence-by-sentence privacy review |
| CI artifacts | Eight diagnostic archives verified, privately backed up and deleted; remote inventory now zero. Future retained summaries contain only fixed numeric fields |
| Dependencies | Sparkle 2.9.1 upgraded to pinned 2.10.1 with verified archive checksum and complete notices; automatic updates remain disabled |
| Assets | Original Apache LICENSE/NOTICE and font terms retained. Thirteen unused inherited WAVs with incomplete individual provenance removed; source/bundle checks reject their return. Historical assets need a separate disclosure decision |

Dependency evidence: [official advisories](https://github.com/sparkle-project/Sparkle/security/advisories)
and [the exact package revision](https://github.com/sparkle-project/Sparkle/blob/ab7d71291238df6e0492143b120c9b696a35f603/Package.swift).
A clean credential scan cannot certify privacy, licensing or absence of vulnerabilities.

## Validation

Local checks used Apple Silicon / Xcode 27.1; CI uses macOS 15 / Xcode 26.3.
Checks ran after implementation; only affected checks reran after repairs.
The separately executed components are not described as a successful invocation
of the complete `scripts/test.sh`, which awaits website assets and final CI.

- Strict formatting passed for all 342 Swift files.
- The repaired Release build and the build after retiring audio passed without
  source warnings. A fresh output directory passed license checks with no legacy
  WAV files, and the dedicated bundle-resource regression passed (1 test).
- Explicit language selection now loads the selected resource bundle. All 49
  language, screen-privacy and settings tests passed; the latest Release build
  and license checks passed with no source compiler warnings.
- The first product run had 704 tests: 691 passed, 12 failed, 1 live Cursor test
  intentionally skipped. After temporary-path canonicalization and assertion
  repairs, all 63 tests in the six affected suites passed.
- The first Prototype run had one obsolete assertion failure among 139 tests.
  Both affected IDE tests passed after correction. Later Bridge retention checks
  passed all 11 tests, including new regressions.
- All 15 release-tool fixtures and source/built-bundle license checks passed.
- An actual Codex CLI passed initialize/initialized/empty thread-list and child
  shutdown over stdio with isolated HOME/CODEX_HOME and no network/account data.
  This does not certify live signed-in sessions.
- Generated IDE setup/statusline handlers passed synthetic normal and hostile
  input/symlink checks. No real IDE was installed or invoked; unrelated chat
  strategy substitutions were outside the harness.
- Actual xcresult exports contain only schema, summary availability and four
  numeric counts, without names, failures, paths or diagnostics.
- First final-candidate CI at `037c4e9`: all 141 Prototype tests passed; product
  tests had 708 passes, one failure and one intentional skip out of 710. The
  owned-process fixture now uses POSIX tools instead of the system Python shim;
  its affected lifecycle suite passes locally. The Xcode 26.3 enum-conformance
  isolation warning is repaired and awaits new-head CI. Because GitHub artifact
  quota has not refreshed, numeric counts now go to Job Summary without uploads.
- All 12 pages passed structural/resource/link checks. Browser checks at 1280px
  and 390px covered language switching, guides and keyboard skip navigation, with
  no horizontal overflow and all six captures loaded. Hosted project-path 404
  and final PR/main CI remain pending. No app installation, signing, notarization or binary release
  occurred, nor minimum-OS/Intel, sleep/wake, multi-display or signed Muse/Grok acceptance.

Private logs are in ignored `build/PublicationChecks/` and `build/TestResults/`;
never publish these directories.

## Verified delivery addendum

The repaired final PR head `79a52bd` passed the complete gate in archive run
[41198267999](https://github.com/Samadhi-Chi/mac-island-private-archive/actions/runs/41198267999).
GitHub Desktop then squashed and pushed the identical tree as `10d925f`; its
[main run 41198728266](https://github.com/Samadhi-Chi/mac-island-private-archive/actions/runs/41198728266)
also passed: 141 Prototype tests, 15 distribution fixtures, 709 product tests
passed and one intentional live Cursor test skipped. Release, license, strict
format and site checks passed with no source compiler warnings. These private
archive runs are provenance; the independent repository has its own new CI.
The pending items above describe the earlier review snapshot, not this addendum.

## Website and publication gates

README, offline help/privacy and the website have Chinese/English versions.
Six corresponding pages per language use local CSS and no third-party scripts,
fonts, analytics or invented download links. Images must be real native-window
captures with isolated synthetic fixtures. Cropping/layout is allowed; simulated
UI cannot replace captures. All six captures have been checked for private
content; build, fixture, language and crop details are in
[screenshot provenance](website-screenshots.md).

Before publication:

1. Commit/push through GitHub Desktop; verify the final PR head and merged main CI.
2. Execute the approved private-archive/clean-repository plan. Preserve the old
   history and PRs privately, import only reviewed source into the independent
   repository, and verify its new CI. Issue/PR numbering restarts. Private images,
   unreviewed sound archives and runtime outputs stay outside public history;
   detailed cleanup targets remain private.
3. Configure and verify private vulnerability reporting, branch rules and available
   secret/dependency protection. Unverified capabilities remain pending.
4. Only after disclosure blockers are resolved, publish the repository, configure
   Pages to use Actions, deploy only `site/`, then verify HTTPS, project paths and 404.

PR refs and caches also affect history cleanup; force-pushing is not proof of
complete removal. See [sensitive-data removal](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)
and [visibility changes](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility).

The site was not yet live at this review snapshot. Project URL:
`https://samadhi-chi.github.io/mac-island/`.
See [Pages instructions](github-pages.md) and [binary release readiness](mac-island-release-readiness.md).
