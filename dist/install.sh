#!/bin/sh
# Replace /Applications/OpenLogi.app with the fork build in dist/.
#
# Interrupts the running app: the GUI, the agent and the overlay all have to stop
# before their bundle is swapped. The upstream bundle is kept in dist/ as
# OpenLogi.upstream.app so `--rollback` can put it back.
#
# The new bundle is ad-hoc signed, so macOS will ask for Accessibility and Input
# Monitoring again on the next launch (System Settings ▸ Privacy & Security).

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FORK=$ROOT/dist/OpenLogi.app
TARGET=/Applications/OpenLogi.app
# Keep the backup OUT of /Applications: two bundles with one CFBundleIdentifier
# confuse Launch Services and per-signature TCC records.
BACKUP=$ROOT/dist/OpenLogi.upstream.app

usage() {
	sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
	exit "${1:-0}"
}

YES=0
confirm() {
	if [ "$YES" != "1" ]; then
		printf '%s\n' "$2"
		printf 'Continue? [y/N] '
		read -r answer
		case $answer in
		[yY]*) ;;
		*) echo "aborted"; exit 1 ;;
		esac
	fi
}

stop_openlogi() {
	osascript -e 'quit app id "org.openlogi.openlogi"' >/dev/null 2>&1 || true
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		pgrep -x openlogi-desktop >/dev/null || pgrep -x openlogi-agent >/dev/null || break
		sleep 0.5
	done
	pkill -x openlogi-overlay >/dev/null 2>&1 || true
	pkill -x openlogi-agent >/dev/null 2>&1 || true
	pkill -x openlogi-desktop >/dev/null 2>&1 || true
	sleep 1
}

case ${1:-} in
-h | --help) usage 0 ;;
--rollback)
	[ -d "$BACKUP" ] || { echo "no backup at $BACKUP" >&2; exit 1; }
	stop_openlogi
	rm -rf "$TARGET"
	mv "$BACKUP" "$TARGET"
	open "$TARGET"
	echo "restored the upstream bundle"
	exit 0
	;;
--yes) YES=1; shift ;;
"") ;;
*) usage 2 ;;
esac

[ -d "$FORK" ] || { echo "build it first: $ROOT/dist/bundle.sh" >&2; exit 1; }
[ -d "$TARGET" ] || echo "note: no bundle at $TARGET; nothing to back up"

confirm "This quits OpenLogi, moves the installed bundle to $BACKUP, installs the fork build, and relaunches."

stop_openlogi
if [ -d "$TARGET" ] && [ ! -d "$BACKUP" ]; then
	mv "$TARGET" "$BACKUP"
fi
rm -rf "$TARGET"
ditto "$FORK" "$TARGET"
open "$TARGET"

echo "installed $TARGET"
echo "next: grant Accessibility and Input Monitoring to OpenLogi (and OpenLogi Agent) again,"
echo "      then open the mouse's button editor to find the Screenflare action group."
