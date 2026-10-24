# Shared Settings restart presenter

Run `python3 other/tests/settings-restart-presenter/run.py` on macOS. The suite
compiles the actual `AppRestart.swift`, color policy, and AppKit accent adapters
for `arm64-apple-macos12`, reusing the existing
`build/sidebar-osd-tests/module-cache`. It exercises native NSAlert sheets in
light and dark appearance with an arbitrary custom accent.

Only the `restart(restoring:)` method body is replaced with a recording boundary
that can simulate failure and invoke the real one-shot prepare method. The
production presenter, coalescing/state cleanup, Later discard, restore markers,
and native default-button styling remain unchanged. The test does not spawn a
helper, terminate another app, load media, or claim to verify actual relaunch.
The unchanged restart/session suite and separate full-player/environment QA
cover those boundaries.

The fixture uses native offscreen windows, prohibits app activation, verifies
that the app stayed inactive, and removes its unique bundle preferences. No
personal/global preference domain or running personal player is modified.

Current checks cover:

- Already committed values exist before the deferred prompt; presenting it does
  not arm Settings or session restoration.
- Multiple commits in the same main-loop turn coalesce; requests during the
  active restart sheet do not queue duplicate sheets.
- Native Return/Escape equivalents retain the production accent default cell
  and route to immediate Restart or Later. Later clears legacy, immediate, and
  media restore keys while retaining the saved setting.
- Immediate callback receives the requesting Settings window; a simulated
  restart failure displays its error sheet without arming restoration.
- A preexisting picker sheet finishes before one deferred restart sheet appears.
- Closed or hidden Settings drops a queued request. Closing while waiting for
  another sheet leaves no stale prompt. Closing an active restart sheet dismisses
  it, and reusing the cached Settings window accepts a fresh request.

Results and the production source hash are recorded in
`build/settings-restart-presenter-2026-10-25/native-checks.json` by default;
`--output DIRECTORY` selects another evidence directory. These are native
boundary/response checks, not a measurement of every compositor frame or a
full-player window/seek acceptance run. Row gating and text/table commit
transactions are covered by `../settings-restart/run.py`.

The older `../accent-controls/alert-presentation.py` entry point forwards here
because accent changes now use the same production presenter.
