# Aspect and rotation motion integration

Run `bash other/tests/geometry-motion/run.sh` on macOS. The executable opens no
visible windows and launches no player or renderer. Compiler warnings are errors.
Source snapshots, SHA-256 hashes, generated Swift, executable and results are
written to `build/geometry-motion-tests/`.

The runner extracts the actual production `GeometryMotion` fields, enqueue,
perform, output readiness, start, finish, cancel, native binding and duration
methods from `MainWindowController.swift`. It also extracts the aspect/rotation
setters, source predicates, video geometry, Default pixel-aspect and raw rotation
selection, native-frame request, seek intent and OSD token methods from
`PlayerCore.swift`, and the native affine presenter, geometry helper and complete
shared animation clock from `InteractiveMode.swift`. The actual notification
prefix of `playbackRestarted` is extracted up to its unrelated log/time/UI updates;
the actual `.windowSize` pinch `.began` block is extracted separately.

The extracted clock records its requested policy and retains its existing
`advance`, `tick` and watchdog objects. Integration checks drive the existing
`advance` closure with selected normalized times. Clock-origin checks use a real
paused native display link, feed controlled target timestamps to the actual
`tick`, and fire the actual watchdog. Progress, first-tick start, generation
checks, update, completion, timer fallback and watchdog logic remain production
code. One check also runs the real 400 ms Timer fallback without a screen or
manual advancement.

Coverage includes:

- PAR and effective rotation readiness, including 180 degrees, square video and
  Default with unchanged display aspect; embedded 90/180/270-degree rotation
  remains distinct from the requested user angle; native-frame callback ownership.
- Delayed decoder metadata cannot release an old aspect/rotation frame. Expected
  readiness uses committed options and raw file metadata, including embedded
  90-degree file rotation with an existing user rotation. Independently published
  new output can release readiness while decoder metadata remains old.
- Default restores nonsquare PAR from the selected track, then falls back to a
  finite positive decoder PAR or 1. Audio-only source dimensions apply options
  directly without acquiring a geometry/OSD scope.
- Canonical target-aspect raster allocation before inverse rotation compensation,
  fixed raster dimensions, synchronized window/OSC/layout/projection order,
  400 ms smoothstep, exact endpoints and no per-tick engine writes.
- New geometry motion opts into first-refresh start: a 600 ms late initial
  target timestamp produces zero progress and retains a full 400 ms movement.
  Its watchdog preserves a visible/on-screen window before the first refresh,
  while hidden or occluded windows can complete. Default Crop calls retain the
  previous clock origin and watchdog behavior. Cancellation and zero duration
  preserve their lifecycle semantics.
- Subsequent aspect overrides and 90/180/270-degree rotations; strict exclusion
  of zoom, pan, panscan, align, margins, scaling, arbitrary angles, unscaled video,
  additional filters and independent video graphs. Crop's stricter source
  predicate remains separate. An owned audio-only graph remains eligible.
- Latest pending aspect and rotation independently survive rapid mixed requests;
  failed writes, failed frames, stale callbacks, cancellation and new media cannot
  publish an obsolete completion or issue queued engine writes.
- Paused restart before metadata retains cached readiness; restart after waiter
  registration reuses the current frame if the waiter missed it. Duplicate
  callbacks, restart after completion and stale media do not publish twice or
  acquire another owner's state. No restart path adds seek or engine writes.
- Cancellation before output does not apply another option delta to old output.
  Both aspect/rotation channels derive their replacement from committed options;
  cancelled cached readiness remains with its owner. Pinch begins at the current
  intermediate frame and prevents an obsolete clock from moving it afterward.
- Reduced/disabled motion, fullscreen and PiP bypass the visual owner; unlocked
  sizing retains the supplied manual outer frame.
- Unsupported graph fallback distinguishes the initial readiness query from a
  real output event, including a graph that replaces decoder PAR and rotation.
- Actual final OSD delivery guards and actual seek-intent/token methods: internal
  refresh SEEK is suppressed, deliberate user seek and pause remain deliverable
  during geometry motion, and Crop/persistent/preferences retain their gates.

Controlled boundaries are explicit. The fixture supplies engine properties and
their output publication independently, invokes stored native-frame callbacks,
and supplies the target window frame at `handleVideoSizeChange`. It uses native
NSWindow/NSView/CALayer objects for layout and affine geometry, but does not run
the real source-scale/minimum/screen target-selection algorithm, OpenGL, mpv,
full displayOSD UI or physical display-link delivery. OSD delivery tests extract
the real early guards and turn only their void return into an observable Bool.
Seek scope tests retain the real event-drain callback with a controlled queue.
Restart tests control native-layer update/callback delivery, and pinch tests
exercise its production beginning block after selecting the window-size action;
they do not synthesize physical input or execute unrelated restart UI updates.
These checks do not establish live pixels, compositor cadence, HDR, visible
quality, or the engine's actual metadata ordering. The delayed-decoder cases are
regression assertions; they require readiness to be independent of input
metadata becoming current immediately after an option write.

Alternate source snapshots can be tested with `GEOMETRY_MOTION_MAIN_SOURCE`,
`GEOMETRY_MOTION_PLAYER_SOURCE`, `GEOMETRY_MOTION_INTERACTIVE_SOURCE`, and a separate
`GEOMETRY_MOTION_OUTPUT_DIR`. This permits negative controls without editing
production files.

The clock-origin negative control forcing opt-in movement to start at the initial
call rather than its first refresh fails 7 of 294 checks. An earlier signature
negative control replacing raw file rotation with an old-output option delta and
retaining old output PAR during rotation failed 32 of 277 checks. These controls
make both preparation-time loss and cancellation regressions observable without
editing production.
