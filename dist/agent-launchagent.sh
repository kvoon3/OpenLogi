#!/bin/sh
# Start the fork's agent from a user LaunchAgent instead of SMAppService.
#
# Why: launchd binds an SMAppService agent to a *launch constraint* recorded when
# the app registered it. Re-signing the bundle (which this fork does, ad-hoc)
# changes the agent's code requirement, so every spawn dies with
#
#   OS_REASON_CODESIGNING | Launch Constraint Violation, (Constraint not matched)
#
# and `launchctl print` shows `last exit code = 78: EX_CONFIG`. A plain
# ~/Library/LaunchAgents job carries no such constraint: launchd just execs the
# binary, so the fork's agent starts at login like any other user agent.
#
# Consequence: the agent is no longer launched "as OpenLogi", so macOS attributes
# its privacy grants to the agent itself — grant Accessibility and Input
# Monitoring to OpenLogi Agent (System Settings ▸ Privacy & Security), not to
# OpenLogi.

set -eu

LABEL=app.openlogi.agent.fork
PLIST=$HOME/Library/LaunchAgents/$LABEL.plist
AGENT="/Applications/OpenLogi.app/Contents/Library/LoginItems/OpenLogi Agent.app/Contents/MacOS/openlogi-agent"

usage() {
	sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
	exit "${1:-0}"
}

case ${1:-install} in
-h | --help) usage 0 ;;
install)
	[ -x "$AGENT" ] || { echo "agent not found: $AGENT" >&2; exit 1; }
	mkdir -p "$HOME/Library/LaunchAgents"
	cat >"$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$AGENT</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
PLIST_EOF
	launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
	launchctl bootstrap "gui/$UID" "$PLIST"
	echo "installed $PLIST"
	launchctl print "gui/$UID/$LABEL" 2>&1 | grep -E "state =|pid = " | head -2
	;;
uninstall)
	launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
	rm -f "$PLIST"
	echo "removed $LABEL"
	;;
*) usage 2 ;;
esac
