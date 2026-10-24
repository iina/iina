#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${OSD_DELIVERY_OUTPUT_DIR:-$repo_dir/build/osd-delivery-tests}"
mkdir -p "$output_dir/module-cache"
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PY'
from pathlib import Path
import hashlib,json,os,sys
repo, tests, output = map(Path, sys.argv[1:])
s = Path(os.environ.get('OSD_DELIVERY_PLAYER_SOURCE',repo/'iina/PlayerCore.swift')).read_text()
start = s.index('  func sendOSD('); end = s.index('{',start)+1; depth=1
while depth:
 depth += (s[end]=='{')-(s[end]=='}'); end+=1
(output/'main.swift').write_text((tests/'main.swift').read_text().replace('// PRODUCTION_OSD_DELIVERY',s[start:end]))
(output/'source-PlayerCore.swift').write_text(s)
(output/'inputs.json').write_text(json.dumps({'PlayerCore.swift':hashlib.sha256(s.encode()).hexdigest()},indent=2)+'\n')
PY
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/tests"
"$output_dir/tests"
