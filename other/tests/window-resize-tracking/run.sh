#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
out="${RESIZE_TEST_OUTPUT_DIR:-$repo_dir/build/window-resize-tracking/tests}"
mkdir -p "$out"
python3 - "$repo_dir" "$test_dir" "$out" <<'PY'
from pathlib import Path
import os,sys
repo, tests, out = map(Path, sys.argv[1:])
source = (repo/'iina/MainWindow.swift').read_text()
model = source[source.index('struct WindowResizeSession {'):source.index('class MainWindow:')]
(out/'main.swift').write_text('import Cocoa\n' + model + (tests/'main.swift').read_text())
def extract(text, marker):
    start = text.index(marker)
    end = text.index('{', start) + 1
    balance = 1
    while balance:
        if text[end] == '{': balance += 1
        if text[end] == '}': balance -= 1
        end += 1
    return text[start:end]
source = Path(os.environ.get('RESIZE_MAIN_SOURCE',repo/'iina/MainWindowController.swift')).read_text()
methods = '\n'.join(extract(source, marker) for marker in [
    '  func windowWillResize(', '  func windowWillStartLiveResize(', '  func windowDidEndLiveResize('])
# Inject only the system pointer position; keep the production delegate methods intact.
methods = methods.replace('NSEvent.mouseLocation', 'testMouse')
grow = extract((repo/'iina/Extensions.swift').read_text(), '  func grow(toSize size:')
aspect = extract((repo/'iina/Extensions.swift').read_text(), '  var aspect: CGFloat {')
helpers = '\n'.join(extract(source, m) for m in ['  private var currentWindowAspectRatio:', '  private func setWindowAspectRatio('])
harness = (tests/'Delegate.swift').read_text().replace('// PRODUCTION_METHODS', methods).replace('// PRODUCTION_ASPECT_HELPERS', helpers)
(out/'delegate/main.swift').parent.mkdir(exist_ok=True)
(out/'delegate/main.swift').write_text('import Cocoa\n' + model + '\nextension NSSize {\n' + aspect + '\n' + grow + '\n}\n' + harness)
PY
xcrun swiftc "$out/main.swift" -o "$out/tests"
"$out/tests"
xcrun swiftc "$out/delegate/main.swift" -o "$out/delegate/tests"
"$out/delegate/tests"
