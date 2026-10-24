# Music-mode ownership regressions

Run `bash other/tests/music-mode-ownership/run.sh` from the repository root.

The harness extracts both production music-mode transitions and the internal
command handler. It reuses the Custom Crop suite's source assembly, including
the real editor, native selection view and zoom projection. Only unrelated
playback, window-presentation and mini-player services are doubles.

Checks cover loading/starting auto-switches, stopped/shutdown attempts, active
Crop/Delogo, zoom-mask retention, PiP and fullscreen transition gates, duplicate
entry/return, a different video host, and close cleanup while stopping or idle.
Windows remain hidden and the test application cannot activate. This suite
does not exercise native PiP or fullscreen presentation.

`MUSIC_MODE_OWNERSHIP_OUTPUT_DIR` and `MUSIC_MODE_OWNERSHIP_MODULE_CACHE` can
redirect generated sources, logs and the Swift module cache. Source hashes are
recorded in `inputs.json`.
