#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${CUSTOM_CROP_OUTPUT_DIR:-$repo_dir/build/custom-crop-tests}"
interactive_source="${CUSTOM_CROP_INTERACTIVE_SOURCE:-$repo_dir/iina/InteractiveMode.swift}"
mkdir -p "$output_dir/module-cache"
{
  printf 'extension PlayerFixture {\n'
  printf '  @discardableResult\n'
  awk '/^  func setCrop\(fromFilter filter: MPVFilter\)/ { extracting=1 } extracting { print } extracting && /^  \}$/ { exit }' "$repo_dir/iina/PlayerCore.swift"
  awk '/^  func removeCropFilter\(\) \{/ { extracting=1 } extracting { print } extracting && /^  \}$/ { exit }' "$repo_dir/iina/PlayerCore.swift"
  printf '}\n'
} > "$output_dir/player-crop-removal.swift"
{
  printf 'class CropVideoFixture: NSView {\n  let player: PlayerFixture\n  let videoLayer = CropRenderFixture()\n  init(player: PlayerFixture) { self.player = player; super.init(frame: .zero) }\n  required init?(coder: NSCoder) { fatalError() }\n'
  awk '/^  override var mouseDownCanMoveWindow: Bool \{|^  override func hitTest\(_ point: NSPoint\) -> NSView\? \{/ { extracting=1 } extracting { print } extracting && /^  \}$/ { extracting=0 }' "$repo_dir/iina/VideoView.swift"
  printf '}\n'
} > "$output_dir/video-hit-testing.swift"
python3 - "$test_dir/Support.swift" "$repo_dir/iina/MainWindowController.swift" "$output_dir/support.swift" <<'PYTHON'
from pathlib import Path
import sys
support, source, output = map(Path, sys.argv[1:])
text = source.read_text()
start = text.index('  func updateVideoViewConstraints(')
end = text.index('\n  }', start) + 4
restoration_start = text.index('  func deferCropVideoRestoration(')
restoration_end = text.index('\n  }', restoration_start) + 4
output.write_text(support.read_text().replace('// PRODUCTION_VIDEO_CONSTRAINT_UPDATE', text[start:end])
                  .replace('// PRODUCTION_DEFER_CROP_RESTORATION', text[restoration_start:restoration_end]))
PYTHON
cat "$output_dir/support.swift" "$repo_dir/iina/ResizeCursor.swift" "$repo_dir/iina/ConstraintsSugar.swift" "$repo_dir/iina/ScrollSelectionControl.swift" "$repo_dir/iina/MPVFilter.swift" "$repo_dir/iina/TrackSelectionState.swift" "$repo_dir/iina/TrackVideoProcessing.swift" "$interactive_source" "$output_dir/player-crop-removal.swift" "$output_dir/video-hit-testing.swift" "$test_dir/main.swift" > "$output_dir/main.swift"
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/custom-crop-tests"
"$output_dir/custom-crop-tests"
