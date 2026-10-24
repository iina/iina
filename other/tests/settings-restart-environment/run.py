#!/usr/bin/env python3
"""Exercise the unchanged native restart helper through real Launch Services."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import platform
import plistlib
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
TESTS = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path,
                    default=ROOT / 'build/settings-restart-2026-10-24/environment')
parser.add_argument('--module-cache', type=Path,
                    default=ROOT / 'build/sidebar-osd-tests/module-cache')
parser.add_argument('--baseline-proxy', choices=['present', 'absent'], default='present',
                    help='Preserve an original synthetic proxy, or its original absence')
args = parser.parse_args()
args.module_cache = args.module_cache.resolve()
if not args.module_cache.is_dir():
    raise SystemExit(f'Reuse the existing module cache: {args.module_cache}')

source = ROOT / 'iina/AppRestart.swift'
source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
assert 'helper = try startRelaunchHelper()' in source.read_text(), 'Probe must use the actual restart handoff'
token = uuid.uuid4().hex
run = args.output.resolve() / token
run.mkdir(parents=True)
bundle = run / ('IINARestartEnvironment-' + token[:12] + '.app')
executable = bundle / 'Contents/MacOS/RestartEnvironmentProbe'
resources = bundle / 'Contents/Resources'
executable.parent.mkdir(parents=True)
resources.mkdir(parents=True)
bundle_id = 'org.iina.tests.settings-restart-environment.' + token
info = {
    'CFBundleIdentifier': bundle_id,
    'CFBundleName': 'IINA Restart Environment ' + token[:12],
    'CFBundleExecutable': executable.name,
    'CFBundlePackageType': 'APPL',
    'CFBundleVersion': '1',
    'CFBundleShortVersionString': '1.0',
    'LSMinimumSystemVersion': '12.0',
    'LSUIElement': True,
}
(bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
launch_path = '/iina-original-launch-' + token + '/bin:/usr/bin:/bin:/usr/sbin:/sbin'
launch_proxy = 'http://127.0.0.1:1' if args.baseline_proxy == 'present' else None
(resources / 'probe.json').write_text(json.dumps({
    'token': token,
    'output': str(run),
    'pathPrefix': '/iina-restart-environment-' + token + '/bin',
    'launchPath': launch_path,
    'launchProxy': launch_proxy,
}))
target = f'{platform.machine()}-apple-macos12.0'
common = ['xcrun', 'swiftc', '-target', target, '-module-cache-path', str(args.module_cache),
          str(source), str(TESTS / 'main.swift')]
subprocess.run([*common, '-typecheck'], check=True)
subprocess.run([*common, '-o', str(executable)], check=True)
subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(bundle)],
               check=True, capture_output=True, text=True)
subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(bundle)],
               check=True, capture_output=True, text=True)
if hashlib.sha256(source.read_bytes()).hexdigest() != source_hash:
    raise SystemExit('Production helper changed during compilation; rerun after source freeze')

# Only these selected variables receive synthetic launch values. The parent
# later mutates PATH/proxy, as PlayerCore.startMPV does. No personal value is saved.
environment = os.environ.copy()
environment['IINA_RESTART_ENVIRONMENT_PARENT'] = token
environment['PATH'] = launch_path
if launch_proxy is None:
    environment.pop('http_proxy', None)
else:
    environment['http_proxy'] = launch_proxy
with (run / 'parent-output.txt').open('w') as output:
    parent = subprocess.Popen([str(executable)], env=environment, stdout=output, stderr=output)
    parent.wait(timeout=10)
if parent.returncode:
    raise SystemExit(f'Native parent failed; inspect task-local {run / "parent-output.txt"}')

deadline = time.monotonic() + 30
events = []
while time.monotonic() < deadline:
    event_file = run / 'events.jsonl'
    if event_file.exists():
        events = [json.loads(line) for line in event_file.read_text().splitlines()]
        if any(event['stage'] == 'launch-services-relaunch' for event in events):
            break
    time.sleep(0.1)

stages = {event['stage']: event for event in events}
expected = ['parent-before-mutation', 'parent-after-mutation', 'inherited-child-witness',
            'parent-spawned-actual-helper', 'launch-services-relaunch']
failures = []
for stage in expected:
    if stage not in stages:
        failures.append('Missing stage: ' + stage)
if len(events) != len(expected):
    failures.append('Unexpected number of stages or recursion')
if stages.get('parent-before-mutation', {}).get('pid') != parent.pid:
    failures.append('Recorded parent process does not match the launched parent')
for key in ['pathMatchesLaunchBaseline', 'proxyMatchesLaunchBaseline']:
    if not stages.get('parent-before-mutation', {}).get(key):
        failures.append('Initial launch baseline is missing: ' + key)
for stage in ['parent-after-mutation', 'inherited-child-witness', 'parent-spawned-actual-helper']:
    if not all(stages.get(stage, {}).get(key) for key in
               ['pathMarkerPresent', 'proxyMarkerPresent', 'parentStageMarkerPresent']):
        failures.append('Runtime environment mutation/inheritance not demonstrated: ' + stage)
relaunch = stages.get('launch-services-relaunch')
if relaunch:
    for key in ['pathMarkerPresent', 'proxyMarkerPresent']:
        if relaunch[key]:
            failures.append('Launch Services retained synthetic marker: ' + key)
    for key in ['pathMatchesLaunchBaseline', 'proxyMatchesLaunchBaseline', 'parentStageMarkerPresent']:
        if not relaunch[key]:
            failures.append('Original launch environment was not preserved: ' + key)
    if relaunch['pid'] in [parent.pid, stages.get('parent-spawned-actual-helper', {}).get('helperPID')]:
        failures.append('Relaunch did not create a fresh application process')
    if relaunch['parentPID'] == parent.pid:
        failures.append('Relaunch is still directly parented by the original application')
if hashlib.sha256(source.read_bytes()).hexdigest() != source_hash:
    failures.append('Production source changed during acceptance')

receipt = {
    'result': 'FAIL' if failures else 'PASS',
    'failures': failures,
    'productionSource': 'iina/AppRestart.swift',
    'productionSHA256': source_hash,
    'probeSHA256': hashlib.sha256((TESTS / 'main.swift').read_bytes()).hexdigest(),
    'handoffAPI': 'Actual AppRestart.startRelaunchHelper(), shared with restart(restoring:)',
    'target': target,
    'macOS': platform.mac_ver()[0],
    'launchProxyFixture': args.baseline_proxy,
    'bundleIdentifier': bundle_id,
    'bundle': str(bundle),
    'environmentRecorded': 'Only synthetic marker-presence booleans; no environment dump',
    'events': events,
}
(run / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
(args.output / 'latest-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt, indent=2))
raise SystemExit(1 if failures else 0)
