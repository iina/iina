# Plugin lifecycle regression tests

These tests build and run a disposable IINA application from the current checkout.
They never launch or replace an installed IINA. The generated app uses bundle ID
`org.iina.lifecycle-tests`, a private home directory, two local test plugins and
loopback-only network access.

From the repository root, after downloading IINA's normal build dependencies:

```sh
python3 other/tests/plugin-lifecycle/portable.py
```

For an existing dependency and Swift package cache, pass paths relative to the
checkout or absolute paths supplied by the caller:

```sh
python3 other/tests/plugin-lifecycle/portable.py \
  --dependencies-from path/to/deps \
  --cloned-packages path/to/SourcePackages \
  --package-cache path/to/PackageCache
```

The runner creates a unique ignored directory under `build/plugin-lifecycle-tests`,
copies the tracked checkout, overlays the 16 lifecycle source files, and appends
the Swift driver and deterministic pause probes only to that generated source.
It runs three modes: the lifecycle suite, exact download file semantics, and a
normal `exit(0)` while a staging writer is paused. Each child has a 45-second
limit. The exit test does not release or join its paused writer before exiting.

Coverage includes retained and idempotent teardown; timer, event, Promise and
native IO cancellation; exactly-once mpv hook continuation; reentrant resource
creation; isolation between two PlayerCore instances; exact download success,
error and cancellation; inode/mode/hard-link/symlink behavior; and immediate
staging cleanup during cancel, destination publication and process exit.

Generated source, products and logs are local evidence and are not contribution
files. The test-only source transformations must never be applied to production.
