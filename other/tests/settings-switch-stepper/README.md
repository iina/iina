# Switch input stepper

Run `bash other/tests/settings-switch-stepper/run.sh` on macOS. The harness
extracts the production SwitchWithInput and TextFieldWithSwitch classes. It
exercises native AppKit controls, target/action delivery, numeric bounds,
fractional increments, Cocoa value binding and switch enablement. Unrelated
settings layout and localization services are stubs. Full-app verification
covers the OSC settings layout and preference persistence via independent readback.
