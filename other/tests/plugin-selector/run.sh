#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="$repo_dir/build/plugin-selector-tests"
mkdir -p "$output_dir/module-cache"
cat "$test_dir/Support.swift" "$repo_dir/iina/ConstraintsSugar.swift" "$repo_dir/iina/ScrollSelectionControl.swift" "$repo_dir/iina/PluginViewController.swift" "$test_dir/main.swift" > "$output_dir/main.swift"
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/plugin-selector-tests"
selection_domain="org.iina.plugin-selector-tests.$(uuidgen)"
export PLUGIN_SELECTOR_TEST_DOMAIN="$selection_domain"
trap 'defaults delete "$selection_domain" >/dev/null 2>&1 || true' EXIT
"$output_dir/plugin-selector-tests"
"$output_dir/plugin-selector-tests" --write-selection
"$output_dir/plugin-selector-tests" --read-selection
