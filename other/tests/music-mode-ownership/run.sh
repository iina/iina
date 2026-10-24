#!/bin/bash
set -euo pipefail
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${MUSIC_MODE_OWNERSHIP_OUTPUT_DIR:-$repo_dir/build/music-mode-ownership-tests}"
cache_dir="${MUSIC_MODE_OWNERSHIP_MODULE_CACHE:-$output_dir/module-cache}"
mkdir -p "$output_dir/profile" "$cache_dir"
python3 "$test_dir/generate.py" "$repo_dir" "$test_dir" "$output_dir"
xcrun swiftc -module-cache-path "$cache_dir" "$output_dir/main.swift" -o "$output_dir/checks"
CFFIXED_USER_HOME="$output_dir/profile" "$output_dir/checks"
