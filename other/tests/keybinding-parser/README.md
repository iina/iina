# Malformed keybinding input

Run `python3 other/tests/keybinding-parser/run.py`. The runner compiles the
production parser and StreamReader with fixture mapping objects/logging.
Files are temporary and contain malformed IINA directives, empty actions,
inline comments with and without spacing, line-ending variants, normal
application/mpv commands and a missing path. No user configuration is read.

`--source` accepts the prior parser for a negative control; the bare
`#@iina#comment` case previously indexed before the start of its string.
