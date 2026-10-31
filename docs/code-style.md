# Code style and verification

Use `.editorconfig` for UTF-8, LF and final newlines. Swift/Python use four-space
indentation; website and workflow files use two spaces.

`.swift-format` defines a four-space / 120-column Swift baseline. All repository
Swift source, tests and scripts are included in `Config/SwiftFormatFiles.txt`.
The quality gate rejects an incomplete list, formatter diagnostics and parse
errors. Add new Swift files to that list. Xcode supplies the formatter:

```sh
xcrun swift-format format -i --configuration .swift-format path/to/File.swift
python3 scripts/check-quality.py
./scripts/test.sh
```

The 2026-10-31 migration formats the complete source tree, replacing the previous
two-file adoption list. Local formatting uses Xcode 27.1; CI uses Xcode 26.3.
Toolchain differences must be resolved in the source/configuration, not hidden
by suppressing diagnostics or accepting arbitrary warning counts.

The shared gate also validates JSON, Python syntax, shell syntax, plist/string
syntax, diff whitespace and the complete bilingual Pages payload. `bash -n` is
syntax-only; it is not ShellCheck. Website structural checks are not a full
accessibility audit. Dependency vulnerability auditing and security review are
separate coverage items, not implied by a green formatting check.
