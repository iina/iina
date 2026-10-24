#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="$repo_dir/build/window-geometry-preview-tests"
mkdir -p "$output_dir/profile" "$output_dir/module-cache"
{ cat "$test_dir/Support.swift"; cat "$repo_dir/iina/Regex.swift"; cat "$repo_dir/iina/GeometryDef.swift"; cat "$repo_dir/iina/InitialWindowGeometry.swift"; cat "$repo_dir/iina/ResizeCursor.swift"; cat "$repo_dir/iina/ConstraintsSugar.swift"; cat "$repo_dir/iina/UIHelper.swift"; cat "$repo_dir/iina/PositionPreviewDrawing.swift"; cat "$repo_dir/iina/WindowGeometrySettingsSheetController.swift"; cat "$test_dir/main.swift"; } > "$output_dir/main.swift"
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/window-geometry-preview-tests"
IINA_TEST_LOCALIZATION_PATH="$repo_dir/iina/en.lproj/Localizable.strings" CFFIXED_USER_HOME="$output_dir/profile" "$output_dir/window-geometry-preview-tests"
