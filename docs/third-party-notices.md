# Bundled notices and offline documents

Mac Island retains the upstream Apache 2.0 `LICENSE.md` and `NOTICE` unchanged.
The bundled `MacIsland-ThirdPartyNotices.txt` adds a prominent fork modification
statement, then includes the complete original texts. It does not replace their
license terms or imply that the upstream project supports Mac Island.

## Inventory

| Component | Source | Bundled coverage |
| --- | --- | --- |
| Ping Island / Mac Island | Root `LICENSE.md` and `NOTICE` | Complete Apache 2.0 license and original NOTICE, plus separate fork modification statement |
| Silkscreen Bold | `PingIsland/Resources/Fonts/Silkscreen-OFL.txt` | Complete copyright and SIL OFL 1.1 |
| Sparkle 2.10.1 | Locked revision `ab7d71291238df6e0492143b120c9b696a35f603`; SPM binary artifact `LICENSE` | Complete Sparkle notice and external notices for bsdiff/bspatch, sais-lite, Ed25519, and SUSignatureVerifier |

The Sparkle binary artifact is declared by the locked package's `Package.swift`
at [the 2.10.1 package revision](https://github.com/sparkle-project/Sparkle/blob/ab7d71291238df6e0492143b120c9b696a35f603/Package.swift).
Its declared archive SHA-256 is
`4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a`.
The archive's full LICENSE was copied without editing. The bundled manifest
records each license section's digest and the dependency pin; it contains no
machine identity, signing information, or credentials.

Sparkle is linked in the regular target even while product policy disables its
update service. The App Store target does not link Sparkle. The same legal
document can ship in both targets and explicitly explains that distinction.
An unused dependency's retained notice does not authorize enabling its service.

The inventory covers the app's identified bundled software/font dependencies.
Client names identify interoperability, not endorsement. New dependencies,
redistributed assets, and future artwork need their own provenance review; a
passing consistency check cannot determine trademark rights or discover every
unrecorded license obligation.

The silent Mac Island product no longer redistributes the 13 inherited WAV
notification sounds. Their per-file provenance was not completely established,
and the product does not use them. Retained sound identifiers preserve settings
compatibility; they do not imply bundled audio or an enabled sound feature.
Historical sound archives are not part of the current source or website payload
and must remain within the separately reviewed history-disclosure scope.
The verifier rejects notification audio in both source resources and the built
app so an old build cache cannot silently reintroduce it.

## Resource integration

The shared `PingIsland` file-system-synchronized Xcode group includes
`PingIsland/Resources/Legal/`. No target exclusion applies to these files. Their
unique basenames avoid collisions if Xcode flattens resource folders:

- `MacIsland-Privacy-zh-Hans.md`
- `MacIsland-Privacy-en.md`
- `MacIsland-Help-zh-Hans.md`
- `MacIsland-Help-en.md`
- `MacIsland-ThirdPartyNotices.txt`
- `MacIsland-Legal-Manifest.json`

The app's About screen reads the policy, help, and notices offline. It must not
substitute upstream issue/download links for Mac Island support. The manifest is
provenance metadata for verification rather than a user-facing policy.

The current policy is maintained directly in these resources; the
[policy index](privacy-policy.md) links to both languages. The
[historical upstream policy](history/ping-island-privacy-policy-2026-05-05.md) is
kept outside the app resources and clearly labeled historical.

## Unified validation

Run these checks after implementation, with the product's consolidated gate:

```sh
python3 scripts/verify-distribution-legal.py
python3 scripts/verify-distribution-legal.py \
  --app "$BUILD_ROOT/DerivedData/Build/Products/Release/Mac Island.app" \
  --sparkle-license "$BUILD_ROOT/SourcePackages/artifacts/sparkle/Sparkle/LICENSE"
```

Use the actual build's path when Xcode places products or package artifacts
elsewhere. The script reads only; it does not build, install, sign, notarize, or
publish. The source check rejects a changed dependency inventory/pin or stale
license text. The app check verifies that every document occurs exactly once
and matches the source bytes. The artifact option compares the included Sparkle
notice to the actual resolved binary artifact rather than only the Git checkout.

When changing an included license or dependency, copy the complete license text
from that exact version, retain all copyright/notice sections, update the
manifest and this inventory, and review the resulting diff. Do not update a
digest merely to make a check pass. Public distribution also needs an accessible
current privacy-policy page and this product's support contact; neither is
invented by these offline resources.
