#!/usr/bin/env bash
#
# Builds Vitrium and assembles Vitrium.app.
#
#   ./Scripts/bundle.sh            release build (default)
#   ./Scripts/bundle.sh debug      debug build
#
# There is no Xcode project on purpose — Command Line Tools plus SwiftPM is
# enough to build an AppKit app, and the bundle is just a directory.

set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Vitrium.app"

cd "$ROOT"

echo "Building ($CONFIGURATION)…"
# Only the app product. The test runner uses `@testable import`, which needs
# `-enable-testing` — a debug-only flag, so building it in release would fail.
swift build -c "$CONFIGURATION" --product Vitrium

BINARY="$(swift build -c "$CONFIGURATION" --product Vitrium --show-bin-path)/Vitrium"
if [[ ! -x "$BINARY" ]]; then
	echo "error: no binary at $BINARY" >&2
	exit 1
fi

echo "Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Lowercase `resources/` is the real directory name — spelling it `Resources/`
# happens to work on case-insensitive APFS and breaks everywhere else.
cp "$BINARY" "$APP/Contents/MacOS/Vitrium"
cp "$ROOT/resources/Info.plist" "$APP/Contents/Info.plist"
[[ -f "$ROOT/resources/Vitrium.icns" ]] && cp "$ROOT/resources/Vitrium.icns" "$APP/Contents/Resources/Vitrium.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature. Without it macOS treats each rebuild as a different app and
# re-asks for permissions (and refuses to keep Accessibility-style grants).
codesign --force --sign - --timestamp=none "$APP" 2>/dev/null || \
	echo "note: ad-hoc codesign unavailable — the app still runs"

echo "Built $APP"
