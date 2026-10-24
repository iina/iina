#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="$repo_dir/build/settings-localization-tests"
mkdir -p "$output_dir/module-cache"
python3 - "$repo_dir" "$output_dir" <<'PY'
from pathlib import Path
import plistlib
import sys
repo, output = map(Path, sys.argv[1:])
contents = output / 'Resource Audit.app' / 'Contents'
(contents / 'MacOS').mkdir(parents=True, exist_ok=True)
(contents / 'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'org.iina.settings-localization-harness',
    'CFBundleExecutable': 'ResourceAudit', 'CFBundlePackageType': 'APPL',
    'CFBundleDevelopmentRegion': 'en', 'CFBundleAllowMixedLocalizations': True,
}))
resources = contents / 'Resources'
if not resources.exists():
    resources.symlink_to(repo / 'iina', target_is_directory=True)
PY
cat "$test_dir/Support.swift" "$repo_dir/iina/ConstraintsSugar.swift" "$repo_dir/iina/UIHelper.swift" "$test_dir/main.swift" > "$output_dir/main.swift"
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/Resource Audit.app/Contents/MacOS/ResourceAudit"
"$output_dir/Resource Audit.app/Contents/MacOS/ResourceAudit"
for language in en ru ar; do
  "$output_dir/Resource Audit.app/Contents/MacOS/ResourceAudit" -AppleLanguages "($language)" --expected-language "$language"
done
