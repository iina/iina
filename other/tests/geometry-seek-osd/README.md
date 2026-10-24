# Geometry refresh seek OSD

Run `bash other/tests/geometry-seek-osd/run.sh`.

The headless Swift harness extracts the production PlayerCore refresh and seek
intent state, pause/resume notification handling, lifecycle cancellation
prefixes, and MPVController SEEK/PLAYBACK_RESTART branches plus the actual event
drain implementation. A thread-safe fake native event stream exercises the
existing controller queue and main queue without opening a player or window.

It covers paused/playing internal refresh both outside and during geometry,
explicit seeking immediately before and during geometry, overlapping requests
and scopes, rejected/canceled command intent, queued events, stale completion,
media generation, paused Crop coexistence, pause/resume, and lifecycle cleanup.
This verifies the OSD classification and ordering contract; native event timing
and the visual geometry handoff still require application acceptance.
