# Security policy

Mac Island is a local, monitor-only development project. There is no supported
public binary release yet. Successful tests or notarization do not certify that
the software is free of vulnerabilities.

## Reporting a vulnerability

Do not put vulnerability details, exploit steps, private conversations, paths,
credentials or raw diagnostics in public issues or pull requests.

Use **Report a vulnerability** on this repository's
[Security page](https://github.com/Samadhi-Chi/mac-island/security). If that button
is absent, do not submit confidential details publicly. This community project
does not currently promise a response deadline or a paid bounty.

## Scope and useful evidence

Reports about hook/socket ingress, local file handling, command construction,
cross-application navigation, private content persistence/export, dependencies
and the distribution pipeline are relevant. Include the commit/version,
macOS/client versions, affected path and a minimal reproduction using synthetic
data. Never test against other users or change live client configuration to
demonstrate an issue.

Retained upstream capabilities are not all enabled in Mac Island. Explain whether
the finding is reachable under `MacIslandProductPolicy` and current feature
flags. Lack of reachability is not permission to expose a secret in source.

## Maintainer publication gate

Before changing visibility, review the complete reachable Git history, branches,
tags, screenshots, issues/PRs, Actions logs and artifacts. Removing a file in a
new commit does not remove earlier versions. Rotate any exposed credentials
before considering history cleanup; rewriting shared history requires a separate
reviewed plan.

Record scanner version, exact revision, exclusions and actual coverage. A scan
that failed before discovery, or an unavailable dependency advisory service,
must remain incomplete. Keep detailed vulnerability evidence private until a
coordinated fix and disclosure decision are ready.
