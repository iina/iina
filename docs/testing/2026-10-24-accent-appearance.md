# Accent appearance and Settings restart checks

## Scope

This records checks of the normalized Part 5 upstream branch on arm64,
macOS 27.0.1. Part 5 is layered on the source-processing part of the interface
series. It uses the repository's existing engine dependencies and build identity;
it does not require the development player's custom engine.

## Fresh checks

- Release app build passed with code signing disabled and arm64 selected.
- Accent policy: 22 isolated process cases, 1,728 assertions over four native
  appearances, including default selection, migration and process-only overrides.
- Native accent selector: committed/cancelled/custom transactions, Base/en
  labels, native popup metrics and the 30 × 16 pt capsule bitmap passed.
- Plugin appearance: 51 real JavaScriptCore/WKWebView checks passed, including
  native/global getters, CSS tokens, optional callbacks, lifecycle cleanup,
  simple-mode compatibility and navigation seed refresh.
- Restart session: 137 model/coordinator checks and 22 production lifecycle
  placement checks passed.
- Settings restart rows/editor/path handling: 69 checks passed.
- Shared Restart/Later presenter: 42 checks each under light and dark appearance.
- The actual relaunch helper passed isolated LaunchServices environment probes
  with an original proxy both present and absent.

The focused runners resolve production input from their own checkout. Their
outputs are local under `build/`; no fixtures are installed in a personal
profile. Compiler cache paths are canonicalized so a symlink to an existing
cache does not register the same Clang module under two different paths.

## Reproduction

Run the Python runners in these directories from the repository checkout:

- `other/tests/accent-policy/`
- `other/tests/accent-color-settings/selection.py`
- `other/tests/plugin-appearance/`
- `other/tests/restart-session/`
- `other/tests/settings-restart/`
- `other/tests/settings-restart-presenter/`
- `other/tests/settings-restart-environment/`

Inspect each runner's arguments for output/cache locations. The environment
runner supports `--baseline-proxy absent` for the second baseline.

## Limits

This publication pass does not establish fresh full-player visual acceptance.
The native switch/control and physical color-panel probes that activate the
application were not run in this pass; their production sources are compiled by
the Release build. Earlier isolated development-build session tests are separate
evidence, not acceptance of this normalized branch.

Intel and older macOS runtime, exact native fullscreen/Spaces restoration,
physical full-app color-panel editing and real WebKit back/forward-cache history
return remain unverified. macOS owns PiP placement. Plugin-owned windows and
unavailable/nonrestartable media retain their existing constraints.

Later saves preferences without a special future-session handoff. Session
restoration here belongs only to an immediate Settings-requested Restart.
