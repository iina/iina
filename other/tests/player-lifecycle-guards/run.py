#!/usr/bin/env python3
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[3]
TESTS = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=ROOT / 'build/player-lifecycle-guards')
parser.add_argument('--module-cache', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
cache = args.module_cache.resolve()
if not cache.is_dir():
    raise SystemExit('Supply an existing compiler cache')

def extract(text, marker):
    start = text.index(marker)
    end = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

player = (ROOT / 'iina/PlayerCore.swift').read_text()
info = (ROOT / 'iina/PlaybackInfo.swift').read_text()
support = (TESTS / 'Support.swift').read_text()
support = support.replace('// PRODUCTION_STATE', extract(info, '  var state: PlayerState = .idle'))
flags = ['  private var hasSentMPVQuit = false', '  private var shutdownRequestedAfterStop = false']
assert all(flag in player for flag in flags)
support = support.replace('// PRODUCTION_SHUTDOWN_FLAGS', '\n'.join(flags))
methods = ['  func pause()', '  func resume()', '  func stop()', '  func shutdown()', '  func idleActiveChanged()',
           '  func seek(percent:', '  func seek(relativeSecond:', '  func seek(absoluteSecond:', '  func setSpeed(',
           '  func setTrack(', '  func getChapters()', '  func setAudioDelay(', '  func setSubDelay(', '  func loadExternalSubFile(',
           '  func toggleMute(', '  func setVolume(', '  func playChapter(']
support = support.replace('// PRODUCTION_METHODS', '\n'.join(extract(player, marker) for marker in methods))
generated = args.output / 'Support.swift'
generated.write_text(support)
executable = args.output / 'checks'
subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(cache), str(ROOT / 'iina/PlayerState.swift'),
                str(generated), str(TESTS / 'main.swift'), '-o', str(executable)], check=True)
result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=15)
(args.output / 'checks.txt').write_text(result.stdout + result.stderr)
print(result.stdout, end='')
if result.stderr:
    print(result.stderr, end='')
if result.returncode:
    raise SystemExit(result.returncode)
native = (ROOT / 'iina/MPVController.swift').read_text()
native_methods = ['  private func recordOSDFeedback(', '  func observe(', '  func setFlag(', '  func setInt(',
                  '  func setDouble(', '  func setString(', '  func setStringToDefault(', '  func getEnum',
                  '  func getInt(', '  func getDouble(', '  func getFlag(', '  func getString(', '  func getFilters(',
                  '  func removeFilter(', '  func getNode(', '  func setNode(', '  func addHook(',
                  '  private func setOptionFlag(', '  private func setOptionFloat(', '  private func setOptionInt(',
                  '  private func setOptionString(']
native_support = (TESTS / 'NativeSupport.swift').read_text().replace('// PRODUCTION_NATIVE_METHODS',
    '\n'.join(extract(native, marker) for marker in native_methods))
native_support = native_support.replace('// PRODUCTION_NODE', extract((ROOT / 'iina/MPVNode.swift').read_text(), 'class MPVNode {'))
native_source = args.output / 'NativeSupport.swift'
native_source.write_text(native_support)
native_main = args.output / 'main.swift'
native_main.write_text((TESTS / 'native-main.swift').read_text())
native_object = args.output / 'native.o'
subprocess.run(['xcrun', 'clang', '-Wall', '-Wextra', '-Werror', '-I', str(ROOT / 'deps/include'), '-c',
                str(TESTS / 'NativeFixture.c'), '-o', str(native_object)], check=True)
native_executable = args.output / 'native-checks'
subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(cache), '-I', str(ROOT / 'deps/include'),
                '-import-objc-header', str(TESTS / 'NativeBridge.h'), str(ROOT / 'iina/PlayerState.swift'),
                str(native_source), str(native_main), str(native_object), '-o', str(native_executable)], check=True)
result = subprocess.run([str(native_executable)], capture_output=True, text=True, timeout=15)
(args.output / 'native-checks.txt').write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr, end='')
if result.returncode:
    raise SystemExit(result.returncode)
hook_support = (TESTS / 'HookSupport.swift').read_text()
hook_support = hook_support.replace('// PRODUCTION_HOOK_VALUE', extract(native, 'struct MPVHookValue {'))
event_start = native.index('    case MPV_EVENT_HOOK:') + len('    case MPV_EVENT_HOOK:')
event_end = native.index('    case MPV_EVENT_PROPERTY_CHANGE:', event_start)
hook_support = hook_support.replace('// PRODUCTION_HOOK_EVENT', native[event_start:event_end])
hook_source = args.output / 'HookSupport.swift'
hook_source.write_text(hook_support)
hook_main = args.output / 'main.swift'
hook_main.write_text((TESTS / 'hook-main.swift').read_text())
hook_executable = args.output / 'hook-checks'
subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(cache), '-I', str(ROOT / 'deps/include'),
                '-import-objc-header', str(TESTS / 'NativeBridge.h'), str(hook_source), str(hook_main),
                str(native_object), '-o', str(hook_executable)], check=True)
result = subprocess.run([str(hook_executable)], capture_output=True, text=True, timeout=15)
(args.output / 'hook-checks.txt').write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr, end='')
if result.returncode:
    raise SystemExit(result.returncode)
(args.output / 'receipt.json').write_text(json.dumps({
    'status': 'passed', 'sources': {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
      for name in ['iina/PlayerCore.swift', 'iina/PlaybackInfo.swift', 'iina/PlayerState.swift', 'iina/MPVController.swift', 'iina/MPVNode.swift']},
    'boundaries': 'Actual public lifecycle methods and state-transition rules; controlled engine/background/window boundaries. No native engine, app activation or personal profile writes.'
}, indent=2) + '\n')
