"""Compile real appearance policy/exports/bridge; run nonactivating native checks."""
from pathlib import Path
import argparse
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[3]
TESTS = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=ROOT / 'build/plugin-appearance-2026-10-24')
parser.add_argument('--module-cache', type=Path, default=ROOT / 'build/sidebar-osd-tests/module-cache')
args = parser.parse_args()
args.module_cache = args.module_cache.resolve()
args.output.mkdir(parents=True, exist_ok=True)

def literal(source, marker):
    body = source.split(marker + ' """', 1)[1].split('\n"""', 1)[0]
    return '"""' + body + '\n"""'

hub = (ROOT / 'iina/JavascriptMessageHub.swift').read_text()
standalone = (ROOT / 'iina/JavascriptAPIStandaloneWindow.swift').read_text()
generated = args.output / 'GeneratedScripts.swift'
generated.write_text('enum FixtureScripts {\n  static let messageBridge = ' +
                     literal(hub, 'static let bridgeScript =') +
                     '\n  static let simpleModeHTML = ' +
                     literal(standalone, 'fileprivate let simpleModeHTMLString =') + '\n}\n')
instance = (ROOT / 'iina/JavascriptPluginInstance.swift').read_text()
assert instance.index('"appearance": JavascriptAPIAppearance') < instance.index('if !isGlobal'), 'API must register in normal and global contexts'
for name in ['PluginSidebarView.swift', 'PluginOverlayView.swift', 'PluginStandaloneWindow.swift']:
    source = (ROOT / 'iina' / name).read_text()
    assert 'PluginAppearanceBridge(webView: webView)' in source
    assert 'appearanceBridge?.prepareForNavigation()' in source
    assert 'appearanceBridge?.didFinishNavigation()' in source
    assert 'appearanceBridge?.invalidate()' in source
command = ['xcrun', 'swiftc', '-D', 'PLUGIN_APPEARANCE_TESTING', '-target', f'{platform.machine()}-apple-macos12.0',
           '-module-cache-path', str(args.module_cache), str(ROOT / 'iina/AppAccentColor.swift'),
           str(ROOT / 'iina/PluginAppearanceBridge.swift'), str(ROOT / 'iina/JavascriptAPIAppearance.swift'),
           str(TESTS / 'Support.swift'), str(generated), str(TESTS / 'main.swift'),
           '-o', str(args.output / 'appearance-checks')]
subprocess.run(command, check=True)
result = subprocess.run([str(args.output / 'appearance-checks'), str(args.output.resolve())], capture_output=True, text=True, timeout=50)
(args.output / 'checks.txt').write_text(result.stdout + result.stderr)
print(result.stdout, end='')
if result.stderr:
    print(result.stderr, end='')
raise SystemExit(result.returncode)
