#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
output="${1:-$root/build/shared-processing-section-tests}"
mkdir -p "$output"
python3 - "$root" "$output" <<'PY'
from pathlib import Path
import sys
r,o=map(Path,sys.argv[1:])
s=(r/'iina/SidebarPane.swift').read_text().split('final class TrackProcessingSection:',1)[1]
(o/'main.swift').write_text((r/'other/tests/track-processing/section-support.swift').read_text()+'\n'+(r/'iina/ConstraintsSugar.swift').read_text()+'\n'+(r/'iina/FlippedView.swift').read_text()+'\nfinal class TrackProcessingSection:'+s+'\n'+(r/'other/tests/track-processing/section-main.swift').read_text())
PY
xcrun swiftc "$output/main.swift" -o "$output/checks"
"$output/checks"
