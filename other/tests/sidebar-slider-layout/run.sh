#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
out="${1:-$root/build/sidebar-slider-layout}"
mkdir -p "$out"
python3 - "$root" "$out" <<'PY'
from pathlib import Path
import sys
root,out=map(Path,sys.argv[1:])
def extract(source, marker):
 start=source.index(marker);end=source.index('{',start)+1;depth=1
 while depth:
  if source[end]=='{':depth+=1
  elif source[end]=='}':depth-=1
  end+=1
 return source[start:end]
helper=(root/'iina/UIHelper.swift').read_text().split('class UIHelper {',1)[0]
colored=extract((root/'iina/SidebarTrackSelector.swift').read_text(),'class ColoredView:')
audio=(root/'iina/SidebarAudioPane.swift').read_text().split('fileprivate class AudioDelayView:',1)[1]
visibility='\n'.join(line for line in audio.splitlines()[:5] if 'override var shows' in line)
main=(root/'other/tests/sidebar-slider-layout/main.swift').read_text().replace('// AUDIO_VISIBILITY',visibility)
source=(root/'other/tests/sidebar-slider-layout/support.swift').read_text()+'\n'+helper+'\n'+colored+'\n'+(root/'iina/ConstraintsSugar.swift').read_text()+'\n'+(root/'iina/SidebarSliderView.swift').read_text()+'\n'+main
(out/'main.swift').write_text(source)
PY
xcrun swiftc "$out/main.swift" -o "$out/checks"
"$out/checks"
