#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
output="${1:-$root/build/lut-sidebar-2026-10-17/popup}"
mkdir -p "$output"
python3 - "$root" "$output" <<'PY'
from pathlib import Path
import sys
root, output = map(Path, sys.argv[1:])
source = (root/'iina/SidebarVideoPane.swift').read_text()
popup = source.split('final class VideoLUTPopUp:', 1)[1].split('fileprivate class EqualizerView:', 1)[0]
tests = root/'other/tests/video-lut'
(output/'main.swift').write_text((tests/'popup-support.swift').read_text() + '\nfinal class VideoLUTPopUp:' + popup + '\n' + (tests/'popup-main.swift').read_text())
PY
xcrun swiftc "$root/iina/TrackSelectionState.swift" "$root/iina/TrackAudioProcessing.swift" \
  "$root/iina/TrackVideoProcessing.swift" "$root/iina/TrackProcessingState.swift" \
  "$root/iina/VideoLUT.swift" "$output/main.swift" -o "$output/checks"
"$output/checks" "$output/profile"
