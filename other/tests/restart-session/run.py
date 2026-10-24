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
parser.add_argument('--module-cache', type=Path, default=ROOT / 'build/sidebar-osd-tests/module-cache')
parser.add_argument('--output', type=Path, default=ROOT / 'build/restart-session-2026-10-24')
args = parser.parse_args()
CACHE = args.module_cache.resolve()
if not CACHE.is_dir():
    raise SystemExit(f'Reuse an existing compiler cache: {CACHE}')

# Assert integration placement against actual production source, without copying
# those large controllers or simulating their geometry implementation.
player = (ROOT / 'iina/PlayerCore.swift').read_text()
delegate = (ROOT / 'iina/AppDelegate.swift').read_text()
main = (ROOT / 'iina/MainWindowController.swift').read_text()
restart = (ROOT / 'iina/AppRestart.swift').read_text()
source_checks = 0

def check(value, label):
    global source_checks
    if not value:
        raise AssertionError(label)
    source_checks += 1

quit_body = delegate.split('func applicationShouldTerminate(', 1)[1]
check(quit_body.index('AppRestart.captureSessionIfRequested()') < quit_body.index('isTerminating = true') < quit_body.index('window.close()'),
      'actual termination captures before close/shutdown')
launch = delegate.split('func applicationDidFinishLaunching(', 1)[1].split('/** Show welcome window', 1)[0]
check(launch.index('AppRestartSession.consume()') < launch.index('getReady()'), 'handoff consumed before media/plugin readiness')
check(launch.index('SettingsWindow.default.show()') < launch.index('AppRestartSession.restore('), 'Settings shown immediately before asynchronous media restore')
check('!commandLineStatus.isCommandLine && !restoreSettings' in launch, 'explicit restore skips ordinary initial window')
check('PluginAppearance.startObserving()' in delegate, 'shared appearance source bootstrapped')
notify = player.split('func notifyWindowVideoSizeChanged()', 1)[1].split('/// Synchronize', 1)[0]
check(notify.index('AppRestartSession.applyWindowFrame(self)') < notify.index('currentController.showWindow(self)'), 'saved frame applied before initial show')
check('info.state == .loaded && !AppRestartSession.isRestoring(self)' in notify, 'ordinary autoplay/fullscreen preferences bypassed during explicit restore')
check('AppRestartSession.windowReady(self)' in notify, 'readiness delivered from real window lifecycle')
check('AppRestartSession.seekStarted(self)' in player and 'AppRestartSession.playbackRestarted(self)' in player, 'actual mpv seek/restart lifecycle routed')
loaded = player.split('func fileLoaded()', 1)[1].split('func fileEnded', 1)[0]
check(loaded.index('AppRestartSession.fileLoaded(self)') < loaded.index('AppRestartSession.fileSetupFinished(self)'), 'seek and final setup bracket existing file lifecycle')
check(loaded.index('miniPlayer.handleVideoSizeChange()') < loaded.index('AppRestartSession.fileSetupFinished(self)'), 'final sizing precedes completion')
check('Preference.bool(for: .autoSwitchToMusicMode) && !AppRestartSession.isRestoring(self)' in player, 'music restore bypasses automatic initial mode')
check('guard mainWindow.loaded, info.state.active, !AppRestartSession.isRestoring(self)' in player, 'mpv fullscreen notifications suppressed while restoring normal frame')
check('!$0.isManagedByPlugin && $0.info.state == .idle && !$0.backgroundTaskInUse' in player, 'plugin-owned idle cores cannot be reused')
geometry = main.split('func applyRestartWindowFrame(', 1)[1].split('private func establishVideoTransformWindowReference', 1)[0]
check('shouldApplyInitialWindowSize = false' in geometry and 'initial: true' in geometry and 'updateWindowParametersForMPV(withFrame: frame)' in geometry,
      'restored frame establishes geometry reference and bypasses fresh-size preferences')
restart_body = restart.split('static func restart(restoring', 1)[1]
check(restart_body.index('discardRestoreRequest()') < restart_body.index('try startRelaunchHelper()') < restart_body.index('prepareForImmediateRestart(window)'),
      'failed relaunch helper factory leaves no restore arm; only successful immediate Restart prepares handoff')
factory = restart.split('static func startRelaunchHelper()', 1)[1]
check(factory.index('process.environment = launchEnvironment') < factory.index('try process.run()') < factory.index('return process'),
      'actual factory launches with captured original environment before returning success')
check('guard immediateRestartRequested, !capturedSessionForQuit' in restart,
      'legacy persisted flags alone cannot capture a normal quit')
ui = (ROOT / 'iina/SettingsPageUI.swift').read_text()
check('AppRestart.confirmSettingsChange(in: window)' in ui and 'NSAlert()' not in ui,
      'accent commits delegate to shared restart presenter')
presenter = restart.split('private static func presentPendingConfirmation()', 1)[1].split('static func runHelperIfRequested()', 1)[0]
check('prepareForImmediateRestart' not in presenter,
      'showing shared restart sheet does not arm restoration')
check('discardRestoreRequest()' in presenter and presenter.index('discardRestoreRequest()') < presenter.index('try restart(restoring: window)'),
      'shared Later/non-restart response discards pending restoration')
session = (ROOT / 'iina/AppRestartSession.swift').read_text()
capture = session.split('static func capture(', 1)[1].split('static func restore(', 1)[0]
check('let players = PlayerCore.playerCores.filter' in capture and 'window.isVisible' not in capture,
      'capture includes initialized loaded cores even when minimized, hidden or absent from orderedWindows')
check('player.playbackStateForRestart()' in capture and 'player.restorePlaybackStateAfterRestart(state)' in session,
      'current processing state has an explicit capture and restore independent of watch-later')

def extract(text, marker):
    start = text.index(marker)
    end = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

with tempfile.TemporaryDirectory(prefix='iina-restart-session-') as temporary:
    bundle = Path(temporary) / 'RestartSessionChecks.app'
    executable = bundle / 'Contents/MacOS/RestartSessionChecks'
    executable.parent.mkdir(parents=True)
    identifier = f'org.iina.tests.restart-session.{uuid.uuid4().hex}'
    (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': identifier,
        'CFBundleExecutable': executable.name,
        'CFBundleName': 'Restart Session Checks',
        'CFBundlePackageType': 'APPL',
        'LSUIElement': True,
        'NSPrincipalClass': 'NSApplication',
    }))
    support = Path(temporary) / 'TestDoubles.swift'
    support.write_text(Path(__file__).with_name('TestDoubles.swift').read_text().replace(
        '// PRODUCTION_RESTART_BRIDGES', '\n'.join(extract(player, marker) for marker in [
            '  private func restartTracks()', '  func playbackStateForRestart()',
            '  func restorePlaybackStateAfterRestart('])))
    files = [ROOT / 'iina/AppRestartSession.swift', ROOT / 'iina/AppRestart.swift',
             *[ROOT / f'iina/{name}.swift' for name in ['TrackProcessingState', 'TrackAudioProcessing',
                                                       'TrackVideoProcessing', 'TrackSelectionState']],
             support, Path(__file__).with_name('main.swift')]
    subprocess.run(['xcrun', 'swiftc', '-target', 'arm64-apple-macos12',
                    '-module-cache-path', str(CACHE), *map(str, files), '-o', str(executable)], check=True)
    completed = subprocess.run([str(executable)], capture_output=True, text=True, timeout=30)
    if completed.returncode:
        raise SystemExit(completed.stdout + completed.stderr)
    print(completed.stdout.strip())
    print(f'{source_checks} production lifecycle placement checks passed')
    result = {
        'runtime': completed.stdout.strip(),
        'sourcePlacementChecks': source_checks,
        'deploymentTarget': 'arm64-apple-macos12',
        'productionSources': {str(file.relative_to(ROOT)): hashlib.sha256(file.read_bytes()).hexdigest() for file in files[:-2]},
        'playerBridgeSourceSHA256': hashlib.sha256(player.encode()).hexdigest(),
        'boundaries': 'Actual coordinator, models and export/import bridges; controlled engine/graph/window doubles. No app activation or real media. Full-player QA separate.',
    }
    output = args.output / 'model-lifecycle-checks.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + '\n')
