#!/bin/zsh
set -euo pipefail
root=${0:A:h:h:h:h}
output=${1:-$root/build/track-processing-2026-10-17/video-probe}
mkdir -p "$output"
swiftc "$root/iina/TrackSelectionState.swift" "$root/iina/TrackVideoProcessing.swift" \
  "$root/other/tests/track-processing/video-main.swift" -o "$output/video-checks"
"$output/video-checks" "$output"
python3 "$root/other/tests/track-processing/video-pixels.py" "$output"
