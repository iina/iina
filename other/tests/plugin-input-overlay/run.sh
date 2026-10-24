#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${PLUGIN_INPUT_OVERLAY_OUTPUT_DIR:-$repo_dir/build/plugin-input-overlay-tests}"
mkdir -p "$output_dir/module-cache"
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PY'
from pathlib import Path
import sys
repo, tests, output = map(Path, sys.argv[1:])
source = (repo / 'iina/MainWindowController.swift').read_text()
start = source.index('  lazy var pluginOverlayViewContainer:')
end = source.index('\n  }()', start) + len('\n  }()')
overlay = (repo / 'iina/PluginOverlayView.swift').read_text()
container = ''
if 'class PluginOverlayViewContainer:' in overlay:
    start_class = overlay.index('class PluginOverlayViewContainer:')
    container = overlay[start_class:overlay.index('\nclass PluginOverlayView:', start_class)]
harness = (tests / 'main.swift').read_text().replace('// PRODUCTION_CONTAINER', container)
harness = harness.replace('// PRODUCTION_FACTORY', source[start:end])
(output / 'main.swift').write_text(harness)
PY
xcrun swiftc -module-cache-path "$output_dir/module-cache" \
  "$repo_dir/iina/PluginInputManager.swift" "$output_dir/main.swift" \
  -o "$output_dir/plugin-input-overlay-tests"
"$output_dir/plugin-input-overlay-tests" "$@"
