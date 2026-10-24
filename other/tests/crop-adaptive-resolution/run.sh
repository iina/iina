#!/bin/bash
set -euo pipefail
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${CROP_ADAPTIVE_OUTPUT_DIR:-$repo_dir/build/crop-adaptive-resolution-tests}"
mkdir -p "$output_dir/module-cache"
python3 "$test_dir/generate.py" "$repo_dir" "$test_dir" "$output_dir" | tee "$output_dir/wiring-results.log"
xcrun swiftc -warnings-as-errors -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/tests"
"$output_dir/tests" | tee "$output_dir/results.log"
