#!/bin/sh

set -eux

patch_binary() {
	vtool -set-version-min macos "$_MACOSX_DEPLOYMENT_TARGET" "$SDK_VERSION" "$1" -output "$1"
	codesign --force --sign "$CODE_SIGN_IDENTITY" -o runtime "$1"
}

patch_binary "$BUILT_PRODUCTS_DIR/$FRAMEWORKS_FOLDER_PATH/Sparkle.framework/Versions/B/Sparkle"
patch_binary "$BUILT_PRODUCTS_DIR/$EXECUTABLE_PATH"

