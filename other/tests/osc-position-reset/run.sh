#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="$repo_dir/build/osc-position-reset-tests"
mkdir -p "$output_dir/profile" "$output_dir/module-cache"
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PYENUM'
from pathlib import Path
import sys
repo, tests, output = map(Path, sys.argv[1:])
s = (repo / 'iina/Preference.swift').read_text()
start = s.index('  enum OSCClickAction:')
end = s.index('  enum ScrollAction:', start)
(output / 'Support.swift').write_text((tests / 'Support.swift').read_text().replace('// PRODUCTION_OSC_CLICK_ACTION', s[start:end]))
PYENUM
{ cat "$output_dir/Support.swift"; cat "$repo_dir/iina/ConstraintsSugar.swift"; cat "$repo_dir/iina/TranslucentView.swift"; cat "$repo_dir/iina/TimeLabelOverflowedStackView.swift"; cat "$repo_dir/iina/FloatingOSCScale.swift"; cat "$repo_dir/iina/FloatingOSCPositionPreferences.swift"; cat "$repo_dir/iina/OSCFloatingView.swift"; cat "$test_dir/main.swift"; } > "$output_dir/main.swift"
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/osc-position-reset-tests"
CFFIXED_USER_HOME="$output_dir/profile" "$output_dir/osc-position-reset-tests"
CFFIXED_USER_HOME="$output_dir/profile" "$output_dir/osc-position-reset-tests" --verify-persistence
