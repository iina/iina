#!/bin/bash
set -eu
repo_dir="$(cd "$(dirname "$0")/../../.." && pwd)"
output_dir="${VIDEO_SESSION_OUTPUT_DIR:-$repo_dir/build/video-geometry-session-tests}"
mkdir -p "$output_dir/module-cache"
python3 - "$repo_dir" "$output_dir" <<'PY'
from pathlib import Path
import sys
repo, out = map(Path, sys.argv[1:])
def extract(text, marker):
    start = text.index(marker)
    end = text.index('{', start) + 1
    depth = 1
    while depth:
        if text[end] == '{': depth += 1
        elif text[end] == '}': depth -= 1
        end += 1
    return text[start:end]
player = (repo/'iina/PlayerCore.swift').read_text()
methods = '\n'.join(extract(player, m) for m in [
    '  private var videoGeometryFilterLabels:', '  private func readVideoGeometry(',
    '  private func saveVideoGeometryForCurrentMedia(', '  private func prepareVideoGeometryForNewFile(',
    '  private func restoreVideoGeometryForCurrentMedia(', '  private func applyVideoGeometry(',
    '  private func syncVideoGeometryInfo(', '  private func restoreVideoTrackGeometryForCurrentMedia(',
    '  func reloadSavedIINAfilters(', '  func windowScaleChanged(', '  func setCrop(fromString'])
geometry = extract((repo/'iina/InteractiveMode.swift').read_text(), 'struct CropVideoGeometry {')
ext = (repo/'iina/Extensions.swift').read_text()
helpers = '\n'.join(extract(ext,m) for m in ['  var aspect:', '  func centeredRect(in rect:', '  func crop(withAspect aspectRect:'])
support = (repo/'other/tests/video-geometry-session/Support.swift').read_text().replace('// PRODUCTION_METHODS', methods)
source = '\n'.join([
    (repo/'iina/Regex.swift').read_text(), (repo/'iina/Aspect.swift').read_text(),
    (repo/'iina/MPVFilter.swift').read_text(), (repo/'iina/TrackSelectionState.swift').read_text(),
    (repo/'iina/TrackAudioProcessing.swift').read_text(), (repo/'iina/TrackVideoProcessing.swift').read_text(),
    (repo/'iina/TrackProcessingState.swift').read_text(), geometry,
    'extension NSSize {\n'+helpers+'\n}', support,
    (repo/'other/tests/video-geometry-session/main.swift').read_text()])
(out/'main.swift').write_text(source)
PY
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/tests"
"$output_dir/tests"
