#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${CROP_TRANSITION_OUTPUT_DIR:-$repo_dir/build/crop-exit-transition-tests}"
mkdir -p "$output_dir/module-cache"
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PY'
from pathlib import Path
import os, sys
repo, tests, output = map(Path, sys.argv[1:])
def extract(text, marker):
    start = text.index(marker)
    end = text.index('{', start) + 1
    balance = 1
    while balance:
        balance += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]
controller = Path(os.environ.get('CROP_TRANSITION_MAIN_SOURCE', repo/'iina/MainWindowController.swift')).read_text()
methods = '\n'.join(extract(controller, marker) for marker in [
    '  func finishPendingNativeCropFrame(', '  func afterNativeCropFrame(', '  func bindCropVideo(', '  func prepareCropExit(', '  func cropTransitionDuration(', '  func finishCropExitTransition(', '  private func startCropExitAnimation(',
    '  func cancelCropExitTransition('])
methods += '\n' + (extract(controller, '  func prepareCropChange(') if '  func prepareCropChange(' in controller
                    else '  func prepareCropChange(_ apply: @escaping () -> Void) -> Bool { false }')
methods += '\n' + (extract(controller, '  func interruptPlayerCropTransition(') if '  func interruptPlayerCropTransition(' in controller
                    else '  func interruptPlayerCropTransition(settleWindowFrame: Bool = true) {}')
interactive = (repo/'iina/InteractiveMode.swift').read_text()
overlay = '\n'.join(extract(interactive, marker) for marker in [
    'final class DelayedPreparationFeedback {', 'final class PreparationFeedbackView:',
    'final class CropTransitionOverlay:'])
# Observe the policy passed to the actual production clock without replacing
# its update, cancellation or completion behavior.
clock_start = ('    var start: CFTimeInterval? = startOnFirstTick ? nil : CACurrentMediaTime()'
               if '    var start: CFTimeInterval? = startOnFirstTick ? nil : CACurrentMediaTime()' in overlay
               else '    let start = CACurrentMediaTime()')
assert overlay.count(clock_start) == 1
overlay = overlay.replace(clock_start, '    CropAnimationObservation.starts.append((curve, duration))\n' + clock_start)
overlay += '\nenum CropAnimationObservation { static var starts: [(curve: CropTransitionOverlay.AnimationCurve, duration: TimeInterval)] = [] }\n'
geometry = extract((repo/'iina/InteractiveMode.swift').read_text(), 'struct CropVideoGeometry {')
surface_fixture = extract((repo/'iina/InteractiveMode.swift').read_text(), 'final class NativeCropVideoPresentation:') if 'final class NativeCropVideoPresentation:' in (repo/'iina/InteractiveMode.swift').read_text() else extract((repo/'iina/InteractiveMode.swift').read_text(), 'final class NativeCropVideoPresentation {')
source = (tests/'main.swift').read_text().replace('// PRODUCTION_OVERLAY', surface_fixture + '\n' + overlay)
source = source.replace('// PRODUCTION_TRANSITION', methods)
layer = Path(os.environ.get('CROP_TRANSITION_LAYER_SOURCE', repo/'iina/ViewLayer.swift')).read_text()
state = layer[layer.index('  // MARK: - Snapshot') + len('  // MARK: - Snapshot'):layer.index('  private func takeSnapshotHandlers(')]
source = source.replace('// PRODUCTION_SNAPSHOT_STATE', state)
source = source.replace('// PRODUCTION_CROP_FRAME_STATE', layer[layer.index('  private final class CropFrameState'):layer.index('  private func takeCropFrameHandlers(')] + '\n' + '\n'.join(extract(layer, m) for m in ['  private func takeCropFrameHandlers(', '  func afterNextCropFrame(', '  private func takePreparedCropFrameHandlers(', '  func afterNextPreparedCropFrame(', '  func cancelCropFrameRequests(', '  private func deferCropDisplay(until']))
source = source.replace('// PRODUCTION_LAYER_COPY', extract(layer, '  override init(layer: Any)').replace('as! ViewLayer', 'as! SnapshotFixture'))
snapshots = '\n'.join(extract(layer, marker) for marker in [
    '  private func takeSnapshotHandlers(', '  func cancelSnapshots(', '  func captureSnapshot('])
source = source.replace('// PRODUCTION_SNAPSHOT', snapshots)
(output/'main.swift').write_text(source)
player = Path(os.environ.get('CROP_TRANSITION_PLAYER_SOURCE', repo/'iina/PlayerCore.swift')).read_text()
apply = extract(player, '  private func applyCropChange(') if '  private func applyCropChange(' in player else '''
  private func applyCropChange(_ filter: MPVFilter?, description: String, outputSize: NSSize?) {
    if let filter { if setCrop(fromFilter: filter) { info.unsureCrop = description } }
    else { removeCropFilter() }
  }
'''
frame = extract(player, '  func cropTransitionFrame(') if '  func cropTransitionFrame(' in player else '''
  func cropTransitionFrame(in bounds: NSRect) -> CropTransitionOverlay.PlayerFrame? { nil }
'''
(output/'apply.swift').write_text((tests/'apply.swift').read_text().replace('// PRODUCTION_APPLY', apply + '\n' + frame + '\n' + extract(player, '  var canAnimateCropSource:') + '\n' + '\n'.join(extract(player, m) for m in ['  private func cropTransitionSelection(', '  private func cropTransitionDisplaySize(', '  private func cropTransitionFilterRect(']))
                               .replace('// PRODUCTION_GEOMETRY', geometry + '\n' + surface_fixture + '\n' + overlay))
PY
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/tests"
"$output_dir/tests"
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/apply.swift" -o "$output_dir/apply-tests"
"$output_dir/apply-tests"
