# OSD command routing

Run `bash other/tests/osd-command-routing/run.sh`.

The headless harness extracts the production `OSDCommandRouting` and
`OSDFeedbackValue` implementations. It checks raw and array command prefixes,
quoted semicolons, comments and escaping, actual seek commands, nonseeking
forward frame steps/mark operations, property-based seeking, and setting
mutation provenance. Expected syntax follows bundled mpv 0.41:

- https://github.com/mpv-player/mpv/blob/v0.41.0/input/cmd.c
- https://github.com/mpv-player/mpv/blob/v0.41.0/player/command.c
- https://github.com/mpv-player/mpv/blob/v0.41.0/DOCS/man/input.rst

This verifies classification only; command execution, event ordering, and
native UI acceptance are covered separately.
