# Sidebar-header activation and OSC layers

Run `bash other/tests/sidebar-stacking/run.sh` on macOS with Xcode installed.

The runner compiles production MainWindow dispatch, SidebarController panel
routing and background classification, OSC click actions, titlebar handling and
scroll routing into native AppKit views. Player services and header layout are
fixture boundaries. Native button/table events and WebKit JavaScript are exercised.

Only a completed secondary click on the free area of a sidebar's own header
raises the whole sidebar group, with the selected sidebar foremost. Native repeat
secondary clicks are accepted regardless of the system click count. Header buttons/segments, content, populated and empty playlist rows,
resize handles, dragged/cancelled presses and the player titlebar cannot raise a
sidebar. Primary sidebar background clicks retain their existing reveal action.
A plugin's primary DOM background observer remains; secondary DOM clicks do not
send a host activation message or alter panel depth. Native plugin menus and
plugin-provided secondary handlers keep their input.

OSC keeps its configurable background actions and double-click cancellation.
Depth changes preserve frames and constraints. Covered controls cannot receive
pointer or wheel input through higher panels. The companion sidebar-window-frame
`--panel-depth-only` checks real production OSC geometry, animated sidebar
opening/closing, independent reset and header/control/body exclusion for Settings,
Playlist and Plugins. The osc-position-reset suite verifies saved defaults,
session placement, window bounds, resize, protected motion and lifecycle behavior.

Outputs default to build/sidebar-stacking/tests; OUTPUT_DIR can redirect them.
These native fixtures do not replace full-player physical acceptance.
