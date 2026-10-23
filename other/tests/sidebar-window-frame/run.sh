#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${SIDEBAR_FRAME_OUTPUT_DIR:-$repo_dir/build/sidebar-window-frame-tests}"
mkdir -p "$output_dir/module-cache"
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PYCODE'
from pathlib import Path
import sys, os
repo, tests, output = map(Path, sys.argv[1:])
def extract(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    balance, end = 1, opening + 1
    while balance:
        if text[end] == '{': balance += 1
        if text[end] == '}': balance -= 1
        end += 1
    return text[start:end]
support = (tests / 'Support.swift').read_text()
main = (repo / 'iina/MainWindowController.swift').read_text()
support = support.replace('// PRODUCTION_OSC_CLICK_ACTION', extract((repo / 'iina/Preference.swift').read_text(), '  enum OSCClickAction:'))
startup = extract(main, '  override func windowDidLoad()')
registration = startup.index('    fadeableViews.add(oscFloatingView)')
assert startup.index('    showUI()', registration) < startup.index('    // other initialization', registration)
visibility = '\n'.join(extract(main, marker) for marker in ['  override func mouseEntered(with event:', '  override func mouseExited(with event:', '  override func mouseMoved(with event:', '  private func refreshSeekTimeAndThumbnail(from event:', '  private func isPointInPlaySlider(', '  private func isSeekPreviewAvailable(', '  func cancelSeekPreviewHover()', '  func hideSeekPreview()', '  func hideUIFromOSC()', '  func restoreUIFromVideoClick(', '  func resumeUIAutoRevealIfSidebarsClosed()', '  func restoreUIFromSidebarBackground()', '  @objc func hideUIAndCursor()', '  func hideUI(force:', '  func trackPluginMenu(', '  func showUI()', '  func updateTimer()', '  private func destroyTimer()', '  private func createTimer()', '  var standardWindowButtons:'])
start = main.index('    fadeableViews.add(titleBarView, visibilityHandler:')
end = main.index('    fadeableViews.add(additionalInfoView)', start)
visibility += '\n  func installHeaderVisibility() {\n' + main[start:end] + '\n  }'
visibility = visibility.replace('override func mouseMoved', 'func mouseMoved').replace('override func mouseEntered', 'func mouseEntered').replace('override func mouseExited', 'func mouseExited')
visibility = visibility.replace('titleBarView.setRevealed', '(titleBarView as! Titlebar).setRevealed').replace('titleBarView.finishHiding', '(titleBarView as! Titlebar).finishHiding')
support = support.replace('// PRODUCTION_HEADER_VISIBILITY', visibility)
support = support.replace('// PRODUCTION_SEEK_PREVIEW_LAYOUT', '\n'.join(extract(main, marker).replace('private func', 'func') for marker in ['  private func updateTimePreview(_ percentage:', '  private func positionSeekPreview(']))
support = support.replace('// PRODUCTION_VIDEO_CONSTRAINTS', extract(main, '  private func setupVideoContainerConstraints()'))
accessory_start = main.index('    osdView.padding(.trailing(greaterThan: 8)')
accessory_end = main.index('    // buffer indicator view', accessory_start)
support = support.replace('// PRODUCTION_ACCESSORY_CONSTRAINTS', main[accessory_start:accessory_end])
# Bottom OSC avoidance retains optional insets; the header has no sidebar insets.
titlebar = (repo / 'iina/Titlebar.swift').read_text()
support = support.replace('// PRODUCTION_CHROME_PRIORITIES', 'sidebarInsetPriority = .init(NSLayoutConstraint.Priority.fittingSizeCompression.rawValue - 1)')
top_start = titlebar.index('      oscView.padding(.trailing(6)')
top_end = titlebar.index('\n    }\n', top_start)
support = support.replace('// PRODUCTION_TOP_OSC_CONSTRAINTS', titlebar[top_start:top_end])
groups_start = main.index('      oscTopMainView.addView(oscVolumeView')
groups_end = main.index('    case .bottom:', groups_start)
support = support.replace('// PRODUCTION_TOP_OSC_GROUPS', main[groups_start:groups_end])
source = 'fileprivate let UIAnimationDuration = 0.25\n' + (repo / 'iina/FadeableViewController.swift').read_text() + '\n' + extract(main, 'fileprivate extension NSStackView.VisibilityPriority') + '\n' + support + '\n' + (repo / 'iina/ConstraintsSugar.swift').read_text() + '\n' + (repo / 'iina/TranslucentView.swift').read_text() + '\n' + (repo / 'iina/TimeLabelOverflowedStackView.swift').read_text()
source += '\n' + titlebar
source += '\n' + (repo / 'iina/FloatingOSCScale.swift').read_text()
source += '\n' + (repo / 'iina/ThumbnailPeekView.swift').read_text()
source += '\n' + (repo / 'iina/TimePreviewView.swift').read_text()
source += '\n' + (repo / 'iina/SideBar.swift').read_text().split('class SidebarViewController:')[0]
source += '\n' + Path(os.environ.get('SIDEBAR_CONTROLLER_SOURCE', str(repo / 'iina/SidebarController.swift'))).read_text()
test_main = (tests / 'main.swift').read_text()
test_main = test_main.replace('var expectedFrame: NSRect?', 'runPanelDepthChecks()\nvar expectedFrame: NSRect?')
source += '\n' + (tests / 'panel-depth.swift').read_text()
if os.environ.get('HEADER_ONLY'):
    test_main = test_main[:test_main.index('// A queued correction')] + test_main[test_main.index('class HeaderTrackingEvent:'): ]
source += '\n' + (repo / 'iina/OSCFloatingView.swift').read_text() + '\n' + test_main
source += '\n' + (tests / 'seek-preview.swift').read_text()
cell = (repo / 'iina/PlaySliderCell.swift').read_text()
source += '\nclass SeekPreviewSliderCellFixture: NSSliderCell {\n  var playerCore: SeekPreviewPlayerFixture!\n  var isPausedBeforeSeeking = false\n' + extract(cell, '  override func startTracking(') + '\n' + extract(cell, '  override func stopTracking(') + '\n}\n'
(output / 'main.swift').write_text(source)
PYCODE
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/sidebar-window-frame-tests"
"$output_dir/sidebar-window-frame-tests" "$@"
