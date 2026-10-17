#!/bin/sh
# Runs the test suite. With only Command Line Tools installed, Swift Testing's macro
# plugin is not on the default search path, so pass it explicitly.
set -e
cd "$(dirname "$0")/.."
PLUGINS=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
if [ -d "$PLUGINS" ] && ! xcode-select -p 2>/dev/null | grep -q Xcode.app; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
fi
exec swift test "$@"
