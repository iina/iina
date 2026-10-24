#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${FLOATING_OSC_OUTPUT_DIR:-$repo_dir/build/floating-osc-scale-tests}"
mkdir -p "$output_dir/module-cache"
# Compile the same clamping extension used by the production placement helper.
python3 - "$repo_dir" "$output_dir" <<'PYCLAMP'
from pathlib import Path
import sys
repo, output = map(Path, sys.argv[1:])
source = (repo / 'iina/Extensions.swift').read_text()
start = source.index('extension Comparable {')
end = source.index('\n}', start) + 2
(output / 'Clamping.swift').write_text(source[start:end])
PYCLAMP
xcrun swiftc -module-cache-path "$output_dir/module-cache" \
  "$output_dir/Clamping.swift" "$repo_dir/iina/FloatingOSCScale.swift" "$test_dir/main.swift" \
  -o "$output_dir/floating-osc-scale-tests"
"$output_dir/floating-osc-scale-tests"

# Exercise the actual native production methods against AppKit controls, including
# duplicate required dimensions and repeated floating/docked layout switches.
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PY'
from pathlib import Path
import sys
repo_dir, test_dir, output_dir = map(Path, sys.argv[1:])
source = (repo_dir / 'iina/MainWindowController.swift').read_text()
def section(start, end):
    return source[source.index(start):source.index(end, source.index(start))]
replacements = {
    '// PRODUCTION_PROPERTIES': section('  private(set) var floatingOSCScale', '  var osdView:'),
    '// PRODUCTION_CAPTURE': section('    let sizedViews:', '    // osd\n'),
    '// PRODUCTION_METHODS': section('  func updateFloatingOSCScale(scale:', '  // MARK: - Mouse / Trackpad events'),
    '// PRODUCTION_TOOLBAR_CAPTURE': section('    floatingOSCToolbarConstraints =', '//    let menuButton'),
}
harness = (test_dir / 'NativeHarness.swift').read_text()
for marker, replacement in replacements.items():
    assert marker in harness, marker
    harness = harness.replace(marker, replacement)
(output_dir / 'main.swift').write_text(harness)
PY
xcrun swiftc -module-cache-path "$output_dir/module-cache" \
  "$output_dir/Clamping.swift" "$repo_dir/iina/FloatingOSCScale.swift" "$output_dir/main.swift" \
  -o "$output_dir/floating-osc-native-tests"
"$output_dir/floating-osc-native-tests"

# Construct the real native anchored groups and material wrappers. Check actual
# control frames through repeated width changes, including at a constant scale.
python3 "$test_dir/generate-layout-harness.py" "$repo_dir" "$test_dir" "$output_dir"
xcrun swiftc -module-cache-path "$output_dir/module-cache" \
  "$output_dir/Clamping.swift" "$repo_dir/iina/FloatingOSCScale.swift" "$output_dir/main.swift" \
  -o "$output_dir/floating-osc-layout-tests"
"$output_dir/floating-osc-layout-tests"
