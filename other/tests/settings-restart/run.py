from pathlib import Path
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parents[3]
output = root / 'build/settings-restart-2026-10-24/hooks'
output.mkdir(parents=True, exist_ok=True)
items = (root / 'iina/SettingsItem.swift').read_text()
advanced = (root / 'iina/SettingsPageAdvanced.swift').read_text()

def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

observer = block(items, 'final class SettingsRestartChangeObserver:')
chooser = block(items, 'class FileChooserView {')
editor = block(advanced, 'fileprivate class MPVOptionsEditor:').replace('fileprivate class', 'class', 1)
master = block(advanced, '.requiresRestart { _ in').split('_ in', 1)[1].rsplit('}', 1)[0]
extracted = output / 'ExtractedHooks.swift'
extracted.write_text('import Cocoa\n' + observer + '\n' + chooser + '\n' + editor + '\n' +
                     'func hasAdvancedStartupEffect() -> Bool { return ' + master + '\n}\n')
executable = output / 'hook-checks'
subprocess.run(['xcrun', 'swiftc', '-target', 'arm64-apple-macos12', '-module-cache-path',
               str((root / 'build/sidebar-osd-tests/module-cache').resolve()), str(extracted),
               str(Path(__file__).with_name('Support.swift')), str(Path(__file__).with_name('main.swift')),
               '-o', str(executable)], check=True)
result = subprocess.run([str(executable)], text=True, capture_output=True, timeout=20)
(output / 'checks.log').write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr)
assert result.returncode == 0
assert items.index('initBinding()\n      observeRestartChanges') > 0
assert '.bindTo(.httpProxy)\n          .requiresRestart()' in (root / 'iina/SettingsPageNetwork.swift').read_text()
assert '.bindTo(.ytdlSearchPath)\n              .requiresRestart()' in (root / 'iina/SettingsPageNetwork.swift').read_text()
assert '.bindTo(.useMediaKeys)\n          .requiresRestart()' in (root / 'iina/SettingsPageKeyBindings.swift').read_text()
assert '.bindTo(.forceDedicatedGPU)\n          .requiresRestart()' in (root / 'iina/SettingsPageVideo.swift').read_text()
(output / 'receipt.json').write_text(json.dumps({'runtime': result.stdout.strip(),
    'deploymentTarget': 'arm64-apple-macos12',
    'boundaries': 'Actual observer, file chooser, and MPV editor methods. Native inactive windows, isolated defaults; controlled text/table editing and panel/drop inputs. No player activation or personal preferences.',
    'sources': {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in [
        'iina/SettingsItem.swift', 'iina/SettingsPageAdvanced.swift', 'iina/SettingsPageNetwork.swift',
        'iina/SettingsPageKeyBindings.swift', 'iina/SettingsPageVideo.swift']}}, indent=2) + '\n')
