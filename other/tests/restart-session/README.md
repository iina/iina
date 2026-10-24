# Explicit settings-restart session handoff

Run `python3 other/tests/restart-session/run.py` on macOS. The script compiles the
actual `AppRestart.swift` and `AppRestartSession.swift` unchanged for
`arm64-apple-macos12`, reuses `build/sidebar-osd-tests/module-cache`, and runs the
coordinator against controlled engine/window boundaries. Native windows remain
hidden and the test application uses a prohibited activation policy. Its unique
bundle/suite preferences are removed; it does not open media, load plugins,
activate the personal player, or write global preferences.

The checks cover:

- Versioned property-list round trips, finite geometry/time limits, malformed and
  oversized payloads, nonrestartable streams, bad playlist indices/current-item
  identity, invalid-window isolation, and removal before one-shot restoration.
- Every ordering of seek completion, window readiness, and final file setup;
  early readiness and final frame reapplication; initial load/watch-later
  SEEK/restart events cannot satisfy the subsequent explicit seek.
- Separate players, playlist order/current index/duplicates, exact seek flags,
  pause until head/window ready, independent pause/play/volume/mute/speed states,
  scalar restoration before unpause, duration clamp,
  unseekable streams, command errors, stop/shutdown/replacement cancellation,
  queued-restart cancellation without engine access in synchronous stopping or
  shutdown gaps before the eventual notification,
  missing files, synchronous opening failure, empty sessions, and Settings
  completion coordination.
- Music/minimized state, fullscreen/PiP normal rectangle, temporary animation
  cleanup, all loaded hidden/minimized normal cores, exclusion of plugin-owned
  windows, immediate-Restart capture at actual termination, and Later clearing
  legacy/pending handoffs while retaining only the saved accent choice.
- Source-placement checks for the real AppDelegate, PlayerCore, and window
  integration, including frame-before-show and launch preference suppression.

`TestDoubles.swift` provides only the mpv/player and native-window boundary
behavior needed to drive production orchestration. It does **not** establish
real mpv accuracy, real window display ordering, or full-app compilation. The
separate `fixture.iinaplugin/` is owned by the parent QA workflow for real
isolated-profile multiwindow/playlist/head/frame acceptance. The focused result
is recorded in `build/restart-session-2026-10-24/model-lifecycle-checks.json`.

## Production scope

The handoff is armed only after the user chooses immediate Restart and its
relaunch helper starts successfully. The actual normal termination captures the
latest session before windows close or mpv stops. The next launch removes both
the restore intent and media snapshot before opening anything. Choosing Later
keeps the saved accent preference and clears any legacy/pending Settings or media
handoff; its later normal Quit/launch performs no explicit session restoration.
A new immediate-only persisted marker distinguishes this handoff from older
builds' Later flag; a legacy flag is removed on launch without reopening
Settings. Persisted flags alone cannot arm a new termination capture. Ordinary launch/quit
and normal playback-history options otherwise retain their existing behavior.

All initialized, loaded ordinary player cores are included, including hidden and
minimized windows; plugin-managed players are excluded to avoid duplicating a
global plugin's own window lifecycle. Nonrestartable inputs such as stdin/file
descriptors are skipped. Missing local files and actual mpv stop/shutdown errors
release the completion barrier for other windows. Settings is shown immediately
and re-fronted after the surviving media windows finish.

Ordinary window/music rectangle, paused/playing state, volume, mute, and speed
are restored. On the
same available displays, the frame stays exact; a frame on a removed display is
recovered to a reachable display. Fullscreen/PiP reentry is best effort: Spaces
and the native PiP bubble position are managed by macOS, without a public exact
restore API. Their underlying normal-window rectangle is retained. A requested
`absolute+exact` seek may still be limited by the media/stream; the actual engine
completion releases restoration and a material head mismatch is logged rather
than leaving Settings or other windows pending forever. A stream still loading
without any terminal engine event keeps only its own restoration pending; the
application and already shown Settings remain usable.
