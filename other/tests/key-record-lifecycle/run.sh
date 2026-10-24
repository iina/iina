#!/bin/bash
set -euo pipefail
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${KEY_RECORD_LIFECYCLE_OUTPUT_DIR:-$repo_dir/build/key-record-lifecycle-tests}"
mkdir -p "$output_dir"
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PY'
from pathlib import Path
import sys
repo, tests, output = map(Path, sys.argv[1:])
production = '\n'.join((repo / 'iina' / name).read_text() for name in [
    'IINACommand.swift', 'KeyBindingCriterion.swift', 'KeyRecordViewController.swift'
])
source = (tests / 'main.swift').read_text().replace('// PRODUCTION_SOURCES', production)
(output / 'main.swift').write_text(source)
PY
xcrun swiftc "$output_dir/main.swift" -o "$output_dir/checks"
"$output_dir/checks"
