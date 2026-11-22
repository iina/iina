#!/usr/bin/env python3
"""Compile FFmpegController with real bundled FFmpeg and injected failure points."""

import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--dependency-root", type=Path, help="Checkout containing downloaded deps/lib (defaults to source root)")
    args = parser.parse_args()
    root = args.source_root.resolve()
    dependencies = (args.dependency_root or root).resolve()
    harness = Path(__file__).with_name("thumbnail-cleanup") / "main.m"
    with tempfile.TemporaryDirectory(prefix="iina-thumbnail-cleanup-") as directory:
        folder = Path(directory)
        # The only application dependency replaced by a stand-in is logging.
        (folder / "IINA-Swift.h").write_text('''#import <Foundation/Foundation.h>
@interface FFmpegLogger: NSObject
+ (void)debug:(NSString *)message;
+ (void)error:(NSString *)message;
+ (void)warn:(NSString *)message;
@end
''')
        fixture = folder / "video.y4m"
        fixture.write_bytes(b"YUV4MPEG2 W16 H16 F12:1 Ip A1:1 C420jpeg\n" + b"".join(
            b"FRAME\n" + bytes([32 + i * 8]) * 256 + bytes([128]) * 128 for i in range(12)))
        invalid = folder / "invalid.y4m"
        invalid.write_bytes(b"not a video")
        libraries = []
        for name in ["avformat", "avcodec", "avutil", "swscale"]:
            matches = list((dependencies / "deps/lib").glob(f"lib{name}.*.dylib"))
            if len(matches) != 1:
                raise SystemExit(f"Expected one bundled {name} library; run other/download_libs.sh first")
            libraries.append(str(matches[0]))
        executable = folder / "probe"
        subprocess.run([
            "xcrun", "clang", "-fobjc-arc", "-fmodules", "-Werror=implicit-function-declaration",
            "-I", str(folder), "-I", str(root / "deps/include"), "-I", str(root / "iina"),
            str(harness), *libraries, "-framework", "Cocoa", "-framework", "QuartzCore",
            "-framework", "Accelerate", "-Wl,-rpath," + str(dependencies / "deps/lib"),
            "-o", str(executable),
        ], check=True, timeout=60)
        subprocess.run([str(executable), str(fixture), str(invalid)], check=True, timeout=30)


if __name__ == "__main__":
    main()
