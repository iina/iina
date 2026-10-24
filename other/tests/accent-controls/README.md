# AppKit accent adapters

Bounded native probe for `AccentControls.swift`. It compiles only the shared color policy, adapters, and standalone harness; it does not build or launch the player.

```sh
xcrun swiftc iina/AppAccentColor.swift iina/AccentControls.swift other/tests/accent-controls/AdapterProbe.swift -o /tmp/iina-accent-adapter-probe
/tmp/iina-accent-adapter-probe /tmp/iina-accent-dark.png
/tmp/iina-accent-adapter-probe /tmp/iina-accent-light.png light
/tmp/iina-accent-adapter-probe /tmp/iina-accent-yellow-dark.png yellow
/tmp/iina-accent-adapter-probe /tmp/iina-accent-yellow-light.png light yellow
/tmp/iina-accent-adapter-probe /tmp/iina-accent-disabled.png disabled
```

The probe uses process-local `NSArgumentDomain` input, creates an offscreen accessory window, and briefly activates its own process to exercise AppKit's active-control rendering. It never changes persistent preferences, installed applications, or player state. Its test-only application/window subclasses report active/key state to make standalone rendering reliable.

Checks: inherited native convenience constructors, exact arbitrary NSColor property input, tinted rendered regions with ICC-aware sampling, tick-mark slider tint, source-list selection, black/white selected text contrast, restoration of original label/icon colors, radio/checkbox native accessibility roles, Cocoa binding, target/action, and native controls loaded without the subclasses.

Native AppKit retains its own lighting, antialiasing, inactive and disabled effects. Pixel checks allow those effects; no palette lookup or color approximation occurs in production. Inactive and disabled controls retain native neutral appearance. The source-list row draws its background through the public row API because AppKit's source-list highlight bypasses `drawSelection(in:)`.

Verified on macOS 27.0.1. Older macOS rendering has not been exercised. Public control tint support for in-window controls was introduced in macOS Monterey: [Apple WWDC21](https://developer.apple.com/videos/play/wwdc2021/10054/). API references: [NSSlider.trackFillColor](https://developer.apple.com/documentation/appkit/nsslider/trackfillcolor), [NSSegmentedControl.selectedSegmentBezelColor](https://developer.apple.com/documentation/appkit/nssegmentedcontrol/selectedsegmentbezelcolor), [NSButton.bezelColor](https://developer.apple.com/documentation/appkit/nsbutton/bezelcolor).

## Restart-sheet presentation regression

Run `python3 other/tests/accent-controls/alert-presentation.py`. This compatibility
entry point forwards to `../settings-restart-presenter/run.py`. Accent changes
now use the shared production `AppRestart.confirmSettingsChange(in:)` presenter;
the former extracted `SettingsPageUI.confirmAccentColorChange` method and
`AlertProbe.swift` are superseded.

The shared suite exercises native light/dark sheets, the real accent default
button cell, Return/Escape, same-turn and active-sheet coalescing, other-sheet
ordering, closed/hidden Settings cleanup, and immediate-versus-Later handoff
behavior. It replaces only the relaunch/termination method body with a recording
boundary, keeps unique test preferences isolated, and never activates the test
application. See `../settings-restart-presenter/README.md` for the exact scope.
`--output` is retained, including `alert-checks.json`; arbitrary legacy `--source`
extraction is retired. The checks cover native presentation boundaries and
responses; they do not measure every compositor frame.
