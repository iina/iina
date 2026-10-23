# Multitrack audio, fixed track order and subtitle roles

Run `bash other/tests/multitrack-playback/run.sh` on macOS with Xcode.
The harness compiles production state/graph generation, audio selection and
ownership methods, active-ID lookup, the complete TrackSelector/table gesture
implementation and native layout helpers. MPV properties, notifications and
unrelated player services are fixtures; AppKit event routing, row drawing,
mouse tracking and cursor state are native.

Checks cover solo/toggle/two-click additive range, Shift-only visual anchors
without a playback write, fixed source order and focus-induced scrolling,
None, multiple blue active bars, neutral anchor state, custom graph ownership,
transactional graph failure, new-file cleanup, native right/Command/Shift clicks,
ignored Audio/Video row dragging without selection, graph changes or hand cursors,
cancelled right drag, metadata refresh and source-order keyboard/cycle behavior.
Bottom-edge resizing covers all four selectors, fixed tops, viewport/window bounds,
independent heights, unchanged playback, same-window media changes and resetting
retained views when their owning player window closes/reopens. Whole-row checks
cover the four-complete-row default, matching real/filler row pitch, quantized
targets and bounds, frame/scroll interpolation while held, retargeting/reversal,
cancelled targets, reduced motion and mid-animation lifecycle cleanup.
Pinned No audio/No video/No subtitles rows cover all four selectors, repeated
explicit-off selection, missing tracks, independent subtitle outputs, native
header hit testing after scrolling and external selection updates. The table now
contains only real tracks; the 26 pt fixed header is excluded from whole-row sizing.
Position labels follow source order. Track rows cannot be reordered or transferred.
Subtitle checks cover complete source lists, single selection with modifiers,
mutually exclusive role assignment, dimmed/accessibility-disabled occupied rows,
keyboard skipping, immediate re-enabling, same-language distinct sources and
ignored within-list/cross-list/header drags. Native light/dark renders are saved
with the test artifacts. File-order export remains removed.
All four selectors share one outline/divider overlay above the pinned header.
Range completion checks cover whole-interval neutral-background flash and fade,
retained logical anchor, reverse/coincident endpoints, unchanged playback, failed
application and cancellation by a new anchor or detach.
Button activation uses AppKit performClick; physical clicks are checked separately
in the isolated app because the harness runs as a prohibited, borderless application.
Successive right-click additions followed by solo of the first-added track
exercise the bundled mpv cached-aid regression, including all four first IDs.

Persistent mixing also checks zero graph replacements for gain changes, logical
solo/None IDs, failed commands, current weights during video rollback, compatible
channel layouts, foreign ownership, attached streams and the original gestures.
See [the engine patch notes](../../patches/README.md) for the PCM/Opus probe.

The real OpenGL smoke test catches ICC failures hidden by null video output:

```sh
xcrun clang -Wno-deprecated-declarations -I deps/include \
  other/tests/multitrack-playback/opengl-probe.c -framework OpenGL -o /tmp/lyina-opengl-probe
/tmp/lyina-opengl-probe /absolute/path/to/libmpv.2.dylib \
  /absolute/path/to/four-audio-track-video.mkv graph /absolute/path/to/display.icc
```

It renders a real frame into a framebuffer and checks visible RGB pixels with
mpv OSD disabled. Run the final engine with and without ICC. If a dependency
directory is supplied through `DYLD_LIBRARY_PATH`, it must not contain another
libmpv, which could override the requested library.

Generate the 30-second test MKV (refuses to overwrite an existing file):

```sh
python3 other/tests/multitrack-playback/generate-fixture.py /absolute/path/test.mkv
```

It contains three labelled H.264 video streams (1280x720, 960x720, 720x1280) and
four independently identifiable stereo PCM tones (330, 440, 550, 660 Hz). The
label renderer uses offscreen AppKit, so ffmpeg drawtext/libass is unnecessary.

The separate engine probe loads this repository's actual libmpv and writes PCM
without opening an audio output device:

```sh
DYLD_LIBRARY_PATH="$PWD/deps/lib" python3 other/tests/multitrack-playback/mpv-probe.py \
  deps/lib/libmpv.2.dylib /absolute/path/test.mkv build/multitrack-playback/mpv
```

It measures selected/absent frequencies and verifies live graph reassignment,
paused exact seeking and returning to native solo, including the first-added
input after successive live graph replacements. The same probe also passed
with an Opus remux. See `docs/plans/active/2026-10-15-multitrack-playback.md` for
build/live evidence and scope. These checks do not claim physical listening or
arbitrary third-party audio-filter compatibility.

Engine references: [mpv lavfi-complex](https://mpv.io/manual/stable/#options-lavfi-complex),
[FFmpeg amix](https://ffmpeg.org/ffmpeg-filters.html#amix).
