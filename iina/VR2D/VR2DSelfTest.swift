//
//  VR2DSelfTest.swift
//  iina
//
//  A way to get the reprojection pass's actual output onto disk, so it can be
//  compared against a ground truth rendered by `ffmpeg`'s `v360` filter.
//
//  Checking a projection by eye does not work: a wrong sign or a transposed
//  face still looks like a picture, and the plugin this fork replaces shipped a
//  bug that survived exactly that kind of inspection. Comparing pixels against
//  a reference does work, and it is what `other/vr2d-tests/shader.sh` does.
//
//  Entirely inert unless `IINA_VR2D_SELFTEST` names a directory holding a
//  `cases.json`. Nothing in the normal app calls into this beyond one guarded
//  line in `VR2DController.fileLoaded`.
//

import Cocoa

#if DEBUG

enum VR2DSelfTest {

  /// Directory holding `cases.json`, and where the renders are written.
  static let directory = ProcessInfo.processInfo.environment["IINA_VR2D_SELFTEST"]

  /// Directory for the interaction check, which drives the view with
  /// synthesised mouse events and reports what happened.
  static let inputDirectory = ProcessInfo.processInfo.environment["IINA_VR2D_INPUTTEST"]

  /// `true` while any self-test is running, whatever kind.
  static var isRunning: Bool { directory != nil || inputDirectory != nil }

  private struct Case: Decodable {
    var name: String
    var projection: String
    var layout: String?
    var swapEyes: Bool?
    var eye: String?
    var inHFov: Double?
    var inVFov: Double?
    var yaw: Double
    var pitch: Double
    /// Diagonal field of view. Matches `v360`'s `d_fov`.
    var fov: Double
  }

  private static var hasRun = false

  /// Render every case in `cases.json`, write each to a PNG, then quit.
  static func runIfRequested(for player: PlayerCore) {
    guard let directory, !hasRun else { return }
    hasRun = true

    let url = URL(fileURLWithPath: directory).appendingPathComponent("cases.json")
    guard let data = try? Data(contentsOf: url),
          let cases = try? JSONDecoder().decode([Case].self, from: data) else {
      Logger.log("VR2D self-test: cannot read \(url.path)", level: .error)
      NSApp.terminate(nil)
      return
    }

    Task { @MainActor in
      // Let the first frame land before asking for a picture back.
      try? await Task.sleep(nanoseconds: 2_000_000_000)

      for testCase in cases {
        player.vr2d.applyForSelfTest(source: source(from: testCase), view: view(from: testCase),
                                     eye: testCase.eye == "right" ? .right : .left)
        // One redraw to apply the new uniforms, then capture the next one.
        try? await Task.sleep(nanoseconds: 120_000_000)

        guard let image = await player.mainWindow.videoView.videoLayer.captureSnapshot() else {
          Logger.log("VR2D self-test: no snapshot for \(testCase.name)", level: .error)
          continue
        }
        write(compositingOverlays(over: image, of: player),
              to: URL(fileURLWithPath: directory).appendingPathComponent("\(testCase.name).png"))
      }

      Logger.log("VR2D self-test: rendered \(cases.count) cases into \(directory)")
      NSApp.terminate(nil)
    }
  }

  private static func source(from testCase: Case) -> VR2DSource {
    let projection: VR2DProjection
    switch testCase.projection {
    case "e": projection = .equirect
    case "fisheye": projection = .fisheye
    case "eac": projection = .eac
    default: projection = .halfEquirect
    }

    let layout: VR2DLayout
    switch testCase.layout {
    case "sbs": layout = .sbs
    case "tb": layout = .tb
    default: layout = .mono
    }

    let defaults: Double = projection == .equirect || projection == .eac ? 360 : 180
    return VR2DSource(layout: layout, swapEyes: testCase.swapEyes ?? false, projection: projection,
                      inHFov: testCase.inHFov ?? defaults,
                      inVFov: testCase.inVFov ?? (projection == .equirect || projection == .eac ? 180 : defaults))
  }

  private static func view(from testCase: Case) -> VR2DView {
    return VR2DView(yaw: testCase.yaw, pitch: testCase.pitch, fov: testCase.fov)
  }

  // MARK: - Interaction

  /// Drive the video view with synthesised mouse events and report what the
  /// view state did, so that panning can be checked without a human at the
  /// keyboard.
  ///
  /// The events go through `NSWindow.sendEvent`, so they are hit-tested and
  /// routed exactly as real ones are — which is the part worth testing. Calling
  /// the view's methods directly would prove nothing about whether the drag
  /// reaches the view at all rather than picking the window up and moving it.
  static func runInputChecksIfRequested(for player: PlayerCore) {
    guard let inputDirectory, !hasRun else { return }
    hasRun = true
    Logger.log("VR2D input check: scheduled")

    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      Logger.log("VR2D input check: starting")

      let vr2d = player.vr2d
      let window = player.mainWindow.window!
      let videoView = player.mainWindow.videoView
      var report: [String: Any] = [:]

      // Measure the paused-capture path with reprojection off first, so that a
      // stall can be attributed to the right side of the change. Detection may
      // already have switched it on for this file, so switch it off explicitly.
      vr2d.setEnabled(false, announce: false)
      try? await Task.sleep(nanoseconds: 200_000_000)
      player.pause()
      try? await Task.sleep(nanoseconds: 600_000_000)
      report["capturesWhileOff"] = await countCaptures(player, attempts: 5)
      player.resume()
      try? await Task.sleep(nanoseconds: 400_000_000)

      vr2d.setEnabled(true, announce: false)
      vr2d.applyForSelfTest(source: VR2DSource(layout: .sbs, swapEyes: false,
                                               projection: .halfEquirect, inHFov: 180, inVFov: 180),
                            view: VR2DView(yaw: 0, pitch: 0, fov: 90), eye: .left)
      try? await Task.sleep(nanoseconds: 200_000_000)

      report["canMoveWindowWhileOn"] = videoView.mouseDownCanMoveWindow
      Logger.log("VR2D input check: state captured")
      report["viewBefore"] = [vr2d.view.yaw, vr2d.view.pitch, vr2d.view.fov]

      // Pause first: panning has to work on a held frame, which is the whole
      // reason for doing this in the renderer rather than in a filter.
      player.pause()
      try? await Task.sleep(nanoseconds: 400_000_000)
      report["pausedBefore"] = player.info.state == .paused
      report["capturesWhileOn"] = await countCaptures(player, attempts: 5)
      let before = await capture(player)
      Logger.log("VR2D input check: paused and captured")

      // A drag across the middle of the video.
      //
      // The events go to the view directly. Synthesising them into
      // `NSWindow.sendEvent` was tried first and AppKit simply dropped them —
      // a background-launched app is not active, and inactive apps do not get
      // mouse dispatch. What that dispatch would have proved is covered above
      // instead: the hit test at this point lands on the video view, and the
      // view refuses to let the window be dragged while reprojection is on, so
      // AppKit has nowhere else to send the drag.
      let centre = NSPoint(x: videoView.bounds.midX, y: videoView.bounds.midY)
      videoView.mouseDown(with: mouseEvent(.leftMouseDown, at: centre, in: window))
      for step in 1...4 {
        let point = NSPoint(x: centre.x + CGFloat(step) * 20, y: centre.y)
        videoView.mouseDragged(with: mouseEvent(.leftMouseDragged, at: point, in: window))
        try? await Task.sleep(nanoseconds: 30_000_000)
      }
      videoView.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: centre.x + 80, y: centre.y), in: window))
      Logger.log("VR2D input check: drag sent")
      // Long enough for IINA's single-click timer to have fired if the drag had
      // been mistaken for a click.
      try? await Task.sleep(nanoseconds: 1_200_000_000)

      report["viewAfterDrag"] = [vr2d.view.yaw, vr2d.view.pitch, vr2d.view.fov]
      report["pausedAfterDrag"] = player.info.state == .paused

      let after = await capture(player)
      if let before, let after {
        write(before, to: URL(fileURLWithPath: inputDirectory).appendingPathComponent("before.png"))
        write(after, to: URL(fileURLWithPath: inputDirectory).appendingPathComponent("after.png"))
      }

      // A click that does not move must still reach IINA, so playback control
      // keeps working while looking around.
      videoView.mouseDown(with: mouseEvent(.leftMouseDown, at: centre, in: window))
      videoView.mouseUp(with: mouseEvent(.leftMouseUp, at: centre, in: window))
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      report["pausedAfterClick"] = player.info.state == .paused

      let fovBeforeScroll = vr2d.view.fov
      videoView.scrollWheel(with: scrollEvent(deltaY: 4))
      try? await Task.sleep(nanoseconds: 200_000_000)
      report["fovBeforeScroll"] = fovBeforeScroll
      report["fovAfterScroll"] = vr2d.view.fov

      // Building the settings page is the only way to find out that a binding
      // or an enum conformance is wrong, since the page is built lazily when
      // it is first shown.
      let settings = SettingsPageVideo()
      let settingsView = settings.getView()
      report["settingsSections"] = settings.builtSections.count
      report["settingsRendered"] = !settingsView.subviews.isEmpty

      let url = URL(fileURLWithPath: inputDirectory).appendingPathComponent("report.json")
      if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]) {
        try? data.write(to: url)
      }
      Logger.log("VR2D input check: \(report)")
      NSApp.terminate(nil)
    }
  }

  /// `captureSnapshot` waits for the layer to draw, and a paused player draws
  /// only when something forces it. If that never happens the await never
  /// returns, so the check needs its own deadline to be able to report a
  /// failure rather than hang.
  private static func capture(_ player: PlayerCore, timeout: Double = 4) async -> NSImage? {
    // Deliberately not a task group: cancelling a group still waits for its
    // children on the way out, and the whole point here is to walk away from a
    // capture that is never going to come back.
    final class Once: @unchecked Sendable {
      private let lock = Lock()
      private var continuation: CheckedContinuation<NSImage?, Never>?
      init(_ continuation: CheckedContinuation<NSImage?, Never>) { self.continuation = continuation }
      func resume(_ image: NSImage?) {
        let pending = lock.withLock { () -> CheckedContinuation<NSImage?, Never>? in
          let pending = continuation
          continuation = nil
          return pending
        }
        pending?.resume(returning: image)
      }
    }

    return await withCheckedContinuation { continuation in
      let once = Once(continuation)
      DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { once.resume(nil) }
      Task {
        let image = await player.mainWindow.videoView.videoLayer.captureSnapshot()
        once.resume(image)
      }
    }
  }

  /// How many of `attempts` captures come back within the deadline while
  /// paused. Run with reprojection off and on, this says whether the pass is
  /// responsible for a stall or whether it is IINA's own draw path.
  private static func countCaptures(_ player: PlayerCore, attempts: Int) async -> Int {
    var captured = 0
    for _ in 0..<attempts {
      if await capture(player) != nil { captured += 1 }
      try? await Task.sleep(nanoseconds: 150_000_000)
    }
    return captured
  }

  private static func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) -> NSEvent {
    return NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                              timestamp: ProcessInfo.processInfo.systemUptime,
                              windowNumber: window.windowNumber, context: nil,
                              eventNumber: Int.random(in: 1...100_000),
                              clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
  }

  private static func scrollEvent(deltaY: CGFloat) -> NSEvent {
    let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                     wheel1: Int32(deltaY), wheel2: 0, wheel3: 0)!
    return NSEvent(cgEvent: cg)!
  }

  /// Put the AppKit views that sit over the video back on top of a framebuffer
  /// capture.
  ///
  /// `captureSnapshot` reads the OpenGL framebuffer, which by definition holds
  /// only what the GPU drew — the reprojected video. Subtitles are an ordinary
  /// view above the layer, composited by the window server, so they are absent
  /// from that capture however correct they are on screen. This performs the
  /// same composition so the file matches what the display shows.
  private static func compositingOverlays(over image: NSImage, of player: PlayerCore) -> NSImage {
    let subtitles = player.mainWindow.vr2dSubtitleView
    guard !subtitles.isHidden, subtitles.bounds.width > 1,
          let video = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let rep = subtitles.bitmapImageRepForCachingDisplay(in: subtitles.bounds) else {
      return image
    }
    subtitles.cacheDisplay(in: subtitles.bounds, to: rep)
    guard let overlay = rep.cgImage,
          let context = CGContext(data: nil, width: video.width, height: video.height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
      return image
    }

    let full = CGRect(x: 0, y: 0, width: video.width, height: video.height)
    context.draw(video, in: full)
    context.draw(overlay, in: full)
    guard let composed = context.makeImage() else { return image }
    return NSImage(cgImage: composed, size: NSSize(width: video.width, height: video.height))
  }

  private static func write(_ image: NSImage, to url: URL) {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    do {
      try data.write(to: url)
    } catch {
      Logger.log("VR2D self-test: cannot write \(url.path): \(error)", level: .error)
    }
  }
}

#endif
