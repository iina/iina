# SharePlay for IINA — implementation and design proposal

This branch implements an experimental native macOS SharePlay integration for IINA's existing mpv player. It is a local implementation for review, not a claim that the official IINA release supports SharePlay. Related upstream request: [#5150](https://github.com/iina/iina/issues/5150).

## Experience

During a FaceTime call, open a finite, seekable video and choose **Playback → SharePlay… → Start SharePlay**. Other participants open the same modified application and use **Use Current Video** or **Choose Local Video…**. Each person supplies their own file or independently accessible URL. Local paths, bookmarks, URL credentials, and media bytes are not sent through the activity.

The activity contains a random content identifier, video title, and duration. Joining requires confirmation that the video is the same edition; duration must match within one second. Duration is only a sanity check and does not prove that scenes match. Different edits cannot be synchronized by this implementation.

Play, pause, speed changes, seeks, and chapter navigation coordinate the group. Volume, subtitles, and video appearance remain local. One window participates in one video session; changing focus does not move the session to another player. **Leave** disconnects only this Mac; **End for Everyone** ends the group activity. Both leave local playback paused.

Automatic pause/resume preferences for inactive, minimized, fullscreen, and PiP windows are suppressed only in the shared window. Sleep and network buffering suspend local coordination, then catch up on recovery. **Rejoin Playback** recovers from an automation or operation failure.

Playlist changes, automatic advancement, A–B/file/playlist loops, and frame stepping are unavailable in the shared window. Original loop/keep-open settings are restored on leaving. Compound mpv commands are blocked. Script bindings suspend participation visibly; arbitrary Lua scripts or direct mpv IPC are not a supported way to control the group. Unexpected changes trigger suspension or bounded resynchronization. Live streams, DRM services, file transfer, and shared playlists are outside this version.

## Implementation

- `IINAWatchActivity` and `SharePlayManager` manage activation, user-selected media, join/leave/end, and the native AppKit panel. All UI and session state changes run on the main thread. The session listener starts at launch, including when no file is open.
- `SharePlayCoordinator` uses Apple's `AVDelegatingPlaybackCoordinator` and forwards its play, pause, seek, and buffering commands to a testable transport. No AVPlayer replacement or mpv binary patch is introduced.
- `SharePlayPlayback` distinguishes local requests from coordinator commands, acknowledges obsolete/cancelled commands, waits for seeks and buffering, and schedules playback using Core Media's host clock. Operations have bounded timeouts; failure suspends participation with a visible notice.
- `PlayerCore` and the existing `MPVController` entry points route UI, keyboard, and ordinary plugin transport operations consistently. Direct mpv API access remains inside the existing controller. The mpv event-reading queue is not used for coordination work.
- Timing is checked only while a session is active. Sustained differences above 250 ms request reapplication of group state, with a five-second correction cooldown. The 250 ms threshold is a correction target, not a measured guarantee across Macs or audio devices.

The prototype does not attempt frame-accurate output synchronization: decoder latency, display timing, Bluetooth audio, and slow seeks require physical validation.

## Building and signing

1. Follow the repository's normal build instructions, including `other/download_libs.sh` and Swift package resolution. The downloader expects the checkout directory to be named lowercase `iina`; an uppercase directory needs that script's local checkout-name check adjusted.
2. Open `iina.xcodeproj` with the current public Xcode, select the `iina` scheme, and use your development signing team and an App ID registered for your own development builds. Use the same signed application identity on both Macs.
3. Enable **Group Activities** for that App ID in Signing & Capabilities. This branch already includes `com.apple.developer.group-session` in the target's entitlements. Merely compiling an unsigned build does not validate the capability or FaceTime integration. Do not commit your team, certificate, profile, or account changes.
4. Install your development build on two physical Macs using different Apple IDs, start a FaceTime call, and exercise the workflow above. macOS 12 or newer is required, consistent with current `develop`.

The available free Personal Team was tested with macOS signing: Xcode rejected Group Activities provisioning. A second Personal Team does not remove that restriction. A single enrolled development team can sign the test applications; FaceTime participants use different Apple Accounts.

Apple references: [custom playback coordination](https://developer.apple.com/videos/play/wwdc2021/10225/), [Group Activities capability](https://developer.apple.com/documentation/xcode/configuring-group-activities).

## Tests and acceptance

Run the maintained tests from the repository root:

```sh
bash Tests/run-shareplay-tests.sh
```

The runner uses Xcode's macOS XCTest runtime and IINA's downloaded `deps/lib/libmpv.2.dylib`. It can generate a 12-second synthetic video with FFmpeg/VideoToolbox; alternatively set `IINA_SHAREPLAY_FIXTURE` to an existing synthetic seekable fixture. Without a fixture, the real-mpv case reports an explicit skip. Tests and generated fixtures stay under ignored `build/`.

Automated checks cover routing, metadata validation, clock calculations, seek/readiness handling, deadline expiry, cancellation, obsolete commands, interruptions, and bounded drift correction. A headless real-mpv test checks scheduled 2× playback, an exact paused seek, and restart at 0.5×. The native coordinator identity test validates registration and teardown; it does not simulate a joined SharePlay group.

Before requesting merge, record physical two-Mac results for:

- Identical MP4 and MKV files in different directories, and independently accessible seekable VOD URLs.
- Controls from either Mac: play/pause, keyboard/media keys, scrubbing, chapters, and 0.5×/1×/2× playback; simultaneous input and late joining.
- Missing/wrong media, failed/slow seeks, network buffering, disconnection, sleep/wake, and leave/end while a command is pending.
- Fullscreen, PiP, unrelated player windows, normal playback without SharePlay, and restoration of loop/keep-open settings.
- A 20-minute timing run with visible timecodes: target a 95th-percentile difference no greater than 250 ms after settling, and recovery within three seconds after both players are ready. Record output/audio-device differences; do not infer rendered synchronization solely from mpv positions.

As of this implementation, automated and build verification are local. Cross-Mac FaceTime synchronization, capability provisioning, and the timing acceptance targets remain unverified until the hardware run is completed.

## Proposed upstream contribution

IINA's contribution guide requires a Design Proposal for UI changes. This document supplies the proposed behavior and architecture for that discussion. The draft contribution is related to [#5150](https://github.com/iina/iina/issues/5150); [Design Proposal #6544](https://github.com/iina/iina/issues/6544) requests maintainer feedback before any request to merge. Physical test evidence is still required. This implementation was developed with AI assistance, which must be disclosed in the PR description. No maintainer acceptance or release readiness is implied.
