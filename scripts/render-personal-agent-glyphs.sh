#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER_BUILD_DIR="${BUILD_ROOT:-$ROOT_DIR/build}/personal-agent-glyphs.noindex"
OUTPUT_DIR="${1:-$ROOT_DIR/docs/images/client-glyphs}"
mkdir -p "$RENDER_BUILD_DIR/ModuleCache"
xcrun swiftc -parse-as-library -module-cache-path "$RENDER_BUILD_DIR/ModuleCache" \
    "$ROOT_DIR/PingIsland/UI/Components/MacIslandPersonalAgentPixelArt.swift" \
    "$ROOT_DIR/scripts/render-personal-agent-glyphs.swift" \
    -o "$RENDER_BUILD_DIR/render-glyphs"
"$RENDER_BUILD_DIR/render-glyphs" "$RENDER_BUILD_DIR/frames"
mkdir -p "$OUTPUT_DIR"
for name in mac-island-muse-pixel mac-island-grok-bot-pixel; do
    cp "$RENDER_BUILD_DIR/frames/$name.png" "$OUTPUT_DIR/$name.png"
    cp "$RENDER_BUILD_DIR/frames/$name.gif" "$OUTPUT_DIR/$name.gif"
done
