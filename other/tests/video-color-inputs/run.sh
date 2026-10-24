#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
out="${1:-$root/build/video-color-inputs}"
mkdir -p "$out"
python3 - "$root" "$out" <<'PY'
from pathlib import Path
import sys
root,out=map(Path,sys.argv[1:])
def extract(source,marker):
 start=source.index(marker);end=source.index('{',start)+1;depth=1
 while depth:
  if source[end]=='{':depth+=1
  elif source[end]=='}':depth-=1
  end+=1
 return source[start:end]
ui='final class UIHelper {'+(root/'other/tests/sidebar-slider-layout/support.swift').read_text().split('final class UIHelper {',1)[1]
ui=ui.replace('font: NSFont) -> NSTextField','font: NSFont, canCompress: Bool = true) -> NSTextField')
source=(root/'other/tests/video-color-inputs/support.swift').read_text()+'\n'+ui+'\n'+extract((root/'iina/SidebarSliderView.swift').read_text(),'final class SidebarInputField:')+'\n'+(root/'iina/ConstraintsSugar.swift').read_text()+'\nfileprivate let ui = UIHelper.shared\n'+extract((root/'iina/SidebarVideoPane.swift').read_text(),'fileprivate class EqualizerView:')+'\n'+(root/'other/tests/video-color-inputs/main.swift').read_text()
(out/'main.swift').write_text(source)
PY
xcrun swiftc "$out/main.swift" -o "$out/checks"
"$out/checks"
