#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${CROP_REFRESH_OUTPUT_DIR:-$repo_dir/build/crop-refresh-tests}"
mkdir -p "$output_dir/module-cache"
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PY'
from pathlib import Path
import os,sys
repo,tests,out=map(Path,sys.argv[1:])
s=Path(os.environ.get('CROP_REFRESH_PLAYER_SOURCE',repo/'iina/PlayerCore.swift')).read_text()
mpv=Path(os.environ.get('CROP_REFRESH_MPV_SOURCE',repo/'iina/MPVController.swift')).read_text()
def extract(s,marker):
 start=s.index(marker);end=s.index('{',start)+1;depth=1
 while depth:depth+=(s[end]=='{')-(s[end]=='}');end+=1
 return s[start:end]
state=s[s.index('  private enum CropRefreshUpdate:'):s.index('  var isInMiniPlayer =')] if '  private enum CropRefreshUpdate:' in s else '''
  var isRefreshingPausedCrop: Bool { false }
  var shouldShowSeekOSD: Bool { true }
  func userInitiatedSeek() {}
  private func beginPausedCropRefresh() {}
  private func finishPausedCropRefresh() {}
'''
methods='\n'.join(extract(s,m) for m in ['  func setCrop(fromFilter','  func removeCropFilter(', '  func onVideoReconfig(', '  func playbackRestarted(', '  func vfChanged('])
methods+='\n'+(extract(s,'  func videoParamsChanged(') if '  func videoParamsChanged(' in s else '  func videoParamsChanged() { postNotification(.iinaVideoParamsChanged) }')
seek=mpv[mpv.index('    case MPV_EVENT_SEEK:')+len('    case MPV_EVENT_SEEK:'):mpv.index('    case MPV_EVENT_PLAYBACK_RESTART:')]
(out/'main.swift').write_text((tests/'main.swift').read_text().replace('// PRODUCTION_REFRESH',state+methods).replace('// PRODUCTION_SEEK',seek))
PY
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/tests"
"$output_dir/tests"
