# Video geometry session regression

Run from the repository root:

```sh
bash other/tests/video-geometry-session/run.sh
python3 other/tests/video-geometry-session/engine.py build/video-geometry-session-2026-10-19/engine
```

The Swift harness extracts the production session read/save/restore methods,
filter synchronization, window-scale notification handler, Crop preset setter,
aspect parser and crop coordinate model. MPV transport, window/editor lifecycle,
and track metadata are fixture boundaries. The multitrack suite additionally
extracts the actual session restore method together with the actual graph owner;
it verifies that restoring settings produces the expected source filter graph
without changing native audio selection.

The Python probe uses the installed custom libmpv with no window/audio output.
It checks on-unload capture, file-local option support, load/preloaded ordering,
native defaults, A-B-A restoration and session Reset overriding stale watch-later
settings. Fixtures, watch-later files and receipts stay in the requested output.

`prepare-lab.py OUTPUT` requires a successful Release build under
`OUTPUT/DerivedData`. It stages the executable with the installed custom engine,
signs and verifies it, then launches a uniquely identified app/profile with a
local IPC socket. `--final` updates the unused stage and creates a second lab;
it never replaces a running lab. `app-probe.py OUTPUT [lab.json]` checks actual
window/renderer dimensions, media transitions and native fullscreen. The optional
`--skip-fullscreen` third argument leaves fullscreen to the original receipt.
These scripts do not install or restart the personal app.

Window area/shape, Retina feedback, explicit scale, unlocked sizing and loading
flags are covered by `other/tests/crop-window-frame/run.sh`. Crop editor
Save/Cancel/Reset and PiP lifecycle/render transactions retain their dedicated
production-method suites. Automated contracts are separate from physical
animation and hidden-window PiP acceptance.
