#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
out="$repo_dir/build/traffic-light-slide-tests"
mkdir -p "$out"
python3 - "$repo_dir" "$test_dir" "$out" <<'PY'
from pathlib import Path
import sys
repo, tests, out = map(Path, sys.argv[1:])
s = (repo/'iina/Titlebar.swift').read_text()
state = s[s.index('  private struct WindowButton {'):s.index('  init(mainWindow:')]
methods = s[s.index('  // Native buttons retain'):s.index('  func updateOnTopIcon()')]
(out/'main.swift').write_text('''import Cocoa
import QuartzCore
struct AccessibilityPreferences { static var motionReductionEnabled = false }
class HeaderHarness: NSView {
  var inFullScreen = false
  var isRevealed = true
  var headerHeightConstraint: NSLayoutConstraint!
  func reveal(_ shown: Bool, animated: Bool) {
    isRevealed = shown
    positionWindowButtons(animated: animated)
  }
''' + state + methods + '\n}\n' + (tests/'main.swift').read_text())
PY
xcrun swiftc "$out/main.swift" -o "$out/tests"
"$out/tests"
