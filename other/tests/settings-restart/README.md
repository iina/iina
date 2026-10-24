# Settings restart hooks

Run `python3 other/tests/settings-restart/run.py` from the owning checkout.

The harness extracts the production row observer, file chooser, MPV options editor,
and Advanced master predicate. It compiles them for macOS 12 and exercises native
inactive windows with isolated test defaults. Text/table editing state, panel
results, and drag input are controlled boundaries; it does not activate the player,
synthesize input, or change personal preferences.

Coverage includes committed versus continuous edits, initial/equal/net-no-op
changes, hidden/disabled/off-page/background changes, conditional Advanced gates,
config-folder key isolation, placeholder drafts, paste/delete/reorder, and key/value
Tab deferral. An actual chooser in a constrained native row verifies that long
paths truncate in the middle, keep the title readable, and do not grow the row.
A real bound NSTextField and native field editor exercise Return via
`insertNewline:` without activation, including AppKit retaining the editor afterward.
Full application presentation and actual keyboard input remain separate
acceptance checks. Results and production hashes are saved under
`build/settings-restart-2026-10-24/hooks/`.
