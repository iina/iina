#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
output="${1:-$root/build/circular-button-cursors-2026-10-17/focused}"
mkdir -p "$output"
python3 - "$root" "$output" <<'PY'
from pathlib import Path
import sys
root, output = map(Path, sys.argv[1:])
buttons = (root/'iina/UIHelper.swift').read_text().split('\nclass UIHelper {', 1)[0]
source = (root/'iina/SidebarTrackSelector.swift').read_text()
reference = 'private final class TrackRemoveButton:' + source.split('private final class TrackRemoveButton:', 1)[1].split('\nprivate final class TrackOffHeaderView:', 1)[0]
body = (root/'other/tests/circular-action-buttons/main.swift').read_text()
(output/'main.swift').write_text('import Cocoa\n' + buttons + '\n' + reference + '\n' + body)
PY
xcrun swiftc "$output/main.swift" -o "$output/checks"
"$output/checks"
