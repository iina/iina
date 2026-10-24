# Native traffic-light slide checks

Run `bash other/tests/traffic-light-slide/run.sh` on macOS.

The harness extracts the button-tracking methods from `Titlebar.swift` and exercises real AppKit window buttons. It checks the offscreen start, shared animation duration, immediate visibility during the slide, native host/frame retention, layout refresh, hiding, Reduce Motion, and fullscreen restoration.

These checks verify the native animation setup. Visual synchronization with the complete player header still requires checking the built app.
