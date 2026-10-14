#!/bin/zsh
# Runs the unit tests. With only the Command Line Tools installed, the Swift Testing
# macro plugin lives in a subfolder the compiler does not search, so point it there.
set -euo pipefail
cd "${0:A:h}/.."

flags=()
plugins="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -d "$plugins" ]]; then
  flags=(-Xswiftc -plugin-path -Xswiftc "$plugins")
fi

swift test "${flags[@]}" "$@"
