#!/usr/bin/env python3
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess

repo = Path(__file__).resolve().parents[3]
tests = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=repo / 'build/filter-window-ownership')
parser.add_argument('--module-cache', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)

def extract(text, marker):
    start = text.index(marker)
    end = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

filter_source = Path(os.environ.get('FILTER_WINDOW_OWNERSHIP_SOURCE', repo / 'iina/FilterWindowController.swift')).read_text()
menu = (repo / 'iina/MainMenuActions.swift').read_text()
window_menu = (repo / 'iina/MainWindowMenuActions.swift').read_text()
interactive = (repo / 'iina/InteractiveMode.swift').read_text()
methods = ['  private var editablePlayer:', '  func setFilters()', '  func addFilter(',
    '  func addFilterFromSheet(', '  func cancelNewFilter()', '  func reloadTable()',
    '  @IBAction func addFilterAction(', '  @IBAction func removeFilterAction(',
    '  @IBAction func toggleSavedFilterAction(', '  private func filtersAsString()',
    '  func tableView(_ tableView: NSTableView, setObjectValue', '  private func updateButtonStatus()']
support = (tests / 'Support.swift').read_text()
support = support.replace('// PRODUCTION_FILTER', '\n'.join(extract(filter_source, marker) for marker in methods))
support = support.replace('// PRODUCTION_SHEET', '\n'.join(extract(filter_source, marker) for marker in [
    '  @IBAction func sheetAddBtnAction(', '  @IBAction func sheetCancelBtnAction(']))
support = support.replace('// PRODUCTION_MAIN_MENU', extract(menu, '  func validateMenuItem('))
support = support.replace('// PRODUCTION_WINDOW_MENU', '\n'.join(extract(window_menu, marker) for marker in [
    '  func validateMenuItem(', '  @objc func menuSetDelogo(', '  @objc func menuSwitchToMiniPlayer(']))
support = support.replace('// PRODUCTION_CAN_ENTER', extract(interactive, '  var canEnter:'))
generated = args.output / 'Support.swift'
generated.write_text(support)
binary = args.output / 'checks'
subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(args.module_cache.resolve()),
    str(repo / 'iina/PlayerState.swift'), str(generated), str(tests / 'main.swift'), '-o', str(binary)], check=True)
env = os.environ.copy()
env['CFFIXED_USER_HOME'] = str(args.output / 'profile')
result = subprocess.run([str(binary)], env=env, capture_output=True, text=True, timeout=20)
(args.output / 'results.log').write_text(result.stdout + result.stderr)
print(result.stdout, end='')
if result.stderr:
    print(result.stderr, end='')
if result.returncode:
    raise SystemExit(result.returncode)
(args.output / 'inputs.json').write_text(json.dumps({name: hashlib.sha256(source.encode()).hexdigest()
    for name, source in [('FilterWindowController.swift', filter_source), ('MainMenuActions.swift', menu),
                         ('MainWindowMenuActions.swift', window_menu), ('InteractiveMode.swift', interactive)]}, indent=2) + '\n')
