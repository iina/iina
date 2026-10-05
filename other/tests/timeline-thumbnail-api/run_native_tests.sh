#!/bin/bash
set -euo pipefail

test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$test_dir/../../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/iina-thumbnail-native.XXXXXX")"
trap 'rm -r "$build_dir"' EXIT

xcrun swiftc "$test_dir/native/Stubs.swift" \
  "$repo_root/iina/Lock.swift" \
  "$repo_root/iina/TimelineThumbnailBroker.swift" \
  "$repo_root/iina/JavascriptAPIThumbnails.swift" \
  "$test_dir/native/main.swift" \
  -o "$build_dir/native-tests"
"$build_dir/native-tests"
