# AccentSwitch acceptance harness

Run on a Mac with an interactive WindowServer session:

```sh
python3 other/tests/accent-switch/run.py
```

The harness compiles the actual `iina/AccentSwitch.swift` with a deterministic,
custom RGB `AppAccentColor` fixture and a macOS 12 deployment target. It runs an
isolated application with an offscreen key window, briefly activates that test
application to exercise active native rendering, then restores the previously
active application. It does not change system settings, the app's preferences,
or any user profile. Output and small PNGs are saved in the selected build
folder (`--output` can override the default).

Checks cover actual hosted pointer events, Cocoa value binding and inverted
binding, single binding write/target invocation, external KVO and programmatic
state changes, `animator().state`, synchronous target reversion, disabled input,
native keyboard Space, one keyboard-focus owner, AX role/subrole/label/press,
absence of duplicate accessible child switches, and native control sizes.
Image checks wait for the native switch animation to finish before comparing
its tinted on state and neutral off state. The test has no dependency on the
user's current system color.

`tint-probe.swift` is the initial independent native SwiftUI rendering probe.
It compares `.tint(customRGB)`, `SwitchToggleStyle(tint:)`, and the untinted
system switch. The production adapter uses `.tint`.
