from pathlib import Path
import argparse
import hashlib
import json
import platform
import plistlib
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--module-cache', type=Path,
                    default=ROOT / 'build/sidebar-osd-tests/module-cache')
parser.add_argument('--output', type=Path,
                    default=ROOT / 'build/accent-color-api-2026-10-24/policy-checks.json')
args = parser.parse_args()
args.module_cache = args.module_cache.resolve()
if not args.module_cache.is_dir():
    raise SystemExit(f'Refusing to create a new compiler cache; supply --module-cache: {args.module_cache}')

source = ROOT / 'iina/AppAccentColor.swift'
source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
blue = [0, 122 / 255, 1, 1]
burgundy = [0.456984, 0.081313, 0.184124, 1]

cases = []

def migration(name, stored, expected, retained=None):
    case = dict(name=name, stored=stored, expectedSource=expected)
    if retained is not None:
        case['retainedSourceValue'] = retained
    if expected == 0:
        case['expectedColor'] = blue
    elif expected == 2:
        case['expectedColor'] = burgundy
    elif expected == 3:
        case['expectedColor'] = blue
    cases.append(case)

migration('missing-new-and-legacy-defaults-to-highlight', {}, 2)
migration('legacy-off-migrates-to-blue', {'useSystemAccentColor': False}, 0)
migration('legacy-on-migrates-to-highlight', {'useSystemAccentColor': True}, 2)
for mode in range(4):
    migration(f'valid-new-{mode}-overrides-opposite-legacy',
              {'accentColorSource': mode, 'useSystemAccentColor': mode == 0}, mode, mode)
migration('numeric-string-source-is-retained', {'accentColorSource': '3', 'useSystemAccentColor': False}, 3, '3')
for name, invalid, legacy, expected in [
    ('unknown-integer', 99, None, 2),
    ('negative-integer', -1, False, 0),
    ('boolean', True, False, 0),
    ('fractional-number', 1.5, True, 2),
    ('array', [], None, 2),
    ('unknown-string', 'custom', None, 2),
    ('fractional-string', '2.0', False, 0),
]:
    stored = {'accentColorSource': invalid}
    if legacy is not None:
        stored['useSystemAccentColor'] = legacy
    migration(f'sanitize-{name}-once', stored, expected)

cases.extend([
    dict(name='custom-canonical-opaque-rgb', expectedSource=3,
         stored={'accentColorSource': 3, 'customAccentColor': '  #a1B2c3\n'},
         retainedSourceValue=3, expectedColor=[161 / 255, 178 / 255, 195 / 255, 1]),
    dict(name='custom-invalid-hex-falls-back-to-blue', expectedSource=3,
         stored={'accentColorSource': 3, 'customAccentColor': '#12345678'},
         retainedSourceValue=3, expectedColor=blue),
    dict(name='custom-explicit-color-removes-alpha', expectedSource=3,
         stored={'accentColorSource': 3, 'customAccentColor': '#FFFFFF'},
         retainedSourceValue=3, explicitCustom=[0.75, 0.25, 0.5, 0.2], expectedColor=[0.75, 0.25, 0.5, 1]),
    dict(name='custom-white-contrasting-foreground', expectedSource=3,
         stored={'accentColorSource': 3, 'customAccentColor': '#FFFFFF'},
         retainedSourceValue=3, expectedColor=[1, 1, 1, 1]),
    dict(name='custom-black-contrasting-foreground', expectedSource=3,
         stored={'accentColorSource': 3, 'customAccentColor': '#000000'},
         retainedSourceValue=3, expectedColor=[0, 0, 0, 1]),
    dict(name='blue-override-restores-existing-volatile-appearance', expectedSource=1,
         stored={'accentColorSource': 1}, retainedSourceValue=1, restorePolicy=True),
    dict(name='blue-override-removes-previously-absent-appearance-arguments', expectedSource=1,
         stored={'accentColorSource': 1}, retainedSourceValue=1, restorePolicy=True, restoreAbsentArguments=True),
])

results = []
with tempfile.TemporaryDirectory(prefix='iina-accent-policy-') as temporary:
    bundle = Path(temporary) / 'AccentPolicyChecks.app'
    executable = bundle / 'Contents/MacOS/AccentPolicyChecks'
    executable.parent.mkdir(parents=True)
    (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': f'org.iina.tests.accentpolicy.{uuid.uuid4().hex}',
        'CFBundleName': 'Accent Policy Checks', 'CFBundleExecutable': executable.name,
        'CFBundlePackageType': 'APPL', 'NSPrincipalClass': 'NSApplication', 'LSUIElement': True,
    }))
    command = ['xcrun', 'swiftc', '-target', 'arm64-apple-macos12', '-module-cache-path',
               str(args.module_cache), str(source), str(Path(__file__).with_name('main.swift')),
               '-o', str(executable)]
    subprocess.run(command, check=True)
    for case in cases:
        process = subprocess.run([str(executable), '--case', json.dumps(case)],
                                 capture_output=True, text=True)
        if process.returncode:
            raise SystemExit(f"{case['name']}: {process.stderr.strip()}")
        results.append(json.loads(process.stdout))

if hashlib.sha256(source.read_bytes()).hexdigest() != source_hash:
    raise SystemExit('Production policy changed during the run; results require a fresh run.')
receipt = dict(status='passed', target='arm64-apple-macos12', runtime=platform.mac_ver()[0],
               productionPolicySHA256=source_hash, caseCount=len(results),
               checkCount=sum(case['checks'] for case in results),
               appearancesPerCase=4, cases=results,
               limitations=['Default blue intentionally retains legacy white text (~4.02:1).',
                            'Native system preference notifications and control rendering are outside this policy test.'])
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(receipt, indent=2) + '\n')
print(f"Accent policy: {receipt['caseCount']} isolated cases, {receipt['checkCount']} checks passed across four appearances.")
print(f'Results: {args.output}')
