#!/bin/bash
set -euo pipefail
tests="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$tests/../../.." && pwd)"
out="${SIDEBAR_OSD_OUTPUT_DIR:-$repo/build/sidebar-osd-tests}"
mkdir -p "$out/module-cache"
python3 - "$repo" "$tests" "$out" <<'PY'
from pathlib import Path
import hashlib,json,os,sys
repo,tests,out=map(Path,sys.argv[1:])
sources={name:Path(os.environ.get(env,repo/'iina'/name)).read_text() for name,env in [('PlayerCore.swift','SIDEBAR_OSD_PLAYER_SOURCE'),('OSDMessage.swift','SIDEBAR_OSD_MESSAGE_SOURCE'),('MPVController.swift','SIDEBAR_OSD_MPV_SOURCE')]}
def extract(text,marker):
 start=text.index(marker);end=text.index('{',start)+1;depth=1
 while depth:
  depth+=(text[end]=='{')-(text[end]=='}');end+=1
 return text[start:end]
player,message,mpv=[sources[n] for n in ['PlayerCore.swift','OSDMessage.swift','MPVController.swift']]
policy='\n'.join(extract(message,m) for m in ['enum OSDFeedbackOrigin {','enum OSDFeedbackValue:','final class OSDFeedbackOrigins {'])
cases=message[message.index('enum OSDMessage {'):message.index('  var isSettingFeedback:',message.index('enum OSDMessage {'))]
policy+='\n'+cases+'\n'+'\n'.join(extract(message,m) for m in ['  var isSettingFeedback:', '  var isDisabled:', '  var alwaysEnabled:'])+'\n}'
context=player[player.index('  let osdFeedbackOrigins ='):player.index('  private enum CropRefreshUpdate:',player.index('  let osdFeedbackOrigins ='))]
delivery=extract(player,'  func sendOSD(')
mutations='\n'.join(extract(mpv,m) for m in ['  func setFlag(', '  func setInt(', '  func setDouble(', '  func setString(', '  private func osdValue('])
if '  private func recordOSDFeedback(' in mpv:mutations+='\n'+extract(mpv,'  private func recordOSDFeedback(')
observer=extract(mpv,'  private func handlePropertyChange(')
prefix=observer[:observer.index('    switch name {')]+ '    switch name {\n'
for start,end in [('MPVOption.PlaybackControl.speed','MPVOption.PlaybackControl.loopPlaylist'),('MPVOption.Video.hwdec','MPVOption.Video.videoRotate'),('MPVOption.Audio.mute','MPVOption.Audio.volume'),('MPVOption.Audio.audioDelay','MPVOption.Subtitles.subVisibility'),('MPVOption.Equalizer.brightness','MPVOption.Equalizer.gamma')]:
 prefix+=observer[observer.index('    case '+start+':'):observer.index('    case '+end,observer.index('    case '+start+':'))]
mutations+='\n'+prefix+'    default: break\n    }\n  }'
support=(tests/'Support.swift').read_text().replace('// PRODUCTION_CONTEXT',context).replace('// PRODUCTION_DELIVERY',delivery).replace('// PRODUCTION_PLAYER_OBSERVATION',extract(player,'  func speedChanged('))
native=(tests/'Native.swift').read_text().replace('// PRODUCTION_MPV_METHODS',mutations)
(out/'main.swift').write_text(policy+'\n'+support+'\n'+native+'\n'+(tests/'main.swift').read_text()+'\n'+(tests/'native-tests.swift').read_text())
for name,source in sources.items():(out/('source-'+name)).write_text(source)
(out/'inputs.json').write_text(json.dumps({name:hashlib.sha256(source.encode()).hexdigest() for name,source in sources.items()},indent=2)+'\n')
PY
xcrun swiftc -warnings-as-errors -module-cache-path "$out/module-cache" "$out/main.swift" -o "$out/tests"
"$out/tests" | tee "$out/results.log"
