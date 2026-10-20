#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
out="${SCREENSHOT_SOUND_OUTPUT_DIR:-$repo_dir/build/screenshot-sound-tests}"
mkdir -p "$out/module-cache"
python3 - "$repo_dir" "$test_dir" "$out" <<'PY'
from pathlib import Path
import re, sys
repo, tests, out = map(Path, sys.argv[1:])
def extract(text, marker):
    start = text.index(marker)
    end = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]
player = (repo/'iina/PlayerCore.swift').read_text()
prefs = (repo/'iina/Preference.swift').read_text()
keys = ['screenshotSaveToFile', 'screenshotCopyToClipboard', 'screenshotShowPreview', 'screenshotPlaySound']
declarations = '\n'.join(re.search(r'    static let ' + key + r' = Key\("[^"]+"\)', prefs)[0] for key in keys)
defaults = ',\n'.join('Key.' + key + '.rawValue: ' + re.search(r'\.'+key+r': (true|false),', prefs)[1] for key in keys)
support = (tests/'Support.swift').read_text().replace('// PRODUCTION_KEYS', declarations).replace('// PRODUCTION_DEFAULTS', defaults)
callback = extract(player, '  func screenshotCallback()').replace('NSPasteboard.general', 'TestPasteboard.shared').replace('ScreenshootOSDView()', 'PreviewFixture()')
helper = extract(player, 'private enum ScreenshotSound {')
source = support.replace('// PRODUCTION_CALLBACK', callback) + '\n' + helper + '\n' + (tests/'main.swift').read_text()
(out/'main.swift').write_text(source)
PY
xcrun swiftc -module-cache-path "$out/module-cache" "$out/main.swift" -o "$out/tests"
"$out/tests"
