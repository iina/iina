#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${MULTITRACK_HEADER_OUTPUT_DIR:-$repo_dir/build/video-track-controls-2026-10-16/header}"
mkdir -p "$output_dir"
python3 - "$repo_dir" "$output_dir" <<'PY'
from pathlib import Path
import sys
repo,out=map(Path,sys.argv[1:])
s=(repo/'iina/FFmpegController.m').read_text();start=s.index('+ (BOOL)hasMultipleVideoTracksInMatroskaFile:');end=s.index('\n+ (NSDictionary *)probeVideoInfoForFile:',start)
source='''#import <Foundation/Foundation.h>
#include <string.h>
#include <libavformat/avformat.h>
@interface HeaderProbe : NSObject
+ (BOOL)hasMultipleVideoTracksInMatroskaFile:(NSString *)file;
@end
@implementation HeaderProbe
'''+s[start:end]+'''
@end
int main(int argc, const char **argv) {
 @autoreleasepool {
  for (int i=1;i+1<argc;i+=2) {
   BOOL actual=[HeaderProbe hasMultipleVideoTracksInMatroskaFile:[NSString stringWithUTF8String:argv[i]]];
   if (actual != atoi(argv[i+1])) return 1;
   printf("PASS production Matroska header probe: %s => %d\\n",argv[i],actual);
  }
 }
 return 0;
}
'''
(out/'probe.m').write_text(source)
PY
xcrun clang -fobjc-arc -framework Foundation -I "$repo_dir/deps/include" "$output_dir/probe.m" -L "$repo_dir/deps/lib" -lavformat.63 -lavcodec.63 -lavutil.61 -Wl,-rpath,"$repo_dir/deps/lib" -o "$output_dir/probe"
"$output_dir/probe" "$@"
