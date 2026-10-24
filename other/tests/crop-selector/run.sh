#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="$repo_dir/build/crop-selector-tests"
mkdir -p "$output_dir/module-cache"
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PY'
from pathlib import Path
import sys
repo, tests, output = map(Path, sys.argv[1:])
source = (repo/'iina/SidebarVideoPane.swift').read_text()
crop = source[source.index('fileprivate class CropView:'):source.index('fileprivate class RotationView:')]
(output/'main.swift').write_text((tests/'main.swift').read_text().replace('// PRODUCTION_CROP_VIEW', crop))
PY
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/tests"
"$output_dir/tests"
