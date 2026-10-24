#!/bin/bash
set -euo pipefail
tests="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$tests/../../.." && pwd)"
out="${GEOMETRY_RESET_OUTPUT_DIR:-$repo/build/geometry-reset-tests}"
mkdir -p "$out/module-cache"
python3 - "$repo" "$tests" "$out" <<'PY'
from pathlib import Path
import hashlib,json,os,sys
repo,tests,out=map(Path,sys.argv[1:])
# Reuse the existing extracted Main/native-clock support; replace its test entry
# with this reset/observer/UI regression, without running or copying its tests.
generator=(repo/'other/tests/geometry-motion/run.sh').read_text().split("<<'PY'\n",1)[1].split('\nPY\n',1)[0]
sys.argv=['geometry-motion-generator',str(repo),str(repo/'other/tests/geometry-motion'),str(out)]
exec(compile(generator,'geometry-motion-generator','exec'),{})
source=(out/'main.swift').read_text().split('var checks=0,failures:',1)[0]
def extract(text,marker):
 start=text.index(marker);end=text.index('{',start)+1;depth=1
 while depth:
  depth+=(text[end]=='{')-(text[end]=='}');end+=1
 return text[start:end]
core=(repo/'iina/PlayerCore.swift').read_text()
settings=(repo/'iina/TrackSettings.swift').read_text()
mpv=Path(os.environ.get('GEOMETRY_RESET_MPV_SOURCE',repo/'iina/MPVController.swift')).read_text()
sidebar=(repo/'iina/SidebarVideoPane.swift').read_text()
source=source.replace('enum OSDMessage { case seek,pause,aspect,rotate;','enum OSDMessage { case seek,pause,aspect;case rotate(Int);')
marker='    var videoTracks:[Track]=[],vid=1'
assert source.count(marker)==1
source=source.replace(marker,marker+'\n    var rotation=0,brightness=0,contrast=0,saturation=0,gamma=0,hue=0\n    var unsureCrop="None",cropFilter:ResetFilter?')
marker='  let info=Info(),mpv=MPVFixture()'
assert source.count(marker)==1
source=source.replace(marker,marker+'\n'+(tests/'PlayerFields.swift').read_text())
state=(repo/'iina/TrackProcessingState.swift').read_text()
state+='\n'+extract((repo/'iina/TrackAudioProcessing.swift').read_text(),'struct AudioTrackProcessing:')
state+='\n'+extract((repo/'iina/TrackVideoProcessing.swift').read_text(),'struct TrackVideoCrop:')
state+='\n'+extract((repo/'iina/TrackVideoProcessing.swift').read_text(),'struct VideoTrackProcessing:')
methods='\n'.join(extract(settings,m) for m in ['  func resetTrackSettings(', '  func scopedVideoSettings('])
methods+='\n'+extract(core,'  func removeCropFilter(')+'\n'+extract(core,'  func observe(')+'\n'+extract(core,'  func postNotification(')
rotation_case=mpv[mpv.index('    case MPVOption.Video.videoRotate:'):mpv.index('    case MPVOption.Audio.mute:',mpv.index('    case MPVOption.Video.videoRotate:'))]
dispatch='    let onMain: (@escaping () -> Void) -> Void = { action in DispatchQueue.main.async(execute: action) }' if 'onMain' in rotation_case else ''
support=(tests/'Support.swift').read_text().replace('// PRODUCTION_PLAYER_METHODS',methods).replace('// PRODUCTION_ROTATION_OBSERVER',rotation_case).replace('// OBSERVER_DISPATCH',dispatch)
source+='\n'+state+'\n'+support+'\n'+extract(sidebar,'fileprivate class RotationView:')+'\n'+(tests/'main.swift').read_text()
(out/'main.swift').write_text(source)
inputs=json.loads((out/'inputs.json').read_text())
for name,text in [('TrackSettings.swift',settings),('MPVController.swift',mpv),('SidebarVideoPane.swift',sidebar)]:
 (out/('source-'+name)).write_text(text)
 inputs[name]=hashlib.sha256(text.encode()).hexdigest()
(out/'inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
PY
xcrun swiftc -warnings-as-errors -module-cache-path "$out/module-cache" "$out/main.swift" -o "$out/tests"
"$out/tests" | tee "$out/results.log"
