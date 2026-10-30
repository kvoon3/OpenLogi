#!/bin/sh
# Assemble a runnable OpenLogi.app from this fork's release binaries.
#
# `cargo xtask macos bundle` is the supported path, but it shells out to `actool`
# (Xcode 26's Icon Composer compiler) and to `xcrun` under Xcode, so it cannot run
# on a Command Line Tools-only Mac. This script borrows the *layout* of the
# installed upstream bundle — Info.plists, icons, the LaunchAgent that starts the
# agent, the nested helper apps — and swaps in this fork's four binaries.
#
# The result is ad-hoc signed: fine for local use, not for distribution.
# Replacing the app changes its code signature, so macOS asks for Accessibility
# and Input Monitoring again (System Settings ▸ Privacy & Security).

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=${OPENLOGI_TEMPLATE_APP:-/Applications/OpenLogi.app}
OUT=$ROOT/dist/OpenLogi.app
BIN=$ROOT/target/release

for binary in openlogi-desktop openlogi openlogi-agent openlogi-overlay; do
	if [ ! -x "$BIN/$binary" ]; then
		echo "missing $BIN/$binary" >&2
		echo "build it first:" >&2
		echo "  OPENLOGI_UPDATE_BASE_URL=https://updates.invalid \\" >&2
		echo "    cargo build --release -p openlogi-desktop -p openlogi-overlay -p openlogi-agent -p openlogi" >&2
		exit 1
	fi
done

if [ ! -d "$SRC" ]; then
	echo "template bundle not found: $SRC" >&2
	echo "set OPENLOGI_TEMPLATE_APP to an installed OpenLogi.app, or install it with:" >&2
	echo "  brew install --cask openlogi" >&2
	exit 1
fi

rm -rf "$OUT"
mkdir -p "$ROOT/dist"
# ditto preserves resource forks, symlinks and extended attributes.
ditto "$SRC" "$OUT"

install -m 755 "$BIN/openlogi-desktop" "$OUT/Contents/MacOS/openlogi-desktop"
install -m 755 "$BIN/openlogi" "$OUT/Contents/MacOS/openlogi"
install -m 755 "$BIN/openlogi-agent" \
	"$OUT/Contents/Library/LoginItems/OpenLogi Agent.app/Contents/MacOS/openlogi-agent"
install -m 755 "$BIN/openlogi-overlay" \
	"$OUT/Contents/Library/LoginItems/OpenLogi Overlay.app/Contents/MacOS/openlogi-overlay"

# This build embeds no Sparkle (no EdDSA key, feed pointed at .invalid) and
# carries no provisioning profile, so neither the framework nor the upstream
# profile belongs in the bundle.
rm -rf "$OUT/Contents/Frameworks"
rm -f "$OUT/Contents/Library/LoginItems/OpenLogi Agent.app/Contents/embedded.provisionprofile"

# Strip the upstream Sparkle keys: this build links no Sparkle (the framework is
# gone above) and updates through the built-in engine with no signing key, so a
# feed URL here would only be a promise the bundle cannot keep.
for key in SUFeedURL SUPublicEDKey SUAllowsAutomaticUpdates SUEnableAutomaticChecks \
	SUEnableSystemProfiling SUVerifyUpdateBeforeExtraction; do
	/usr/libexec/PlistBuddy -c "Delete :$key" "$OUT/Contents/Info.plist" >/dev/null 2>&1 || true
done

# Everything below must be in place before signing: a signature seals the bundle.
{
	printf 'OpenLogi fork: Screenflare actions (FORK.md)\n'
	printf 'built: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
	printf 'source: %s\n' "$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
} >"$OUT/Contents/Resources/fork-build.txt"

find "$OUT" -name _CodeSignature -type d -prune -exec rm -rf {} +

# Deepest code first: the outer signature seals the nested helper signatures.
codesign --force --sign - --timestamp=none "$OUT/Contents/Library/LoginItems/OpenLogi Agent.app"
codesign --force --sign - --timestamp=none "$OUT/Contents/Library/LoginItems/OpenLogi Overlay.app"
codesign --force --sign - --timestamp=none "$OUT"
codesign --verify --deep --strict "$OUT"

echo "Bundle ready: $OUT"
codesign -dv "$OUT" 2>&1 | sed -n '1,4p'
