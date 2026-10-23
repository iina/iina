#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
out="${1:-$root/build/subtitle-controls}"
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
support=(root/'other/tests/sidebar-slider-layout/support.swift').read_text()
ui='final class UIHelper {'+support.split('final class UIHelper {',1)[1]
helper=(root/'iina/UIHelper.swift').read_text().split('class UIHelper {',1)[0]
settings=(root/'iina/TrackSettings.swift').read_text()
subtitles=(root/'iina/SidebarSubtitlesPane.swift').read_text()
sidebar=(root/'iina/SidebarPane.swift').read_text()
group=extract(sidebar,'final class TrackSettingsGroupView:')
group=group.replace(extract(group,'  convenience init(player:'),'')
section=extract(sidebar,'final class TrackProcessingSection:')
section=section.replace(extract(section,'  convenience init(player:'),'')
core=(root/'iina/PlayerCore.swift').read_text()
styleReset='extension PlayerCore {'+'\n'.join(extract(core, '  func '+name+'(') for name in ['chooseSubFont','resetSubtitleStyle','setSubScale','setSubFont','setSubTextSize','setSubTextColor','setSubTextBorderSize','setSubTextBorderColor','setSubTextBgColor'])+'}\n'
extensions=(root/'iina/Extensions.swift').read_text()
styleReset+='extension NSColor {'+extract(extensions,'  var mpvColorString:')+'\n'+extract(extensions,'  convenience init?(mpvColorString')+'}\n'
styleReset+='extension Comparable {'+extract(extensions,'  func clamped(to range: ClosedRange<Self>)')+'}\n'
layout='class SidebarScrollView {'+extract(sidebar,'  class Container:')+'}\n'+group+'\n'+section
source=(root/'other/tests/subtitle-controls/support.swift').read_text()+'\n'+styleReset+'\n'+ui+'\n'+helper+'\n'+extract((root/'iina/SidebarTrackSelector.swift').read_text(),'class ColoredView:')+'\n'+(root/'iina/ConstraintsSugar.swift').read_text()+'\n'+(root/'iina/SidebarSliderView.swift').read_text()+'\n'+'\n'.join(extract(settings,m) for m in ['class SettingsTargetPopUp:','final class SubtitleRoleSelector:','enum SubtitleStyle {','private final class TrackSettingsHeadingCell:','class SidebarResetButton:'])+'\n'+layout+'\n'+'\n'.join(extract(subtitles,m) for m in ['fileprivate class SubDelayView:','fileprivate class SubPositionDelayView:','fileprivate class SubStyleView:'])+'\n'+extract(subtitles,'fileprivate func selectSubtitleStyleValue(')+'\n'+extract((root/'iina/SidebarAudioPane.swift').read_text(),'fileprivate class AudioDelayView:')+'\n'+(root/'other/tests/subtitle-controls/main.swift').read_text()
(out/'main.swift').write_text(source)
PY
xcrun swiftc "$out/main.swift" -o "$out/checks"
"$out/checks"
