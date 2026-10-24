#!/usr/bin/env python3
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=ROOT / 'build/settings-restart-presenter-2026-10-25')
args = parser.parse_args()
CACHE = (ROOT / 'build/sidebar-osd-tests/module-cache').resolve()
if not CACHE.is_dir():
    raise SystemExit(f'Reuse existing module cache: {CACHE}')
source = ROOT / 'iina/AppRestart.swift'
text = source.read_text()
if 'static func confirmSettingsChange(in ' not in text:
    raise SystemExit('AppRestart.confirmSettingsChange(in:) production source is not ready yet')
# Replace only the OS relaunch/termination boundary. All presenter/state cleanup
# and native alert code remains actual production source.
marker = '  static func restart(restoring window: SettingsWindow) throws {'
start = text.index(marker)
body = start + len(marker)
depth = 1
end = body
while depth:
    if text[end] == '{': depth += 1
    elif text[end] == '}': depth -= 1
    end += 1
replacement = marker + '''
    Probe.restartRequests.append(window)
    discardRestoreRequest()
    if Probe.failRestart { throw CocoaError(.executableNotLoadable) }
    prepareForImmediateRestart(window)
  }'''
production = text[:start] + replacement + text[end:]
records = []
with tempfile.TemporaryDirectory(prefix='iina-settings-restart-presenter-') as temporary:
    temporary = Path(temporary)
    patched = temporary / 'AppRestart.swift'
    patched.write_text(production)
    bundle = temporary / 'PresenterChecks.app'
    executable = bundle / 'Contents/MacOS/PresenterChecks'
    executable.parent.mkdir(parents=True)
    resources = bundle / 'Contents/Resources/en.lproj'
    resources.mkdir(parents=True)
    (resources / 'Localizable.strings').write_bytes((ROOT / 'iina/en.lproj/Localizable.strings').read_bytes())
    (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'org.iina.tests.settings-restart-presenter.' + uuid.uuid4().hex,
        'CFBundleName': 'Settings Restart Presenter Checks', 'CFBundleExecutable': executable.name,
        'CFBundlePackageType': 'APPL', 'NSPrincipalClass': 'NSApplication', 'LSUIElement': True,
    }))
    files = [patched, ROOT / 'iina/AppAccentColor.swift', ROOT / 'iina/AccentControls.swift',
             Path(__file__).with_name('main.swift')]
    subprocess.run(['xcrun', 'swiftc', '-target', 'arm64-apple-macos12', '-module-cache-path',
                    str(CACHE), *map(str, files), '-o', str(executable)], check=True)
    for appearance in ['light', 'dark']:
        completed = subprocess.run([str(executable), appearance], capture_output=True, text=True, timeout=30)
        if completed.returncode:
            raise SystemExit(completed.stdout + completed.stderr)
        print(appearance + ': ' + completed.stdout.strip())
        records.append({'appearance': appearance, 'result': completed.stdout.strip()})
output = args.output / 'native-checks.json'
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps({'productionSourceSha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'deploymentTarget': 'arm64-apple-macos12', 'checks': records,
    'boundary': 'Actual production presenter/state code and AccentControls; only OS restart/termination method body replaced with recording boundary.'}, indent=2) + '\n')
