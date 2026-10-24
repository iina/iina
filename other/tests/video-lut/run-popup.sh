#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
output="${1:-$root/build/video-lut-popup}"
mkdir -p "$output"
scratch="$(mktemp -d "$output/run.XXXXXX")"
python3 - "$root" "$scratch" <<'PY'
from pathlib import Path
import sys
root,out=map(Path,sys.argv[1:])
def extract(text, marker):
    start=text.index(marker);end=text.index('{',start)+1;depth=1
    while depth:
        depth+=(text[end]=='{')-(text[end]=='}');end+=1
    return text[start:end]
support=(root/'other/tests/video-lut/popup-support.swift').read_text()
support=support.replace('// PRODUCTION_SAVED_LUT',extract((root/'iina/PlayerCore.swift').read_text(),'  func detachSavedVideoLUT('))
video=(root/'iina/SidebarVideoPane.swift').read_text()
(out/'main.swift').write_text(support+'\n'+extract(video,'final class VideoLUTPopUp:')+'\n'+extract(video,'enum VideoLUTLibraryActions {')+'\n'+(root/'other/tests/video-lut/popup-main.swift').read_text())
PY
xcrun swiftc "$root/iina/TrackSelectionState.swift" "$root/iina/TrackAudioProcessing.swift" \
  "$root/iina/TrackVideoProcessing.swift" "$root/iina/TrackProcessingState.swift" \
  "$root/iina/VideoLUT.swift" "$scratch/main.swift" -o "$scratch/checks"
"$scratch/checks" "$scratch/profile"
