# External attachment chooser lifetime

Run `python3 other/tests/external-track-chooser/run.py` on macOS. The runner
extracts all five production audio/video/manual-subtitle chooser actions.
AppKit sender controls and the player-state enum are real; the panel callback
and attachment receiver are fixtures. No panel or media file is opened.

The same-file positive cases and deferred results cover loaded/playing/paused,
loading/starting/stopping/idle/shutdown, a replacement media generation, and
release of the original player before selection completes. `--source-root`
permits a prior source tree for a causal negative control. This does not test
online subtitle providers.
