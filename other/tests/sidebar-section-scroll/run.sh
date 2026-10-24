#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
out="${SIDEBAR_SCROLL_OUTPUT_DIR:-$repo_dir/build/sidebar-section-scroll-tests}"
mkdir -p "$out/module-cache"
python3 - "$repo_dir" "$test_dir" "$out" <<'PY'
from pathlib import Path
import os, sys
repo, tests, out = map(Path, sys.argv[1:])
def extract(text, marker):
    start=text.index(marker);end=text.index('{',start)+1;depth=1
    while depth:
        depth+=(text[end]=='{')-(text[end]=='}');end+=1
    return text[start:end]
source = (tests/'Support.swift').read_text()

source += '\n' + (repo/'iina/ConstraintsSugar.swift').read_text()
sidebar_pane = Path(os.environ.get('SIDEBAR_PANE_SOURCE', str(repo/'iina/SidebarPane.swift'))).read_text()
# Settings headers are outside this suite's scrolling/transition boundary.
for marker in ['final class TrackSettingsGroupView:', 'final class TrackProcessingSection:']:
    if marker in sidebar_pane: sidebar_pane = sidebar_pane.replace(extract(sidebar_pane,marker),'')
source += '\n' + sidebar_pane

sidebar = Path(os.environ.get('SIDEBAR_HEADER_SOURCE', str(repo/'iina/SideBar.swift'))).read_text()
source += '\n' + sidebar[sidebar.index('class SidebarViewController:'):]
source += '\n' + (tests/'main.swift').read_text()
(out/'main.swift').write_text(source)
PY
xcrun swiftc -module-cache-path "$out/module-cache" "$out/main.swift" -o "$out/tests"
"$out/tests"
