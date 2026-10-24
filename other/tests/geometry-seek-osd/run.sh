#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${GEOMETRY_SEEK_OSD_OUTPUT_DIR:-$repo_dir/build/geometry-seek-osd-tests}"
mkdir -p "$output_dir/module-cache"
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PY'
from pathlib import Path
import os, sys
repo, tests, out = map(Path, sys.argv[1:])
player = Path(os.environ.get('GEOMETRY_SEEK_OSD_PLAYER_SOURCE', repo/'iina/PlayerCore.swift')).read_text()
mpv = Path(os.environ.get('GEOMETRY_SEEK_OSD_MPV_SOURCE', repo/'iina/MPVController.swift')).read_text()
def extract(text, marker):
    start = text.index(marker)
    end = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]
state = player[player.index('  private enum CropRefreshUpdate:'):player.index('  var isInMiniPlayer =')]
methods = extract(player, '  func pauseChanged(')
# Execute the actual cancellation prefix without unrelated teardown/AppKit work.
for marker, boundary in [
    ('  func shutdown()', '\n    info.state ='),
    ('  func mpvHasShutdown()', '\n    let isMPVInitiated'),
    ('  func stop()', '\n    guard info.state'),
    ('  func fileStarted(path:', '\n    mainWindow?.cancelCropExitTransition()'),
    ('  func fileEnded(', '\n    // if receive end-file')]:
    methods += '\n' + extract(player, marker).split(boundary)[0] + '\n  }'
seek = mpv[mpv.index('    case MPV_EVENT_SEEK:') + len('    case MPV_EVENT_SEEK:'):mpv.index('    case MPV_EVENT_PLAYBACK_RESTART:')]
restart = mpv[mpv.index('    case MPV_EVENT_PLAYBACK_RESTART:') + len('    case MPV_EVENT_PLAYBACK_RESTART:'):mpv.index('    case MPV_EVENT_END_FILE:')]
events = '\n'.join(extract(mpv, marker) for marker in ['  func afterPendingEvents(', '  private func readEvents('])
source = (tests/'main.swift').read_text().replace('// PRODUCTION_PLAYER', state + methods)
source = source.replace('// PRODUCTION_SEEK', seek).replace('// PRODUCTION_RESTART', restart)
source = source.replace('// PRODUCTION_EVENT_DRAIN', events)
(out/'main.swift').write_text(source)
PY
xcrun swiftc -warnings-as-errors -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/tests"
"$output_dir/tests"
