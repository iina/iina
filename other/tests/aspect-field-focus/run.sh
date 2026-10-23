#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="$repo_dir/build/aspect-field-focus-tests"
mkdir -p "$output_dir/module-cache"
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PY'
from pathlib import Path
import sys
repo, tests, output = map(Path, sys.argv[1:])
source = (repo / 'iina/SidebarVideoPane.swift').read_text()
start = source.index('fileprivate class AspectRatioView:')
end = source.index('fileprivate class CropView:', start)
field = (repo / 'iina/SidebarSliderView.swift').read_text().split('final class SidebarInputField:', 1)[1].split('\n\nclass SidebarSliderView:', 1)[0]
(output / 'main.swift').write_text((tests / 'Support.swift').read_text() + '\nfinal class SidebarInputField:' + field + '\n' + source[start:end] + '\n' + (tests / 'main.swift').read_text())
PY
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/aspect-field-focus-tests"
"$output_dir/aspect-field-focus-tests"
