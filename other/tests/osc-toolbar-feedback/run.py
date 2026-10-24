#!/usr/bin/env python3
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[3]
TESTS = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=ROOT / 'build/toolbar-icon-feedback-2026-10-24/focused')
parser.add_argument('--module-cache', type=Path, default=ROOT / 'build/DerivedData/ModuleCache.noindex')
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)

def extract(text, marker):
    start = text.index(marker)
    opening = text.index('{', start + len(marker))
    index, depth, quote, line_comment, block_comment = opening + 1, 1, False, False, 0
    while depth:
        if index >= len(text):
            raise ValueError('Unterminated declaration: ' + marker)
        char, pair = text[index], text[index:index + 2]
        if line_comment:
            if char == '\n': line_comment = False
        elif block_comment:
            if pair == '/*': block_comment += 1; index += 1
            elif pair == '*/': block_comment -= 1; index += 1
        elif quote:
            if char == '\\': index += 1
            elif char == '"': quote = False
        elif pair == '//': line_comment = True; index += 1
        elif pair == '/*': block_comment = 1; index += 1
        elif char == '"': quote = True
        elif char == '{': depth += 1
        elif char == '}': depth -= 1
        index += 1
    return text[start:index]

preference = (ROOT / 'iina/Preference.swift').read_text()
extensions = (ROOT / 'iina/Extensions.swift').read_text()
accessibility = (ROOT / 'iina/AccessibilityPreferences.swift').read_text()
toolbar = (ROOT / 'iina/OSCToolbarButton.swift').read_text()
main_window = (ROOT / 'iina/MainWindowController.swift').read_text()
sidebar = (ROOT / 'iina/SidebarController.swift').read_text()
support = (TESTS / 'Support.swift').read_text()
pieces = {
    'toolbarTypes': extract(preference, '  enum ToolBarButton:'),
    'symbols': extract(extensions, '  static func sf(_ names: [String],'),
    'tinted': extract(extensions, '  func tinted('),
    'adjustedDuration': extract(accessibility, '  static func adjustedDuration('),
    'controllerSetup': extract(main_window, '  private func setupOSCToolbarButtons('),
    'controllerNotification': extract(main_window, '  private func updateOSCToolbarButtons('),
    'controllerStates': extract(main_window, '  func updateOSCToolbarButtonStates()'),
    'pipState': extract(main_window, '  var pipStatus = PIPStatus.notInPIP'),
    'fullscreenState': extract(main_window, '  enum FullScreenState:'),
    'fullscreenProperty': extract(main_window, '  var fsState: FullScreenState'),
}
support = support.replace('// PRODUCTION_TOOLBAR_TYPES', pieces['toolbarTypes'])
support = support.replace('// PRODUCTION_SF', pieces['symbols'])
support = support.replace('// PRODUCTION_TINTED', pieces['tinted'])
support = support.replace('// PRODUCTION_ADJUSTED_DURATION', pieces['adjustedDuration'])
support = support.replace('// PRODUCTION_CONTROLLER_METHODS', '\n'.join(pieces[name] for name in [
    'controllerSetup', 'controllerNotification', 'controllerStates']))
support = support.replace('// PRODUCTION_PIP_STATE', pieces['pipState'])
support = support.replace('// PRODUCTION_FULLSCREEN_STATE', pieces['fullscreenState'])
support = support.replace('// PRODUCTION_FULLSCREEN_PROPERTY', pieces['fullscreenProperty'])
placements = {}
for marker, name in [('  private func replaceSideBar(', 'sidebarReplace'), ('  private func showSideBar(', 'sidebarShow')]:
    body = extract(sidebar, marker)
    placements[name] = body.index('panel.status = type') < body.index('mainWindow.updateOSCToolbarButtonStates()') < body.index('panel.view.setContent(')
body = extract(sidebar, '  func hideSideBar(side: Side, animate: Bool = true, after: @escaping () -> Void = {})')
placements['sidebarHide'] = body.index('panel.status = .hidden') < body.index('mainWindow.updateOSCToolbarButtonStates()') < body.index('NSAnimationContext.runAnimationGroup')
start = main_window.index('    case PK.enableLiveText.rawValue:')
placements['liveTextPreference'] = 'updateOSCToolbarButtonStates()' in main_window[start:main_window.index('    default:', start)]
assert all(placements.values()), placements
source = support + '\n' + toolbar + '\n' + (TESTS / 'main.swift').read_text()
generated = args.output / 'main.swift'
generated.write_text(source)
executable = args.output / 'checks'
subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(args.module_cache.resolve()),
                str(generated), '-o', str(executable)], check=True)
with (args.output / 'checks.txt').open('w') as log:
    result = subprocess.run([str(executable)], text=True, stdout=log, stderr=subprocess.STDOUT, timeout=15)
print((args.output / 'checks.txt').read_text(), end='')
if result.returncode:
    raise SystemExit(result.returncode)
(args.output / 'inputs.json').write_text(json.dumps({
    'status': 'passed',
    'productionFiles': {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in [
        'iina/OSCToolbarButton.swift', 'iina/Preference.swift', 'iina/Extensions.swift',
        'iina/AccessibilityPreferences.swift', 'iina/MainWindowController.swift', 'iina/SidebarController.swift']},
    'extractedDeclarations': {name: hashlib.sha256(text.encode()).hexdigest() for name, text in pieces.items()},
    'sourcePlacementChecks': placements,
    'boundaries': 'Real AppKit buttons/cells/windows and production symbols; controlled accessibility preference values. No activation, system preference writes or timing sleeps.'
}, indent=2) + '\n')
