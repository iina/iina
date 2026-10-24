#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
source_dir="${SOURCE_DIR:-$repo_dir/iina}"
output_dir="${OUTPUT_DIR:-$repo_dir/build/sidebar-stacking/tests}"
mkdir -p "$output_dir"
python3 - "$source_dir" "$test_dir" "$output_dir" <<'PY'
from pathlib import Path
import sys
source, tests, output = map(Path, sys.argv[1:])
def extract(text, marker):
    if marker not in text:
        return ''
    start = text.index(marker)
    end = text.index('{', start) + 1
    balance = 1
    while balance:
        if text[end] == '{': balance += 1
        if text[end] == '}': balance -= 1
        end += 1
    return text[start:end]
window = extract((source/'MainWindow.swift').read_text(), '  override func sendEvent(')
sidebar_source = (source/'SidebarController.swift').read_text()
sidebar = sidebar_source[sidebar_source.index('  private struct BackgroundPress {'):sidebar_source.index('  /// Returns true if the event was consumed by sidebar logic')]
support = (tests/'main.swift').read_text()
support = support.replace('// PRODUCTION_OSC_CLICK_ACTION', extract((source/'Preference.swift').read_text(), '  enum OSCClickAction:'))
osc = (source/'OSCFloatingView.swift').read_text()
support = support.replace('// PRODUCTION_OSC_BACKGROUND_CLICK', '\n'.join(extract(osc, marker) for marker in [
    '  func cancelPendingBackgroundClick(', '  func performSingleBackgroundClick(', '  private func performBackgroundAction(']))
support = support.replace('// PRODUCTION_OSC_SECONDARY_CLICK', '\n'.join(extract(osc, marker) for marker in ['  override func rightMouseDown(', '  override func rightMouseUp(', '  private func isBackgroundEvent(']))
controller_source = source/'MainWindowController.swift'
scroll = extract(controller_source.read_text(), '  override func scrollWheel(') if controller_source.exists() else ''
support = support.replace('// PRODUCTION_SCROLL_ROUTING', scroll)
support = support.replace('// PRODUCTION_HIDE_UI_FROM_OSC', extract(controller_source.read_text(), '  func hideUIFromOSC('))
support = support.replace('// PRODUCTION_WINDOW_DISPATCH', window)
support = support.replace('// PRODUCTION_SIDEBAR_STACKING', sidebar)
title = (source/'Titlebar.swift').read_text()
support = support.replace('// PRODUCTION_TITLEBAR_BACKGROUND', '\n'.join(extract(title, marker) for marker in [
    '  private func cancelBackgroundPress(', '  func handleBackgroundMouseEvent(', '  private func isBackgroundEvent(']))
web = (source/'PluginSidebarView.swift').read_text()
script = web.split('  static let backgroundClickScript = #\"\"\"', 1)[1].split('\"\"\"#', 1)[0]
support = support.replace('// PRODUCTION_WEB_BACKGROUND_SCRIPT', 'let backgroundScript = #\"\"\"' + script + '\"\"\"#')
(output/'main.swift').write_text(support)
PY
xcrun swiftc "$output_dir/main.swift" -o "$output_dir/tests"
"$output_dir/tests"
