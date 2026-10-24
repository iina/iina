#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${INTERFACE_SHORTCUTS_OUTPUT_DIR:-$repo_dir/build/interface-shortcuts-tests}"
mkdir -p "$output_dir/module-cache"
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PY'
from pathlib import Path
import sys
repo, tests, out = map(Path, sys.argv[1:])
def extract(file, marker):
    text=(repo/'iina'/file).read_text();start=text.index(marker);end=text.index('{',start)+1;depth=1
    while depth:
        depth+=(text[end]=='{')-(text[end]=='}');end+=1
    return text[start:end]
support=(tests/'Support.swift').read_text()
support=support.replace('// PRODUCTION_DISPATCH',extract('PlayerWindowController.swift','  func handleKeyBinding('))
support=support.replace('// PRODUCTION_ESCAPE',extract('MainWindowController.swift','  func handleDefaultEscape('))
support=support.replace('// PRODUCTION_CROP_ENTRY',extract('MainMenuActions.swift','  func openCustomCrop()'))
support=support.replace('// PRODUCTION_INTERFACE',extract('MainWindowController.swift','  override func handleInterfaceCommand('))
support=support.replace('// PRODUCTION_WINDOW_EVENT',extract('MainWindow.swift','  override func sendEvent('))
support=support.replace('// PRODUCTION_ARROW_KEYS',extract('MainWindow.swift','  override func performKeyEquivalent(')+'\n'+extract('MainWindow.swift','  private func shouldFavorArrowKeyNavigation('))
files=['IINACommand.swift','StreamReader.swift','KeyCodeHelper.swift','KeyMapping.swift','KeyBindingCriterion.swift','KeyBindingItem.swift','KeyBindingDataLoader.swift','KeyBindingTranslator.swift','KeyRecordViewController.swift']
production='\n'.join((repo/'iina'/f).read_text().replace('import Mustache','') for f in files)
production+='\n'+'\n'.join(extract('OSDMessage.swift', marker) for marker in [
    'enum OSDFeedbackOrigin {', 'enum OSDFeedbackValue:', 'final class OSDFeedbackOrigins {', 'enum OSDCommandRouting {'])
(out/'main.swift').write_text(support+'\n'+production+'\n'+(tests/'main.swift').read_text())
PY
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/tests"
"$output_dir/tests" "$repo_dir" "$output_dir"
