# Plugin process output

Run `python3 other/tests/plugin-process-output/run.py` on macOS. The runner
extracts the production `exec` method and its pipe collector; path permissions,
logging and plugin ownership are fixtures. Processes, pipes, JavaScriptCore
promises and the main run loop are real.

Checks cover main-thread callback affinity, stream tails, interleaved output
larger than the pipe buffer, callback order before promise settlement, split
UTF-8 collection, empty streams, missing executables, repeated spawn failures
and nonzero exit status. `--source` accepts an older implementation for a
causal negative control. `--module-cache` permits an existing compiler cache.

This does not exercise installed plugins or arbitrary child processes that
retain inherited output handles after their parent exits.
