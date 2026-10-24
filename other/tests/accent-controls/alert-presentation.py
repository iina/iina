"""Compatibility entry point for the shared settings-restart presenter suite.

Accent commits now delegate to AppRestart; the old extracted SettingsPageUI
method and AlertProbe.swift are superseded by the shared native presenter test.
"""
from pathlib import Path
import argparse
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path)
parser.add_argument('--output', type=Path, default=ROOT / 'build/accent-alert-flicker-2026-10-24')
args = parser.parse_args()
if args.source is not None and args.source.resolve() != ROOT / 'iina/SettingsPageUI.swift':
    parser.error('--source extraction is retired; run settings-restart-presenter against the owning production source')
print('Accent restart alerts now use the shared native presenter; running settings-restart-presenter checks.', flush=True)
subprocess.run([sys.executable, str(ROOT / 'other/tests/settings-restart-presenter/run.py'),
                '--output', str(args.output)], check=True)
# Retain the familiar evidence filename for existing local callers.
shutil.copyfile(args.output / 'native-checks.json', args.output / 'alert-checks.json')
