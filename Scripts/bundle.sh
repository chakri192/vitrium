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

# Universal binary for release builds, so the app runs on Intel Macs too.
#
# `swift build --arch arm64 --arch x86_64` would be the obvious way, but that
# route needs xcbuild, which only ships with Xcode. Building each slice into its
# own scratch directory and lipo-ing them works with Command Line Tools alone.
if [[ "$CONFIGURATION" == "release" ]]; then
	HOST_ARCH="$(uname -m)"
	OTHER_TRIPLE="x86_64-apple-macosx13.0"
	[[ "$HOST_ARCH" == "x86_64" ]] && OTHER_TRIPLE="arm64-apple-macosx13.0"

	echo "Cross-building ${OTHER_TRIPLE%%-*} slice…"
	if swift build -c "$CONFIGURATION" --product Vitrium \
		--scratch-path "$ROOT/.build-cross" \
		-Xswiftc -target -Xswiftc "$OTHER_TRIPLE" >/dev/null 2>&1
	then
		CROSS="$(swift build -c "$CONFIGURATION" --product Vitrium \
			--scratch-path "$ROOT/.build-cross" \
			-Xswiftc -target -Xswiftc "$OTHER_TRIPLE" --show-bin-path)/Vitrium"
		UNIVERSAL="$ROOT/.build-cross/Vitrium-universal"
		lipo -create "$BINARY" "$CROSS" -output "$UNIVERSAL"
		BINARY="$UNIVERSAL"
		echo "Universal: $(lipo -archs "$UNIVERSAL")"
	else
		echo "note: cross-build failed — shipping $HOST_ARCH only"
	fi
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
