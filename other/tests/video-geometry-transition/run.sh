#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${VIDEO_GEOMETRY_TRANSITION_OUTPUT_DIR:-$repo_dir/build/video-geometry-transition-tests}"
mkdir -p "$output_dir/module-cache"
python3 - "$repo_dir/iina/InteractiveMode.swift" "$test_dir/main.swift" "$output_dir/main.swift" <<'PY'
from pathlib import Path
import sys
source, fixture, output = map(Path, sys.argv[1:])
text = source.read_text()
def extract(marker):
    start = text.index(marker)
    end = text.index('{', start) + 1
    balance = 1
    while balance:
        balance += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]
production = '\n'.join(extract(marker) for marker in ['final class NativeCropVideoPresentation {', 'enum VideoGeometryTransition {'])
output.write_text(fixture.read_text().replace('// PRODUCTION_GEOMETRY', production))
PY
xcrun swiftc -warnings-as-errors -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/tests"
"$output_dir/tests"
