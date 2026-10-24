# Plugin input and overlay regressions

Run from the repository root:

```sh
bash other/tests/plugin-input-overlay/run.sh
bash other/tests/plugin-input-overlay/run.sh --expired-listener
```

The harness compiles the production `PluginInputManager`, overlay container and
MainWindowController overlay factory. It uses real JavaScriptCore contexts,
managed references, garbage collection and native AppKit hit testing. Player and
overlay contents are fixtures; full WebKit rendering is not covered here.

Checks cover callback registration, removal with null/undefined, replacement,
active managed-reference retention, repeated removal before input dispatch and
an expired context. Overlay checks preserve native control hits through empty,
nonclickable and hidden overlays while keeping interactive overlay children.

The expired-context check is a separate process because the previous production
implementation traps when invoking that callback. Logs and binaries are written
under `build/plugin-input-overlay-tests`.
