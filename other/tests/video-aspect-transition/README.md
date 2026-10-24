# Temporary aspect-transition fill

Run from the repository root after generating the multitrack fixture:

```sh
DYLD_LIBRARY_PATH="$PWD/deps/lib" python3 other/tests/video-aspect-transition/render-probe.py deps/lib/libmpv.2.dylib '/Users/lyzmin41/Downloads/IINA Multitrack Test 2026-10-15.mkv' build/video-aspect-transition/render
```

Uses the bundled libmpv software render API with null audio and a paused portrait
track. It checks letterboxing versus aspect-fill at landscape, square and portrait
viewport sizes, exact restoration of a nonzero original fill, and automatic
file-local cleanup on the next media load. Writes PPM images for inspection.
It does not observe the application's OpenGL animation timing.

The production window lifecycle and early-return guards are exercised by
`other/tests/crop-window-frame/run.sh`; graph failure cleanup is covered by
`other/tests/multitrack-playback/run.sh`. Full-player transition sequencing is
verified in the isolated Lab runtime log.
