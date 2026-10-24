#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${WINDOW_DRAG_OUTPUT_DIR:-$repo_dir/build/window-drag-tests}"
mkdir -p "$output_dir/module-cache"
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PY'
from pathlib import Path
import os,sys
repo,tests,out=map(Path,sys.argv[1:])
def extract(text,marker):
    start=text.index(marker);end=text.index('{',start)+1;depth=1
    while depth:
        depth+=(text[end]=='{')-(text[end]=='}');end+=1
    return text[start:end]
main=Path(os.environ.get('WINDOW_DRAG_MAIN_SOURCE',repo/'iina/MainWindowController.swift')).read_text()
methods='\n'.join(extract(main,m) for m in ['  override func mouseDown(with event:', '  override func mouseDragged(with event:', '  override func mouseUp(with event:', '  func windowDidResignKey('])
methods += '\n' + (extract(main,'  func cancelWindowDrag(') if '  func cancelWindowDrag(' in main else '  func cancelWindowDrag() {}')
methods=methods.replace('NSEvent.pressedMouseButtons','pressedMouseButtons')
window=Path(os.environ.get('WINDOW_DRAG_WINDOW_SOURCE',repo/'iina/MainWindow.swift')).read_text()
route=extract(window,'  override func sendEvent(')
source=(tests/'main.swift').read_text().replace('// PRODUCTION_HANDLERS',methods).replace('// PRODUCTION_ROUTING',route)
(out/'main.swift').write_text(source)
PY
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/tests"
"$output_dir/tests" "${1:-all}"
