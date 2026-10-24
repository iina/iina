# Deferred OSD delivery

Run `bash other/tests/osd-delivery/run.sh`.

The harness extracts the production `PlayerCore.sendOSD` method. It queues a
message, stops the player before the main queue delivers it, and fails if the
window tries to use its closed engine. It also covers ordinary queued delivery
and an already closed player. This regression corresponds to the stale OSD
`mpv_get_property` crash observed while terminating an early crop-animation lab.
