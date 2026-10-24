#!/usr/bin/env python3
"""Run extracted attachment chooser actions with deferred panel completions."""
import argparse
from pathlib import Path
import subprocess

tests = Path(__file__).resolve().parent
repo = tests.parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, default=repo / 'build/external-track-chooser-tests')
parser.add_argument('--module-cache', type=Path)
parser.add_argument('--source-root', type=Path, default=repo)
args = parser.parse_args()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
cache = (args.module_cache or output / 'module-cache').resolve()
cache.mkdir(parents=True, exist_ok=True)
entries = [('SidebarAudioPane', 'loadExternalAudioAction'),
           ('SidebarVideoPane', 'loadExternalVideoAction'),
           ('SidebarSubtitlesPane', 'loadExternalSubAction'),
           ('MainMenuActions', 'menuLoadExternalAudio'),
           ('MainMenuActions', 'menuLoadExternalSub')]
harness = (tests / 'main.swift').read_text()
for index, (name, method) in enumerate(entries):
    source = (args.source_root / 'iina' / (name + '.swift')).read_text()
    start = source.index('  @objc ', source.index('class ') if name != 'MainMenuActions' else 0)
    start = source.rfind('  @objc ', 0, source.index('func ' + method + '('))
    end = source.index('\n  }', start) + 4
    extracted = source[start:end].replace('@objc private func', '@objc func')
    harness = harness.replace('// PRODUCTION_ACTION_' + str(index), extracted)
(output / 'main.swift').write_text(harness)
subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(cache),
                str(args.source_root / 'iina/PlayerState.swift'), str(output / 'main.swift'),
                '-o', str(output / 'checks')], check=True)
result = subprocess.run([str(output / 'checks')], text=True, capture_output=True, timeout=30)
(output / 'checks.log').write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr, end='')
raise SystemExit(result.returncode)
