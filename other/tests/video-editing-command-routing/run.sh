#!/bin/bash
set -euo pipefail
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${VIDEO_EDITING_ROUTING_OUTPUT_DIR:-$repo_dir/build/video-editing-command-routing}"
cache_dir="${VIDEO_EDITING_ROUTING_MODULE_CACHE:-$output_dir/module-cache}"
mkdir -p "$output_dir/profile" "$cache_dir"
python3 "$test_dir/generate.py" "$repo_dir" "$test_dir" "$output_dir"
xcrun swiftc -module-cache-path "$cache_dir" "$output_dir/main.swift" -o "$output_dir/checks"
if [[ -n "${VIDEO_EDITING_ROUTING_LIBMPV:-}" ]]; then
  export DYLD_LIBRARY_PATH="$(dirname "$VIDEO_EDITING_ROUTING_LIBMPV")"
fi
CFFIXED_USER_HOME="$output_dir/profile" "$output_dir/checks" "${VIDEO_EDITING_ROUTING_LIBMPV:-}"
