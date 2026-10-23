#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
out="$repo_dir/build/sidebar-selector-tests"
mkdir -p "$out"
python3 - "$repo_dir" "$test_dir" "$out" <<'PY'
from pathlib import Path
import sys
repo, tests, out = map(Path, sys.argv[1:])
s = (repo/'iina/SideBar.swift').read_text()
pane = (repo/'iina/SidebarPane.swift').read_text()
motion = pane[pane.index('enum SidebarTabMotion {'):pane.index('class SidebarTabViewController:')]
status = s[s.index('  func updateTabActiveStatus() {'):s.index('  func updateTabButtonSize() {')]
s = s[s.index('private final class SidebarSelectorOverlay:'):]
(out/'main.swift').write_text('''import Cocoa
import QuartzCore
struct AccessibilityPreferences {
  static var motionReductionEnabled = false
  static func adjustedDuration(_ duration: TimeInterval) -> TimeInterval { duration }
}
''' + motion + s + '''
class HeaderFixture {
  struct Tab { var tag: Int; var name: String }
  var isLeading = false
  var allTabs: [Tab]
  var currentTab: Tab
  var tabButtonsSegmentControl: NSSegmentedControl
  init(_ control: NSSegmentedControl, titles: [String]) {
    tabButtonsSegmentControl = control
    allTabs = titles.enumerated().map { Tab(tag: $0.offset, name: $0.element) }
    currentTab = allTabs[0]
  }
''' + status + '}\n' + (tests/'main.swift').read_text())
PY
xcrun swiftc "$out/main.swift" -o "$out/tests"
"$out/tests"
