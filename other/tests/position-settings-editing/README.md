# Position sheet editing

Run `bash other/tests/position-settings-editing/run.sh` from the repository.

The harness extracts the production panel and text field classes and exercises native AppKit field editors with synthetic events. It checks Enter, default-button key routing, background clicks, transfer to another field, and restoration of empty, malformed, negative, out-of-range and overflowing values. The length tests also exercise native editor insertion and replacement, including rejection of a sixth digit and an oversized replacement. They do not establish physical keyboard or pointer acceptance in the player.
