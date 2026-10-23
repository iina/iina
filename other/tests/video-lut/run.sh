#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
output="${1:-$root/build/lut-sidebar-2026-10-17/model}"
mkdir -p "$output"
xcrun swiftc "$root/iina/TrackSelectionState.swift" "$root/iina/TrackAudioProcessing.swift" \
  "$root/iina/TrackVideoProcessing.swift" "$root/iina/TrackProcessingState.swift" \
  "$root/iina/VideoLUT.swift" "$root/other/tests/video-lut/main.swift" -o "$output/tests"
fixtures="$(mktemp -d "$output/run.XXXXXX")"
"$output/tests" "$fixtures"
cp "$fixtures/graphs.json" "$output/graphs.json"
bash "$root/other/tests/video-lut/run-popup.sh" "$output/popup"
