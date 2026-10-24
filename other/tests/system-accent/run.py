from pathlib import Path
import argparse
import json
import math
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path,
                    default=ROOT / 'build/system-accent-repair-2026-10-23/native-checks.json')
parser.add_argument('--module-cache', type=Path)
args = parser.parse_args()
module_cache = args.module_cache.resolve() if args.module_cache else None
if module_cache is None:
    existing = ROOT / 'build/sidebar-osd-tests/module-cache'
    if existing.is_dir():
        module_cache = existing.resolve()

custom_highlight = '0.456984 0.081313 0.184124 Other'
different_highlight = '0.081313 0.456984 0.184124 Other'
scenarios = [(f'palette-{code}', ['--accent-code', str(code)])
             for code in [0, 1, 2, 3, 4, 5, 6, -1, -2]]
scenarios += [
    ('multicolor-custom-highlight', ['--accent-code', '-2', '--highlight', custom_highlight]),
    ('multicolor-different-highlight', ['--accent-code', '-2', '--highlight', different_highlight]),
    ('red-accent-custom-burgundy', ['--accent-code', '0', '--highlight', custom_highlight]),
    ('light-custom-highlight', ['--highlight', '0.95 0.92 0.85 Other']),
    ('black-custom-highlight', ['--highlight', '0 0 0 Other']),
    ('white-custom-highlight', ['--highlight', '1 1 1 Other']),
    ('invalid-highlight', ['--highlight', 'invalid']),
    ('incomplete-highlight', ['--highlight', '0.1 0.2']),
    ('out-of-range-highlight', ['--highlight', '2 0.2 0.3 Other']),
    ('non-finite-highlight', ['--highlight', 'NaN 0.2 0.3 Other']),
    ('actual-system-preferences', []),
]

results = []
with tempfile.TemporaryDirectory(prefix='iina-accent-checks-') as temporary:
    executable = Path(temporary) / 'accent-checks'
    compile_command = ['xcrun', 'swiftc']
    if module_cache:
        compile_command += ['-module-cache-path', str(module_cache)]
    compile_command += [str(ROOT / 'iina/AppAccentColor.swift'),
                        str(Path(__file__).with_name('main.swift')), '-o', str(executable)]
    subprocess.run(compile_command, check=True)

    def run(mode, inputs):
        command = [str(executable), *inputs]
        if mode == 'native':
            command.append('--native')
        elif mode == 'system':
            command.append('--system')
        process = subprocess.run(command, check=True, capture_output=True, text=True)
        return json.loads(process.stdout)

    blue = run('native', ['--accent-code', '4', '--highlight',
                          '0.698039 0.843137 1.000000 Blue'])
    for name, inputs in scenarios:
        baseline = run('native', inputs)
        for mode in ['blue', 'system']:
            result = run(mode, inputs)
            result['scenario'] = name
            expected = baseline if mode == 'system' else blue
            for sample, native_sample in zip(result['colors'], expected['colors']):
                assert sample['nativeAccent'] == native_sample['nativeAccent'], (name, mode, result)
                assert sample['textHighlight'] == native_sample['textHighlight'], (name, mode, result)
                expected_accent = native_sample['nativeAccent']
                if mode == 'system':
                    try:
                        raw = [float(value) for value in result['sourceHighlight'].split()[:3]]
                        if len(raw) == 3 and all(math.isfinite(value) and 0 <= value <= 1 for value in raw):
                            expected_accent = [*raw, 1]
                    except ValueError:
                        pass
                assert all(abs(actual - expected_component) < 1e-12
                           for actual, expected_component in zip(sample['accent'], expected_accent)), (name, mode, result)
            results.append(result)

    custom_samples = [next(result for result in results
                           if result['scenario'] == name and result['mode'] == 'system')['colors']
                      for name in ['multicolor-custom-highlight', 'multicolor-different-highlight']]
    assert custom_samples[0] != custom_samples[1], 'The custom text highlight fixture was ineffective.'

args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(results, indent=2) + '\n')
print(f'{len(results)} native policy cases passed across four appearances; '
      'enabled preserves exact highlight RGB, disabled matches native blue; '
      'no persistent/global color writes.')
print(f'Results: {args.output}')
