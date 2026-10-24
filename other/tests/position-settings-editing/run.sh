#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
out="$repo_dir/build/position-settings-editing-tests"
mkdir -p "$out"
python3 - "$repo_dir" "$test_dir" "$out" <<'PY'
from pathlib import Path
import sys
repo, tests, out = map(Path, sys.argv[1:])
s = (repo/'iina/PositionPreviewDrawing.swift').read_text()
s = s[s.index('final class PositionSettingsPanel:'):]
(out/'main.swift').write_text('import Cocoa\n' + s + '\n' + (tests/'main.swift').read_text())
PY
xcrun swiftc "$out/main.swift" -o "$out/tests"
"$out/tests"
