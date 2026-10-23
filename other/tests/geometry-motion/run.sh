#!/bin/bash
set -euo pipefail
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${GEOMETRY_MOTION_OUTPUT_DIR:-$repo_dir/build/geometry-motion-tests}"
mkdir -p "$output_dir/module-cache"
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PY'
from pathlib import Path
import hashlib,json,os,sys
repo,tests,output=map(Path,sys.argv[1:])
sources={name:Path(os.environ.get(env,repo/'iina'/name)).read_text() for name,env in [('MainWindowController.swift','GEOMETRY_MOTION_MAIN_SOURCE'),('PlayerCore.swift','GEOMETRY_MOTION_PLAYER_SOURCE'),('InteractiveMode.swift','GEOMETRY_MOTION_INTERACTIVE_SOURCE')]}
def extract(text,marker):
 start=text.index(marker);end=text.index('{',start)+1;balance=1
 while balance:
  balance+=(text[end]=='{')-(text[end]=='}');end+=1
 return text[start:end]
main,player,interactive=[sources[n] for n in ['MainWindowController.swift','PlayerCore.swift','InteractiveMode.swift']]
fields=main[main.index('  enum VideoGeometryChange:'):main.index('  private var cropExitOverlay:',main.index('  enum VideoGeometryChange:'))]
methods='\n'.join(extract(main,m) for m in ['  func enqueueVideoGeometryChange(', '  func performVideoGeometryChange(', '  func geometryVideoOutputDidChange(', '  private func startVideoGeometryAnimation(', '  func cancelVideoGeometryTransition(', '  private func finishVideoGeometryTransition(', '  func bindCropVideo(', '  func cropTransitionDuration('])
# Exercise the final OSD delivery decisions without recreating its rendering UI.
# Preserve the actual guard expressions and only make their early return observable.
delivery=extract(main,'  func displayOSD(')
guards=delivery[delivery.index('{')+1:delivery.index('    if hideOSDTimer != nil')]
methods+='\n'+extract(main,'  var isCropTransitionInProgress:')
methods+='\n  func canDeliverOSD(_ message:OSDMessage)->Bool {'+guards.replace('return }','return false }')+'    return true\n  }'
pinch=extract(main,'  @objc func handleMagnifyGesture(')
window_pinch=pinch[pinch.index('    case .windowSize:'):]
began=extract(window_pinch,'      if recognizer.state == .began {')
methods+='\n  func beginWindowSizePinchForTesting(_ recognizer:PinchFixture) {\n    guard let window else { return }\n'+began+'\n  }'
production='\n'.join(extract(interactive,m) for m in ['final class NativeCropVideoPresentation {','enum VideoGeometryTransition {','final class DelayedPreparationFeedback {','final class CropTransitionOverlay:','struct CropVideoGeometry {'])
# Observe the actual production clock's policy and retain its existing advance
# closure. Tests can drive time deterministically without replacing progress,
# generation checks, update/completion, timer fallback or watchdog logic.
for marker,replacement in [
 ('    var start: CFTimeInterval? = startOnFirstTick ? nil : CACurrentMediaTime()', '    ClockTrace.policies.append((duration, curve, startOnFirstTick))\n    var start: CFTimeInterval? = startOnFirstTick ? nil : CACurrentMediaTime()'),
 ('    let tick: (CFTimeInterval) -> Void = { timestamp in', '    ClockTrace.advances.append(advance)\n    let tick: (CFTimeInterval) -> Void = { timestamp in'),
 ('    guard duration > 0 else { advance(1); return }', '    ClockTrace.ticks.append(tick)\n    guard duration > 0 else { advance(1); return }'),
 ('      timer = watchdog', '      ClockTrace.watchdogs.append(watchdog)\n      timer = watchdog')]:
 assert production.count(marker)==1, 'Clock observation point changed: '+marker
 production=production.replace(marker,replacement)
predicates='\n'.join(extract(player,m) for m in ['  var canAnimateCropSource:'])
for marker in ['  var canAnimateVideoGeometrySource:', '  var canAnimateVideoGeometry:']:
 if marker in player: predicates+='\n'+extract(player,marker)
player_methods='\n'.join(extract(player,m) for m in ['  func setVideoAspect(', '  func setVideoRotate(', '  func interactiveVideoGeometry(', '  var defaultVideoPixelAspect:', '  var defaultVideoRotation:', '  func requestNativeCropFrame('])
# Keep actual restart notification wiring; time/Now Playing/analysis updates
# after that boundary are unrelated to native ownership in this fixture.
restart=extract(player,'  func playbackRestarted(')
player_methods+='\n'+restart[:restart.index('    log("Playback restarted")')]+'  }'
seek_fields=player[player.index('  private enum CropRefreshUpdate:'):player.index('  var isRefreshingPausedCrop:',player.index('  private enum CropRefreshUpdate:'))]
seek_methods='\n'.join(('@discardableResult\n' if m == '  func userInitiatedSeek(' else '')+extract(player,m) for m in ['  var isRefreshingPausedCrop:', '  var shouldShowSeekOSD:', '  func userInitiatedSeek(', '  func seekOSDDidStart(', '  func seekOSDDidRestart(', '  func beginVideoGeometryOSDRefresh(', '  func endVideoGeometryOSDRefresh(', '  private func cancelVideoGeometryOSDRefresh('])
support=(tests/'Support.swift').read_text().replace('// PRODUCTION_MAIN_FIELDS',fields).replace('// PRODUCTION_MAIN_METHODS',methods).replace('// PRODUCTION_PLAYER_METHODS',predicates+'\n'+player_methods).replace('// PRODUCTION_SEEK_FIELDS',seek_fields).replace('// PRODUCTION_SEEK_METHODS',seek_methods)
text=(repo/'iina/Regex.swift').read_text()+'\n'+production+'\n'+support+'\n'+(tests/'main.swift').read_text()
(output/'main.swift').write_text(text)
for name,source in sources.items(): (output/('source-'+name)).write_text(source)
(output/'inputs.json').write_text(json.dumps({name:hashlib.sha256(source.encode()).hexdigest() for name,source in sources.items()},indent=2)+'\n')
PY
xcrun swiftc -warnings-as-errors -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/tests"
"$output_dir/tests" | tee "$output_dir/results.log"
