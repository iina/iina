#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
out="${SCREENSHOT_SOUND_OUTPUT_DIR:-$repo_dir/build/screenshot-sound-tests}"
mkdir -p "$out/module-cache"
python3 - "$repo_dir" "$test_dir" "$out" <<'PY'
from pathlib import Path
import os, re, sys
repo, tests, out = map(Path, sys.argv[1:])
def extract(text, marker):
    start = text.index(marker)
    end = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]
player = Path(os.environ.get('SCREENSHOT_PLAYER_SOURCE', repo/'iina/PlayerCore.swift')).read_text()
mpv = Path(os.environ.get('SCREENSHOT_MPV_SOURCE', repo/'iina/MPVController.swift')).read_text()
prefs = (repo/'iina/Preference.swift').read_text()
keys = ['screenshotSaveToFile', 'screenshotCopyToClipboard', 'screenshotShowPreview', 'screenshotPlaySound', 'screenshotIncludeSubtitle', 'enableFFmpegImageDecoder']
declarations = '\n'.join(re.search(r'    static let ' + key + r' = Key\("[^"]+"\)', prefs)[0] for key in keys)
defaults = ',\n'.join('Key.' + key + '.rawValue: ' + re.search(r'\.'+key+r': (true|false),', prefs)[1] for key in keys)
support = (tests/'Support.swift').read_text().replace('// PRODUCTION_KEYS', declarations).replace('// PRODUCTION_DEFAULTS', defaults)
osd = (repo/'iina/OSDMessage.swift').read_text()
support = support.replace('// PRODUCTION_OSD_ROUTING', '\n'.join(extract(osd, marker) for marker in [
    'enum OSDFeedbackOrigin {', 'enum OSDFeedbackValue:', 'final class OSDFeedbackOrigins {', 'enum OSDCommandRouting {']))
methods = [extract(player, '  private final class ScreenshotRequest {')]
for marker in ['  private static let screenshotQueue', '  private var screenshotRequestSequence', '  private var screenshotRequests']:
    start=player.index(marker);methods.append(player[start:player.index('\n',start)])
for marker in ['  func screenshot(fromKeyBinding', '  private func isCurrentScreenshotRequest(', '  private static func removeTemporaryScreenshot(',
               '  private func finishScreenshotRequest(', '  func cancelScreenshotRequests(', '  func screenshotCallback(',
               '  private func screenshotFileReady(', '  private func finishDecodedScreenshot(']:
    methods.append(extract(player,marker))
callback = '\n'.join(methods).replace('NSPasteboard.general', 'TestPasteboard.shared').replace('ScreenshootOSDView()', 'PreviewFixture()')
callback = callback.replace('private func ', 'func ').replace('private static func ', 'static func ')
callback = callback.replace('private final class ScreenshotRequest', 'final class ScreenshotRequest')
decoder = extract(player, 'private enum ScreenshotImageDecoder {')
decoder = decoder.replace('    autoreleasepool {', '    DecodeObserver.shared.begin()\n    return autoreleasepool {', 1)
support = support.replace('// PRODUCTION_DECODER', decoder)
support = support.replace('// PRODUCTION_USERDATA', extract(mpv,'  struct UserData {'))
support = support.replace('// PRODUCTION_PARSE', extract((repo/'iina/MPVNode.swift').read_text(), '  static func parse('))
support = support.replace('// PRODUCTION_ASYNC', '\n'.join(extract(mpv, marker) for marker in [
    '  private func makeCArgs(', '  private func recordOSDFeedback(', '  func asyncCommand(']))
reply = mpv[mpv.index('    case MPV_EVENT_COMMAND_REPLY:') + len('    case MPV_EVENT_COMMAND_REPLY:'):mpv.index('    case MPV_EVENT_QUEUE_OVERFLOW:')]
support = support.replace('// PRODUCTION_REPLY', reply)
helper = extract(player, 'private enum ScreenshotSound {')
source = support.replace('// PRODUCTION_SCREENSHOT', callback) + '\n' + helper + '\n' + (tests/'main.swift').read_text()
(out/'main.swift').write_text(source)
PY
xcrun clang -Wall -Wextra -Werror -I "$repo_dir/deps/include" -c "$test_dir/EventFixture.c" -o "$out/events.o"
xcrun swiftc -I "$repo_dir/deps/include" -import-objc-header "$test_dir/Bridge.h" -module-cache-path "$out/module-cache" "$out/main.swift" "$out/events.o" -o "$out/tests"
"$out/tests"
