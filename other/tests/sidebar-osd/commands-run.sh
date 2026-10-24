#!/bin/bash
set -euo pipefail
tests="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$tests/../../.." && pwd)"
out="${SIDEBAR_OSD_COMMAND_OUTPUT_DIR:-$repo/build/sidebar-osd-command-tests}"
mkdir -p "$out/module-cache"
python3 - "$repo" "$tests" "$out" <<'PY'
from pathlib import Path
import json,sys
repo,tests,out=map(Path,sys.argv[1:])
# Reuse only the existing production extraction and mocks. Its 211-check entry
# and files remain unchanged; command checks have a separate executable/output.
generator=(tests/'run.sh').read_text().split("<<'PY'\n",1)[1].split('\nPY\n',1)[0]
sys.argv=['sidebar-osd-generator',str(repo),str(tests),str(out)]
exec(compile(generator,'sidebar-osd-generator','exec'),{})
source=(out/'main.swift').read_text().split('// Pure value/key matching',1)[0]
player=(out/'source-PlayerCore.swift').read_text()
message=(out/'source-OSDMessage.swift').read_text()
mpv=(out/'source-MPVController.swift').read_text()
def extract(text,marker):
 start=text.index(marker);end=text.index('{',start)+1;depth=1
 while depth:
  depth+=(text[end]=='{')-(text[end]=='}');end+=1
 return text[start:end]
seek=player[player.index('  private enum CropRefreshUpdate:'):player.index('  var isRefreshingPausedCrop:',player.index('  private enum CropRefreshUpdate:'))]
seek+='\n'+'\n'.join(extract(player,m) for m in ['  var isRefreshingPausedCrop:', '  var shouldShowSeekOSD:', '  func userInitiatedSeek(', '  func cancelUserInitiatedSeek('])
seek+='\n  var testSeekToken:UUID? { userSeekOSDIntent?.token }\n'
source=source.replace('    var state=State(),disableOSDForFileLoading=false','    var trackSelectionGeneration=1\n    var state=State(),disableOSDForFileLoading=false')
source=source.replace('  let osdFeedbackOrigins =',seek+'\n  let osdFeedbackOrigins =',1)
commands='\n'.join(extract(mpv,m) for m in ['  private func makeCArgs(', '  private final class SeekOSDTicket {', '  private func prepareCommandOSD(', '  func command(_ command:', '  func command(rawString:'])
source=source.replace('  unowned let player:PlayerFixture',commands+'\n  func chkErr(_ status:Int32) { if status < 0 { errors+=1 } }\n  unowned let player:PlayerFixture',1)
source=source.replace('enum Logger {enum Level {case debug,error}}','enum Logger {enum Level {case debug,error};static func fatal(_ message:String)->Never {fatalError(message)}}')
source=source.replace('  var failNext=false,writes:',(tests/'CommandEngine.swift').read_text()+'\n  var failNext=false,writes:',1)
source=source.replace('var mpv:OpaquePointer! {OpaquePointer(Unmanaged.passUnretained(native).toOpaque())}','var mpv:OpaquePointer! {native.available ? OpaquePointer(Unmanaged.passUnretained(native).toOpaque()):nil}')
source+='\n'+extract(message,'enum OSDCommandRouting {')+'\n'+(tests/'CommandSupport.swift').read_text()
source+='\n'+(tests/'command-tests.swift').read_text()
(out/'main.swift').write_text(source)
manifest=json.loads((out/'inputs.json').read_text())
(out/'inputs.json').write_text(json.dumps(manifest,indent=2)+'\n')
PY
if [[ "${SIDEBAR_OSD_COMMAND_GENERATE_ONLY:-0}" == 1 ]]; then exit 0; fi
xcrun swiftc -warnings-as-errors -module-cache-path "$out/module-cache" "$out/main.swift" -o "$out/tests"
"$out/tests" | tee "$out/results.log"
