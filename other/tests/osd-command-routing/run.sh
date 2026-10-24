#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${OSD_COMMAND_ROUTING_OUTPUT_DIR:-$repo_dir/build/osd-command-routing-tests}"
cache_dir="${OSD_COMMAND_ROUTING_MODULE_CACHE:-$output_dir/module-cache}"
mkdir -p "$output_dir" "$cache_dir"
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PY'
from pathlib import Path
import os, sys
repo, tests, out = map(Path, sys.argv[1:])
source = Path(os.environ.get('OSD_COMMAND_ROUTING_SOURCE', repo/'iina/OSDMessage.swift')).read_text()
def extract(marker):
    start = source.index(marker)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]
production = '\n'.join(extract(marker) for marker in ['enum OSDFeedbackOrigin {', 'enum OSDFeedbackValue:',
    'final class OSDFeedbackOrigins {', 'enum OSDCommandRouting {'])
(out/'main.swift').write_text((tests/'main.swift').read_text().replace('// PRODUCTION_ROUTING', production))
PY
xcrun swiftc -warnings-as-errors -module-cache-path "$cache_dir" "$output_dir/main.swift" -o "$output_dir/tests"
"$output_dir/tests"
