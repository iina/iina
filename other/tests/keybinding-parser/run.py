#!/usr/bin/env python3
"""Compile the production input.conf parser and reader against malformed files."""
import argparse
from pathlib import Path
import subprocess

tests = Path(__file__).resolve().parent
repo = tests.parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, default=repo / 'build/keybinding-parser-tests')
parser.add_argument('--module-cache', type=Path)
parser.add_argument('--source', type=Path, default=repo / 'iina/KeyMapping.swift')
args = parser.parse_args()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
cache = (args.module_cache or output / 'module-cache').resolve()
cache.mkdir(parents=True, exist_ok=True)
source = args.source.read_text()
start = source.index('  static func parseInputConf(')
method = source[start:source.index('\n  }', start) + 4]
harness = (tests / 'main.swift').read_text().replace('// PRODUCTION_PARSER', method)
(output / 'main.swift').write_text(harness)
subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(cache),
                str(repo / 'iina/StreamReader.swift'), str(output / 'main.swift'),
                '-o', str(output / 'checks')], check=True)
result = subprocess.run([str(output / 'checks'), str(output / 'fixture.conf')],
                        text=True, capture_output=True, timeout=30)
(output / 'checks.log').write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr, end='')
raise SystemExit(result.returncode)
