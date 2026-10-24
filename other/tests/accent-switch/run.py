"""Run the native AppKit/SwiftUI bridge acceptance harness without profile writes."""
from pathlib import Path
import argparse
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=ROOT / 'build/accent-switch-2026-10-23')
parser.add_argument('--module-cache', type=Path)
args = parser.parse_args()
args.output = args.output.resolve()
args.output.mkdir(parents=True, exist_ok=True)
executable = args.output / 'AccentSwitchChecks'
command = ['xcrun', 'swiftc', '-target', f'{platform.machine()}-apple-macos12.0']
if args.module_cache:
    command += ['-module-cache-path', str(args.module_cache)]
command += [str(ROOT / 'iina/AccentSwitch.swift'),
            str(Path(__file__).with_name('main.swift')), '-o', str(executable)]
subprocess.run(command, check=True)
result = subprocess.run([str(executable), str(args.output)], capture_output=True, text=True)
(args.output / 'checks.txt').write_text(result.stdout + result.stderr)
print(result.stdout, end='')
if result.stderr:
    print(result.stderr, end='')
raise SystemExit(result.returncode)
