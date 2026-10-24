# Settings restart environment acceptance

On macOS with Launch Services available, run:

```sh
python3 other/tests/settings-restart-environment/run.py
python3 other/tests/settings-restart-environment/run.py --baseline-proxy absent
```

The harness compiles **unmodified** `iina/AppRestart.swift` with inert dependencies,
typechecks a macOS 12 target, and ad-hoc signs a uniquely named/bundle-ID probe.
The native entrypoint first calls `AppRestart.runHelperIfRequested()`, exactly as
the application does. No `NSApplication` or windows are initialized; the bundle
has `LSUIElement=true` and no activation-policy call.

The initial process receives a test-specific stage marker, synthetic launch
`PATH`, and baseline proxy `http://127.0.0.1:1`. After the production entrypoint
captures that baseline, the probe mutates its own `PATH` with a different unique
fake prefix and `http_proxy` to `http://127.0.0.1:9`.
A same-executable witness proves Foundation Process inherits those runtime
mutations. The parent calls actual `AppRestart.startRelaunchHelper()`, the same
handoff used by `restart(restoring:)`, then exits normally. The helper waits for
that process exit and uses its production
`/usr/bin/open -n` path to relaunch the bundle through Launch Services. The final
process records whether runtime markers survived and whether launch `PATH` and
proxy match their exact synthetic baseline. The original stage marker is also
expected to survive this preservation policy; an exclusive one-shot file prevents
recursion. This distinguishes legitimate original environment from app-applied
runtime mutations.

The second invocation covers a proxy absent at initial launch, ensuring that an
app-applied proxy does not survive when the saved proxy setting is cleared.

Receipts under `build/settings-restart-2026-10-24/environment/` contain the source
SHA-256, target, macOS version, process IDs, stages, and only synthetic marker
booleans/equality results. The harness never dumps the environment, changes Launch Services
environment variables, writes personal preferences, or uses the network. It
reuses `build/sidebar-osd-tests/module-cache` to limit disk usage. It validates
the helper/relaunch boundary, rather than the Settings modal or session restore.
