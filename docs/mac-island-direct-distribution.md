# Mac Island direct distribution

This lane prepares a Developer ID candidate for distribution outside the Mac App
Store. It does not publish a release, update a website, install an application,
change repository visibility, create certificates, or modify client settings.
Manual updates remain the product policy; no Sparkle feed or update check is
enabled by this work.

The App Store target is separate. Its existence is not evidence that the current
cross-application observation product is sandbox-compatible or approved by Apple.

## Prerequisites

- A reviewed, committed, clean source checkout with the product gate and required
  GitHub checks passing at that commit. The packaging script checks cleanliness,
  not GitHub review approval; the release operator must verify the exact commit's
  checks and acceptance record.
- A stable bundle identifier for this product, developer Team ID, and a usable
  **Developer ID Application** signing identity in Keychain. Membership enrollment
  alone does not create this identity. Keep private keys/certificates out of Git.
  Preserve the existing Mac Island identifier, including a `local.` prefix if
  that is its established identity, unless a separate migration plan is approved.
  A prefix alone does not determine release readiness. Placeholder identifiers
  and the original upstream product identifier are rejected. Changing the ID can
  separate preferences, login items, metadata, and system permission identity;
  it must not be done merely to make the name look more like a public product.
- A previously configured `notarytool` Keychain profile. The script references its
  name and never accepts an Apple ID password, private-key path, or API secret.
- Real publicly accessible HTTPS support and current privacy-policy pages. A
  separate website landing page is optional. A private repository, placeholder
  URL, or this project's upstream support page is not a substitute for this
  product's support route. The operator must review the page contents; an HTTP
  success response proves availability, not policy accuracy or ownership.
- The last distributed version/build and its manifest, or an explicit declaration
  that this is the first public release. Build numbers must increase; version
  numbers must not go backwards. For a first release, set the previous floor to
  the latest installed/distributed development version, not zero.
- Xcode with the existing project-required toolchain and access to the exact
  dependencies locked in `Package.resolved`.

This preparation work has not created a signing identity or notarization profile,
and has not confirmed the stable release identity or public support/privacy
pages. Missing prerequisites deliberately stop the lane. A local ad-hoc build is
not an alternative public-distribution artifact.

## Local configuration and preflight

Copy `Config/Distribution.example.json` to an ignored location such as
`build/release-settings.json`, and fill in actual values. The example intentionally
has empty identity/contact fields and build number zero so it cannot produce a
misleading release. Store only certificate/profile references, never credentials.
Do not commit the completed machine-specific configuration.

For the first public release:

```sh
python3 scripts/prepare-mac-island-release.py \
  --config build/release-settings.json \
  --first-public-release
```

For later releases, replace `--first-public-release` with
`--previous-manifest /path/to/last-distributed/manifest.json`. These options are
mutually exclusive. The receipt must match the configured product and previous
version/build. This is a local release ledger check, not a query of a public
download service; do not use an unpublished candidate as the public release floor.

The default action is read-only preflight: validate fields, stable product identity,
version progression, receipt consistency, clean source, available signing identity,
license resources, and the local/monitor-only/no-telemetry/no-update policy. It
does not build, sign, upload, install, write a receipt, or contact the configured
pages. Public-page reachability and notarization authentication are checked only
during explicit execution.

## Explicit candidate preparation

After release authorization and prerequisite setup, append `--execute`:

```sh
python3 scripts/prepare-mac-island-release.py \
  --config build/release-settings.json \
  --first-public-release \
  --output build/distribution/first-candidate \
  --execute
```

This command **uses the signing identity and uploads the candidate to Apple's
notary service**. Development/test authorization alone does not authorize running
it. It does not make the candidate publicly downloadable.

The output directory must be new. The tool does not clean or overwrite an
existing candidate. By default it uses `build/distribution/<version>-<build>`;
an output inside the repository must remain under ignored `build/`. External
output must have no other Git checkout/worktree in its resolved parent chain;
existing or dangling output symlinks are rejected. Failed
preparation retains its local evidence and `INCOMPLETE.txt`; those files are not a
usable release. Choose another output directory after reviewing a failure.

The lane performs these steps:

1. Check public page availability, then build the `MacIsland` Release scheme for
   Apple silicon and Intel with the configured identity/version, hardened runtime,
   timestamps, and locked package versions.
2. Copy the app into the candidate directory and add its support/privacy/optional
   website URLs and source commit/tree to Info.plist **before final signing**.
3. Verify the actual built app's offline documents and complete third-party
   notices, including the resolved Sparkle artifact's license.
4. Sign individual Mach-O code and enclosing bundles from inside out, preserving
   embedded entitlements and explicitly using the main app's entitlements.
   Signing does not use `--deep`. Verify every component's signature, Team ID,
   Developer ID authority, secure timestamp, hardened runtime, required
   architectures, and absence of `get-task-allow`. Verify the complete app seal.
5. Submit the app archive for notarization and require the exact `Accepted` state;
   staple and validate the app ticket, then require Gatekeeper assessment to pass.
6. Create a ZIP of the stapled app and a simple DMG with an Applications shortcut.
   Sign, notarize, staple, and validate the DMG; a failed Gatekeeper assessment
   stops preparation rather than becoming a warning.
7. Extract the final ZIP to a new verification directory and mount the final DMG
   read-only without opening Finder. Check the application actually contained in
   each artifact: its complete file/symlink inventory must match the signed,
   stapled source app; identity/version metadata and legal resources must match;
   nested code signatures, runtime/timestamp/entitlements, ticket, and Gatekeeper
   assessment must pass again. Verification does not re-sign packaged copies.
   Detachment runs in a bounded `finally` path, including after payload failures.
   A detach failure stops the candidate and leaves its owned directory intact
   rather than recursively deleting a possibly mounted volume. Verify that the
   artifact digests did not change during inspection.
8. Recheck source identity/cleanliness, then write `manifest.json` and
   `SHA256SUMS` for the final ZIP and DMG. The receipt contains source and public
   product metadata, artifact digests and notarization IDs, without key material
   or certificate identity details. Local stage logs remain in the ignored output.

Apple's guidance covers [distribution signing](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)
and [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
The lane's checks do not substitute for Apple's service results or real-device
acceptance. It does not remove quarantine or instruct users to bypass Gatekeeper.

## Final acceptance and publication

A `verified_candidate` receipt means these packaging checks passed. It does not
mean public release approval. Using the same exact artifacts, still verify:

- Download and launch through the normal quarantined installation path on a
  separate supported Mac/user environment, including the minimum supported OS.
- Upgrade from the intended previous app identity and verify preferences,
  metadata, integration routing, login items, and permission continuity. A new
  production bundle ID is an identity migration, not proof of seamless upgrade.
- Supported clients, window navigation, permission recovery, sleep/wake, displays,
  keyboard/VoiceOver, and sustained energy behavior.
- Published privacy/support content, version/release notes, artifact digests, and
  a rollback/download retention policy.

Record limitations and unrun checks. Publish only the reviewed final ZIP/DMG and
their public receipt after explicit publication authorization. Do not upload
local configuration, DerivedData, stage logs, or signing material. This tool has
no publish option and never changes another repository.

## Development verification

The consolidated development gate can run:

```sh
python3 scripts/test_prepare_mac_island_release.py
python3 scripts/verify-distribution-legal.py
```

These fixtures cover release boundaries with synthetic values and temporary
files. They do not use a real identity, Keychain profile, client, network service,
or app build. Separately run the legal verifier against the Release app produced
by the shared gate. No fixture success certifies actual signing or notarization.

The retained upstream `build.sh`, `package-release.sh`, `package-unsigned.sh`, and
`create-release.sh` stop early in this fork and point to the new lane. They cannot
silently delete prior build directories, enable an update feed, publish to the
private source repository, or commit a neighboring website. Use `scripts/test.sh`
for development builds; the legacy unsigned publishing path is not supported.
