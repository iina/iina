#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TASK_BUILD="build/shareplay-tests"
mkdir -p "$TASK_BUILD"
TASK_DEVELOPER="$(xcode-select -p)/Platforms/MacOSX.platform/Developer"
TASK_FRAMEWORKS="$TASK_DEVELOPER/Library/Frameworks"
TASK_BUNDLE="$TASK_BUILD/SharePlayTests.xctest"
mkdir -p "$TASK_BUNDLE/Contents/MacOS"
cat > "$TASK_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SharePlayTests</string>
<key>CFBundleIdentifier</key><string>dev.local.iina.shareplay-tests</string>
<key>CFBundlePackageType</key><string>BNDL</string>
</dict></plist>
PLIST
if [[ -z "${IINA_SHAREPLAY_FIXTURE:-}" ]]; then
  if command -v ffmpeg >/dev/null && [[ ! -f "$TASK_BUILD/fixture.mp4" ]]; then
    ffmpeg -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=640x360:rate=30' \
      -t 12 -c:v h264_videotoolbox -b:v 1M -an "$TASK_BUILD/fixture.mp4"
  fi
  if [[ -f "$TASK_BUILD/fixture.mp4" ]]; then
    export IINA_SHAREPLAY_FIXTURE="$PWD/$TASK_BUILD/fixture.mp4"
  fi
fi
xcrun swiftc -emit-library -module-name SharePlayTests -swift-version 5 -module-cache-path "$TASK_BUILD/ModuleCache" \
  -I deps/include -import-objc-header Tests/MPVTest-Bridging-Header.h deps/lib/libmpv.2.dylib \
  -Xlinker -rpath -Xlinker "$PWD/deps/lib" \
  -I "$TASK_DEVELOPER/usr/lib" -L "$TASK_DEVELOPER/usr/lib" \
  -F "$TASK_FRAMEWORKS" -Xlinker -rpath -Xlinker "$TASK_FRAMEWORKS" \
  iina/SharePlayState.swift iina/SharePlayPlayback.swift iina/SharePlayCoordinator.swift \
  Tests/SharePlayTests.swift Tests/MPVSharePlayTests.swift -o "$TASK_BUNDLE/Contents/MacOS/SharePlayTests"
xcrun xctest "$TASK_BUNDLE"
