#!/usr/bin/env python3
"""Exercise production exec with real pipes, processes and JavaScriptCore."""
import argparse
from pathlib import Path
import subprocess

tests = Path(__file__).resolve().parent
repo = tests.parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, default=repo / 'build/plugin-process-output-tests')
parser.add_argument('--module-cache', type=Path)
parser.add_argument('--source', type=Path, default=repo / 'iina/JavascriptAPIUtils.swift')
args = parser.parse_args()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
cache = (args.module_cache or output / 'module-cache').resolve()
cache.mkdir(parents=True, exist_ok=True)
source = args.source.read_text()
helpers = source[source.index('fileprivate func searchBinary('):source.index('@objc protocol JavascriptAPIUtilsExportable:')]
start = source.index('  func exec(', source.index('class JavascriptAPIUtils:'))
method = source[start:source.index('\n  func ask(', start)]
harness = (tests / 'main.swift').read_text().replace('// PRODUCTION_HELPERS', helpers)
harness = harness.replace('// PRODUCTION_EXEC', method)
(output / 'main.swift').write_text(harness)
subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(cache),
                str(output / 'main.swift'), '-o', str(output / 'checks')], check=True)
result = subprocess.run([str(output / 'checks')], text=True, capture_output=True, timeout=60)
(output / 'checks.log').write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr, end='')
raise SystemExit(result.returncode)
