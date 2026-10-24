#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="$repo_dir/build/window-geometry-model-tests"
mkdir -p "$output_dir/module-cache"
{ cat "$test_dir/Support.swift"; cat "$repo_dir/iina/Regex.swift"; cat "$repo_dir/iina/GeometryDef.swift"; cat "$repo_dir/iina/InitialWindowGeometry.swift"; cat "$test_dir/main.swift"; } > "$output_dir/main.swift"
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/window-geometry-model-tests"
"$output_dir/window-geometry-model-tests"
{ cat "$test_dir/Support.swift"; cat "$repo_dir/iina/Regex.swift"; cat "$repo_dir/iina/GeometryDef.swift"; cat "$repo_dir/iina/InitialWindowGeometry.swift"; cat "$test_dir/BindingSupport.swift"; awk '/^fileprivate class GeometryBindings/{include=1} /^fileprivate class WindowGeometryConfigurationItem/{include=0} include' "$repo_dir/iina/SettingsPageUI.swift"; cat "$test_dir/BindingTests.swift"; } > "$output_dir/main.swift"
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/window-geometry-binding-tests"
"$output_dir/window-geometry-binding-tests"
