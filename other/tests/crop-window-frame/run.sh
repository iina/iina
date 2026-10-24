#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${CROP_WINDOW_OUTPUT_DIR:-$repo_dir/build/crop-window-frame-tests}"
mkdir -p "$output_dir/module-cache"
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PY'
from pathlib import Path
import os,sys
repo, tests, output = map(Path, sys.argv[1:])
main = Path(os.environ.get('CROP_WINDOW_MAIN_SOURCE', str(repo/'iina/MainWindowController.swift'))).read_text()
ext = (repo/'iina/Extensions.swift').read_text()
def extract(text, marker):
 start=text.index(marker); opening=text.index('{',start); end=opening+1; balance=1
 while balance:
  if text[end]=='{': balance+=1
  elif text[end]=='}': balance-=1
  end+=1
 return text[start:end]
size='\n'.join(extract(ext,m) for m in ['  var aspect:', '  func grow(toSize', '  func shrink(toSize', '  func satisfyMinSizeWithSameAspectRatio(', '  func satisfyMaxSizeWithSameAspectRatio(', '  func multiply(', '  func centeredRect(in rect:'])
rect='\n'.join(extract(ext,m) for m in ['  func centeredResize(to', '  func areaPreservingResized(', '  func constrain(in biggerRect:'])
methods='\n'.join(extract(main,m) for m in ['  var minimumWindowSize:', '  func windowFrameConstrainedToScreen(', '  private func establishVideoTransformWindowReference(', '  private func updateVideoTransformWindowReference(', '  private func rememberVideoTransformWindowResize(', '  func prepareVideoTransformWindowReference(', '  func beginVideoAspectTransition(', '  func finishVideoAspectTransition(', '  private func setWindowAspectRatio(', '  func windowFrameFromGeometry(', '  func handleVideoSizeChange(keepWindowSize:', '  func updateWindowParametersForMPV(', '  func setWindowScale(', '  func setUserWindowFrame('])
methods += '\n' + (extract(main, '  func resetWindowSizingForNewSession(') if '  func resetWindowSizingForNewSession(' in main else '  func resetWindowSizingForNewSession() {}')
appdata=(repo/'iina/AppData.swift').read_text()
constants=extract((repo/'iina/FloatingOSCScale.swift').read_text(), 'enum FloatingOSCMetrics {')+'\nenum AppData {\n'+'\n'.join(x for x in appdata.splitlines() if 'static let mainWindowMinSize =' in x or 'static let floatingOSCWindowMinSize =' in x or 'static let rotations:' in x)+'\n}'
source=(repo/'iina/Regex.swift').read_text()+'\n'+(repo/'iina/GeometryDef.swift').read_text()+'\n'+(tests/'main.swift').read_text().replace('// PRODUCTION_CONSTANTS',constants).replace('// PRODUCTION_EXTENSIONS','extension NSSize {\n'+size+'\n}\nextension NSRect {\n'+rect+'\n}').replace('// PRODUCTION_CONTROLLER_METHODS',methods)
player=Path(os.environ.get('TRANSFORM_PLAYER_SOURCE', str(repo/'iina/PlayerCore.swift'))).read_text()
source=source.replace('// PRODUCTION_PLAYER_TRANSFORMS', '\n'.join(extract(player,m) for m in ['  func setVideoAspect(', '  func setVideoRotate(', '  func setTrack(', '  func onVideoReconfig(', '  func aidChanged(']))
source=source.replace('// PRODUCTION_OUTPUT_CHANGE', extract(player, '  func videoOutputSizeChanged(') if '  func videoOutputSizeChanged(' in player else '  func videoOutputSizeChanged() { onVideoReconfig() }')
(output/'main.swift').write_text(source)
PY
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/crop-window-frame-tests"
"$output_dir/crop-window-frame-tests"
