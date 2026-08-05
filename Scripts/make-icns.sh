#!/usr/bin/env bash
#
# Builds resources/Vitrium.icns from the icon renderer.
#
#   ./Scripts/make-icns.sh [design]
#
# Every entry in the iconset is rendered natively at its own size rather than
# downscaled from one 1024px master — line weights and the caret survive at
# 16px that way, and turn to porridge otherwise.

set -euo pipefail

DESIGN="${1:-caret-mono}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONSET="$(mktemp -d)/Vitrium.iconset"

cleanup() { rm -rf "$(dirname "$ICONSET")"; }
trap cleanup EXIT

mkdir -p "$ICONSET"
cd "$ROOT"

# name:size pairs required by iconutil
for entry in \
	"icon_16x16:16" \
	"icon_16x16@2x:32" \
	"icon_32x32:32" \
	"icon_32x32@2x:64" \
	"icon_128x128:128" \
	"icon_128x128@2x:256" \
	"icon_256x256:256" \
	"icon_256x256@2x:512" \
	"icon_512x512:512" \
	"icon_512x512@2x:1024"
do
	name="${entry%%:*}"
	size="${entry##*:}"
	swift Scripts/make-icons.swift "$ICONSET/$name.png" "$DESIGN" "$size"
done

iconutil -c icns "$ICONSET" -o "$ROOT/resources/Vitrium.icns"
echo "Built resources/Vitrium.icns from '$DESIGN'"

# A 1024px master for the README and the release page.
swift Scripts/make-icons.swift "$ROOT/docs/icon.png" "$DESIGN" 1024
echo "Built docs/icon.png"
