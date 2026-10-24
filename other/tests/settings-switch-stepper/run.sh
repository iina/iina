#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="$repo_dir/build/settings-switch-stepper-tests"
mkdir -p "$output_dir/module-cache"
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PYCODE'
from pathlib import Path
import sys
repo, tests, output = map(Path, sys.argv[1:])
source = (repo / 'iina/SettingsItem.swift').read_text()
start = source.index('  class SwitchWithInput:')
end = source.index('\n}\n', start)
field = source[source.index('class TextFieldWithSwitch:'):]
(output / 'main.swift').write_text((tests / 'Support.swift').read_text() + '\nstruct SettingsItem {\n' + source[start:end] + '\n}\n' + field + '\n' + (tests / 'main.swift').read_text())
PYCODE
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/settings-switch-stepper-tests"
"$output_dir/settings-switch-stepper-tests"
