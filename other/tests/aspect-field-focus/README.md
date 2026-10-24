# Aspect input focus

Run `bash other/tests/aspect-field-focus/run.sh` on macOS. The harness extracts the production `AspectRatioView` and exercises actual AppKit field-editor state, inside/outside clicks, other-window isolation, focus transfer and monitor detach/reattach. Unrelated player and layout services are stubs. The field retains its native exterior focus ring. Full-app verification covers the unclipped ring at the horizontal scroll boundary and event-monitor dispatch; the harness calls the production dismissal handler with synthetic events.
