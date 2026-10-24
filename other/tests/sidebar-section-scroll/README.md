# Sidebar section scrolling

Run `bash other/tests/sidebar-section-scroll/run.sh` from the repository root.
The harness compiles the production sidebar controller, section navigation,
native scroll views, track selectors, tab transitions and header selector.
Player services, preferences and the surrounding pane layout are fixtures.

Coverage includes two/four-section sidebars, direct horizontal mouse ticks,
phased trackpad swipes, precise phase-free bursts, cancellation, axis locking,
momentum after a tab change, first/last boundaries, header/content routing,
duplicate responder delivery, nested horizontal strips and rapid animated
switches. A real in-process scroll event verifies native vertical scrolling;
the check waits for AppKit's deferred scrolling instead of assuming it is
synchronous. No events are posted to other applications.

Native window dispatch also covers production Video, Audio, Primary Subtitles
and Secondary Subtitles track lists nested in the settings scroll view. It
checks side-wheel delivery, swipe release, momentum, cancellation, local
vertical scrolling, slight table-width overflow, unchanged media track
selection and lists containing only `<None>`. This regression fails on the
original plain-NSScrollView track selector.

Empty, short and exactly fitting lists must pass vertical wheel events to the
outer sidebar. The production Aspect/Crop viewport also passes vertical events
while retaining horizontal scrolling. Coverage includes slight horizontal drift
in a vertical event and the shared trackpad-axis guard. The output directory can
be overridden with `SIDEBAR_SCROLL_OUTPUT_DIR`.

Actual trackpad feel and physical side-wheel hardware remain full-app/manual
acceptance beyond synthetic component events.

Motion checks inspect the actual CA animations attached by the production
section transition and header. For two/four tabs, capsule geometry, icon/title
frames and title opacity must match the content push's duration, easing control
points and start transaction. Forward/reverse and rapid switches, unchanged
layout during animation, Reduce Motion and Disable animations are covered.
`SIDEBAR_PANE_SOURCE` and `SIDEBAR_HEADER_SOURCE` can select saved production
sources to reproduce a timing regression without changing the working tree.
