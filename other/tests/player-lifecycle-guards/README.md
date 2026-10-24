# Player lifecycle guards

Run `python3 other/tests/player-lifecycle-guards/run.py --module-cache PATH`.
Use `--output PATH` to choose an evidence directory.

The runner compiles the production `PlayerState`, `PlaybackInfo.state` transition
rules, and public playback, track, subtitle-load and lifecycle methods against controlled
engine, background-work, notification and window boundaries. It covers every
player state, late playback actions, duplicate shutdown, stop-before-quit ordering,
background completion, the application stopped observer, and ordinary queued opens.
It does not activate an application, open media, run plugins, or change preferences.

The second fixture extracts production native scalar, string, option, node, filter
and hook wrappers with the real `MPVNode` implementation. Its C functions abort if
called with a null handle. It checks neutral results with no native calls at nil,
idle initialization with a retained handle, and filter removal with empty,
negative, stale, failed-read/write and malformed data plus a valid removal.

The hook fixture compiles `MPVHookValue` and its event branch with actual
JavaScriptCore. It checks synchronous, retained and asynchronous JavaScript
continuations, duplicate and parallel native calls, reentrancy, controller
release, late calls after handle removal, and unloaded-plugin hooks.

Actual mpv teardown, live plugin timers and native window ordering remain separate
integration checks.
