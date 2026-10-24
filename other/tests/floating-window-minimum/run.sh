#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="$repo_dir/build/floating-window-minimum-tests"
mkdir -p "$output_dir/module-cache"
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PY'
from pathlib import Path
import sys
repo, tests, output = map(Path, sys.argv[1:])
source = (repo / 'iina/MainWindowController.swift').read_text()
menu_source = (repo / 'iina/MainWindowMenuActions.swift').read_text()
appdata = (repo / 'iina/AppData.swift').read_text()
extensions = (repo / 'iina/Extensions.swift').read_text()
def extract(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    balance = 1
    end = opening + 1
    while balance:
        if text[end] == '{': balance += 1
        if text[end] == '}': balance -= 1
        end += 1
    return text[start:end]
constants = 'enum AppData {\n' + '\n'.join(line for line in appdata.splitlines() if 'static let mainWindowMinSize =' in line or 'static let floatingOSCWindowMinSize =' in line) + '\n}'
size_methods = '\n'.join(extract(extensions, marker) for marker in ['  var aspect: CGFloat {', '  func grow(toSize size:', '  func shrink(toSize size:', '  func satisfyMinSizeWithSameAspectRatio(', '  func crop(withAspect targetAspect: CGFloat)'])
rect_method = '\n'.join(extract(extensions, marker) for marker in ['  func centeredResize(to newSize:', '  func constrain(in biggerRect:'])
controller_methods = '\n'.join(extract(source, marker) for marker in ['  var minimumWindowSize:', '  private func applyNativeMinimumWindowSize()', '  private func updateMinimumWindowSize()', '  func windowFrameConstrainedToScreen(', '  private var currentWindowAspectRatio:', '  private func setWindowAspectRatio(', '  func setWindowToolbar()', '  func windowWillResize(', '  func windowFrameFromGeometry(', '  @objc func removeVideoViewBlackBars()'])
controller_methods += '\n' + extract(menu_source, '  @objc func menuChangeWindowSize(')
harness = (tests / 'NativeHarness.swift').read_text().replace('// PRODUCTION_CONSTANTS', constants).replace('// PRODUCTION_EXTENSIONS', 'extension NSSize {\n' + size_methods + '\n}\nextension NSRect {\n' + rect_method + '\n}').replace('// PRODUCTION_CONTROLLER_METHODS', controller_methods)
metrics = extract((repo / 'iina/FloatingOSCScale.swift').read_text(), 'enum FloatingOSCMetrics {')
metrics += '\n' + extract((repo / 'iina/MainWindow.swift').read_text(), 'struct WindowResizeSession {')
(output / 'main.swift').write_text('import Cocoa\n' + metrics + '\n' + (repo / 'iina/Regex.swift').read_text() + '\n' + (repo / 'iina/GeometryDef.swift').read_text() + '\n' + harness)
# Scope check all programmatic entrypoints and native initialization. These
# checks detect forgotten old constants; behavioral evidence is from Swift above.
for marker in ['  func windowWillResize(', '  func windowFrameFromGeometry(', '  @objc func handleMagnifyGesture(', '  func setWindowScale(', '  func handleVideoSizeChange(keepWindowSize:']:
    block = extract(source, marker)
    assert 'minimumWindowSize' in block, marker + ' missing floating-aware minimum'
    assert 'AppData.mainWindowMinSize' not in block, marker + ' bypasses computed minimum'
assert 'updateMinimumWindowSize()' in extract(source, '  private func setupOnScreenController(')
assert 'applyNativeMinimumWindowSize()' in extract(source, '  override func windowDidLoad()')
print('PASS: native initialization, layout switches and resize/geometry/pinch/windowScale/videoSizeChange entrypoints use computed minimum')
for marker in ['  private func updateMinimumWindowSize()', '  func windowWillResize(', '  @objc func removeVideoViewBlackBars()', '  func handleVideoSizeChange(keepWindowSize:', '  func setWindowScale(']:
    assert 'windowFrameConstrainedToScreen(' in extract(source, marker), marker + ' bypasses screen-aware floating clamp'
for marker in ['  func windowDidExitFullScreen(', '  func windowDidFailToEnterFullScreen(']:
    block = extract(source, marker)
    assert block.index('fsState.finishAnimating()') < block.index('updateMinimumWindowSize()'), marker + ' must restore minimum after returning to windowed state'
video = extract(source, '  func handleVideoSizeChange(keepWindowSize:')
titlebar = video.index('rect.size.height += titleBarView.frame.height')
assert 'windowFrameConstrainedToScreen(' in video[titlebar:], 'titlebar addition bypasses final screen containment'
print('PASS: fit-video crop, fullscreen restore and all final window-setting paths use screen-aware minimum clamp')
menu = extract(menu_source, '  @objc func menuChangeWindowSize(')
assert 'minimumWindowSize' in menu and 'AppData.mainWindowMinSize' not in menu
assert 'windowFrameConstrainedToScreen(' in menu
assert 'Preference.unlockWindowAspectRatio ? window.frame.size : window.aspectRatio' in menu
print('PASS: Smaller/Bigger menu uses effective minimum, screen clamp and finite unlocked frame aspect')
native_minimum = extract(source, '  private func applyNativeMinimumWindowSize()')
assert 'window.contentMinSize = window.contentRect(forFrameRect: frame).size' in native_minimum
toolbar = extract(source, '  func setWindowToolbar()')
assert 'applyNativeMinimumWindowSize()' in toolbar
assert 'setFrame(' not in toolbar, 'toolbar must not repair native sizing by forcing the frame afterward'
print('PASS: startup, native minimum updates and toolbar configuration use content/frame conversion without toolbar frame compensation')
PY
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/floating-window-minimum-tests"
"$output_dir/floating-window-minimum-tests"
