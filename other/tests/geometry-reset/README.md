# Geometry Reset observer refresh

Run `bash other/tests/geometry-reset/run.sh` on macOS. No application, renderer or
visible window is opened. The compiler treats warnings as errors.

The runner reuses the existing geometry-motion production extractor, substitutes
this focused test entry, and adds actual `resetTrackSettings`,
`scopedVideoSettings`, `removeCropFilter`, notification delivery, the mpv
`video-rotate` property-observer case and the native `RotationView`.

The regression is stale UI after one Reset: Aspect can own an asynchronous
transition while Rotation0 waits in Main's existing queue. Reset's immediate
track-settings notification reads the previous cached angle. The rotation
observer must refresh the sidebar after it updates that angle on main.

Checks cover paused/playing, Default/4:3, crop/no crop, existing preparation and
animation owners, exactly one canonical rotation0 write, Default/None/0 after
the queue drains, and a second Reset that changes no engine value. They also
cover asynchronous delivery order, no additional OSD or engine write from the
observer, malformed property error handling, and independent selected-track
rotation. Notification delivery updates a real NSSegmentedControl through the
actual RotationView observer; it is not replaced with a counter.

Native frame callbacks, target window selection, filter removal and unrelated
audio/color branches are controlled fixture boundaries. This does not verify
native pixels, actual mpv event order or the visible animation. The queue,
rotation option setter, reset sequence and selector refresh are production code.

Artifacts and source hashes are written to `build/geometry-reset-tests/`.
Set `GEOMETRY_RESET_MPV_SOURCE` and a separate `GEOMETRY_RESET_OUTPUT_DIR` to run
the old observer as a negative control without editing production.
