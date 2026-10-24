final class SeekPreviewPlayerFixture {
  enum State { case playing, paused }
  struct Info { var state = State.playing }
  var info = Info()
  let mainWindow: MainWindowController
  var pauses = 0
  var resumes = 0
  init(mainWindow: MainWindowController) { self.mainWindow = mainWindow }
  func pause() { pauses += 1; info.state = .paused }
  func resume() { resumes += 1; info.state = .playing }
}

// Production hover timers and MainWindow mouse handlers, with native fixture views.
func runSeekPreviewHoverChecks() {
  Preference.values = [.disableAnimations: true, .enableControlBarAutoHide: true, .settingsLeading: true]
  let controller = MainWindowController()
  let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 1000, height: 600),
                        styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  controller.window = window
  let content = window.contentView!
  controller.titleBarView = ChromeFixture(minimumWidth: 180, titlebar: true)
  controller.oscBottomView = ChromeFixture(minimumWidth: 28, titlebar: false)
  content.addSubview(controller.titleBarView)
  content.addSubview(controller.oscBottomView)
  controller.sidebars.installSubviews(in: content)
  content.addSubview(controller.timePreviewView)
  content.addSubview(controller.chapterPreviewView)
  content.addSubview(controller.playSlider)
  content.addSubview(controller.osdView)
  controller.osdView.isHidden = true
  window.orderFrontRegardless()
  controller.hideSeekPreview()
  func wait(_ duration: TimeInterval, tracking: Bool = false) {
    let deadline = Date().addingTimeInterval(duration)
    while Date() < deadline {
      if tracking { RunLoop.main.run(mode: .eventTracking, before: Date().addingTimeInterval(0.002)) }
      else { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
    }
  }
  func move(_ x: CGFloat, _ y: CGFloat = 10) {
    let point = controller.playSlider.convert(NSPoint(x: x, y: y), to: nil)
    let event = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
      context: nil, eventNumber: 1, clickCount: 0, pressure: 0)!
    controller.mouseMoved(with: event)
    controller.hideControlTimer?.invalidate()
  }
  func visible() -> Bool { !controller.thumbnailPeekView.isHidden && !controller.timePreviewView.isHidden && !controller.chapterPreviewView.isHidden }
  func hidden() -> Bool { controller.thumbnailPeekView.isHidden && controller.timePreviewView.isHidden && controller.chapterPreviewView.isHidden }

  move(100)
  check(hidden(), "timeline entry waits before presenting the preview")
  wait(0.06)
  check(hidden(), "a brief crossing does not flash a preview")
  move(220)
  wait(0.07)
  check(visible() && controller.seekPreviewUpdates == 1 &&
        controller.lastSeekPreviewPoint == controller.playSlider.convert(NSPoint(x: 220, y: 10), to: nil),
        "continued movement does not restart entry delay and presents the latest position")
  move(260)
  check(visible() && controller.seekPreviewUpdates == 2,
        "visible preview updates immediately along the timeline")
  move(260, 50)
  check(visible(), "leaving the timeline retains the preview during the exit grace period")
  wait(0.14)
  check(visible(), "preview remains visible beyond the previous 120ms exit deadline")
  move(280)
  check(visible() && controller.seekPreviewUpdates == 3, "reentry resumes immediately without another entry delay")
  wait(0.10)
  check(visible(), "a cancelled hide cannot remove the reentered preview")
  move(280, 50)
  wait(0.14)
  move(300, 50)
  wait(0.09)
  check(hidden(), "continued movement outside does not postpone the hide deadline")

  let updatesBeforeBrush = controller.seekPreviewUpdates
  move(100)
  wait(0.04)
  move(100, 50)
  wait(0.22)
  check(hidden() && controller.seekPreviewUpdates == updatesBeforeBrush,
        "leaving before the entry deadline cancels presentation")
  let seekCell = SeekPreviewSliderCellFixture()
  seekCell.playerCore = SeekPreviewPlayerFixture(mainWindow: controller)
  let seekSlider = NSSlider(frame: NSRect(x: 0, y: 0, width: 400, height: 20))
  seekSlider.cell = seekCell
  move(100)
  if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
    Preference.values[.disableAnimations] = false
    wait(0.13)
    move(100, 50)
    wait(0.22)
    check(visible() && controller.thumbnailPeekView.alphaValue > 0 && controller.thumbnailPeekView.alphaValue < 1 &&
          controller.thumbnailPeekView.alphaValue == controller.timePreviewView.alphaValue &&
          controller.timePreviewView.alphaValue == controller.chapterPreviewView.alphaValue,
          "production MainWindow fades image, timestamp and chapter together")
  }
  check(seekCell.startTracking(at: NSPoint(x: 100, y: 10), in: seekSlider), "native slider starts an active seek")
  check(controller.timePreviewView.alphaValue == 1, "active seeking cancels fade and restores full timestamp opacity")
  Preference.values[.disableAnimations] = true
  check(controller.thumbnailPeekView.isHidden && !controller.timePreviewView.isHidden && controller.chapterPreviewView.isHidden && controller.isSeekingWithSlider,
        "active seeking shows the timestamp immediately while suppressing the thumbnail")
  wait(0.23)
  check(controller.thumbnailPeekView.isHidden && !controller.timePreviewView.isHidden && controller.chapterPreviewView.isHidden,
        "cancelled hover cannot interrupt the active-seek timestamp")
  seekCell.stopTracking(last: NSPoint(x: 100, y: 10), current: NSPoint(x: 150, y: 10), in: seekSlider, mouseIsUp: true)
  check(hidden() && !controller.isSeekingWithSlider && seekCell.playerCore.pauses == 1 && seekCell.playerCore.resumes == 1,
        "seek completion clears preview state and preserves pause/resume behavior")
  move(100)
  controller.trackPluginMenu { wait(0.23) }
  check(hidden(), "menu tracking cancels a pending preview")
  move(100)
  controller.oscFloatingView.isDragging = true
  wait(0.23)
  check(hidden(), "delayed presentation rechecks OSC dragging")
  controller.oscFloatingView.isDragging = false
  move(100)
  controller.hideUI(force: true)
  wait(0.23)
  check(hidden(), "hiding the OSC cancels pending preview presentation")
  controller.animationState = .shown
  move(100)
  controller.osdView.frame = controller.playSlider.frame
  controller.osdView.isHidden = false
  wait(0.23)
  check(hidden(), "delayed presentation rechecks OSD occlusion")
  controller.osdView.isHidden = true
  move(100)
  controller.isSeekingWithSlider = true
  controller.cancelSeekPreviewHover()
  wait(0.23)
  check(hidden(), "starting an active seek cannot revive a pending hover preview")
  controller.isSeekingWithSlider = false
  move(100)
  controller.sidebars.show(sidebar: .settings)
  content.addSubview(controller.sidebars.leadingSidebar.view, positioned: .above,
                     relativeTo: controller.playSlider)
  wait(0.23)
  check(hidden(), "delayed presentation rechecks a newly covering sidebar")
  content.addSubview(controller.playSlider, positioned: .above,
                     relativeTo: controller.sidebars.leadingSidebar.view)
  move(100)
  wait(0.23)
  check(visible(), "a timeline above a sidebar keeps its hover preview available")
  controller.sidebars.hideAllSideBars(animate: false)
  let closingDeadline = Date().addingTimeInterval(0.5)
  while controller.sidebars.sideBars.contains(where: { !$0.view.isHidden }) && Date() < closingDeadline { wait(0.002) }
  check(controller.sidebars.sideBars.allSatisfy { $0.view.isHidden }, "sidebar teardown completes before the next hover")
  controller.animationState = .shown
  move(100)
  wait(0.23, tracking: true)
  check(visible(), "hover deadlines continue in native event-tracking mode")
  controller.hideSeekPreview()
  move(100)
  controller.hideSeekPreview()
  window.close()
  wait(0.23)
  check(hidden(), "explicit teardown leaves no delayed preview after window close")
  controller.hideControlTimer?.invalidate()
  runSeekPreviewFadeChecks()
  runChapterPreviewChecks()

  var callbacksAfterRelease = 0
  var owner: SeekPreviewHoverController? = SeekPreviewHoverController(canShow: { _ in true },
    show: { _ in callbacksAfterRelease += 1 }, hide: {})
  weak var weakOwner = owner
  owner?.hover(at: .zero)
  owner = nil
  wait(0.23)
  check(weakOwner == nil && callbacksAfterRelease == 0, "pending hover timers do not retain their owner or fire after release")
}

// Render and measure the production bubble views and MainWindow placement method.
func runChapterPreviewChecks() {
  let controller = MainWindowController()
  let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 480, height: 300),
                        styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  controller.window = window
  let content = window.contentView!
  content.wantsLayer = true
  content.layer?.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.24, blue: 0.28, alpha: 1).cgColor
  content.addSubview(controller.playSlider)
  content.addSubview(controller.thumbnailPeekView)
  content.addSubview(controller.timePreviewView)
  content.addSubview(controller.chapterPreviewView)
  controller.timePreviewView.textField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
  controller.chapterPreviewView.textField.font = .systemFont(ofSize: 11)
  controller.thumbnailPeekView.wantsLayer = true
  controller.thumbnailPeekView.layer?.backgroundColor = NSColor.darkGray.cgColor
  let oldWidth = UserDefaults.standard.object(forKey: "thumbnailWidth")
  defer {
    if let oldWidth { UserDefaults.standard.set(oldWidth, forKey: "thumbnailWidth") }
    else { UserDefaults.standard.removeObject(forKey: "thumbnailWidth") }
    window.close()
  }
  UserDefaults.standard.set(160, forKey: "thumbnailWidth")
  window.orderFrontRegardless()
  let thumbnail = NSSize(width: 160, height: 90)
  controller.thumbnailPeekView.imageView.image = NSImage(size: thumbnail, flipped: false) { rect in
    NSColor(calibratedRed: 0.34, green: 0.64, blue: 0.72, alpha: 1).setFill()
    rect.fill()
    let hill = NSBezierPath()
    hill.move(to: .zero)
    hill.line(to: NSPoint(x: 60, y: 65))
    hill.line(to: NSPoint(x: 160, y: 0))
    hill.close()
    NSColor(calibratedRed: 0.04, green: 0.46, blue: 0.28, alpha: 1).setFill()
    hill.fill()
    return true
  }
  var styles: [TranslucentView.Style] = [.visualEffect]
  if #available(macOS 26, *) { styles.append(.liquidGlass) }
  for (index, style) in styles.enumerated() {
    controller.timePreviewView.setStyle(style)
    controller.chapterPreviewView.setStyle(style)
    controller.oscPosition = .bottom
    controller.playSlider.frame = NSRect(x: 40, y: 20, width: 400, height: 20)
    controller.player.info.chapterTitle = "Очень длинное название главы — 東京の物語 🎬 с продолжением и дополнительными подробностями"
    controller.updateTimePreview(0.5)
    controller.timePreviewView.isHidden = false
    controller.positionSeekPreview(0.5, thumbnailSize: thumbnail)
    content.layoutSubtreeIfNeeded()
    content.displayIfNeeded()
    check(controller.thumbnailPeekView.frame.size == thumbnail, "thumbnail retains its configured display size (style \(index))")
    check(controller.timePreviewView.textField.stringValue == "02:30",
          "timestamp contains only time, independent of chapter title (style \(index))")
    check(!controller.chapterPreviewView.isHidden && controller.chapterPreviewView.frame.width <= thumbnail.width,
          "long Unicode chapter stays within thumbnail width (style \(index))")
    check(controller.chapterPreviewView.textField.usesSingleLineMode &&
          controller.chapterPreviewView.textField.lineBreakMode == .byTruncatingTail &&
          controller.chapterPreviewView.textField.frame.width < controller.chapterPreviewView.textField.intrinsicContentSize.width,
          "long chapter uses a single truncated line with a tail ellipsis (style \(index))")
    check(controller.chapterPreviewView.frame.minY >= controller.timePreviewView.frame.maxY + 4 &&
          controller.thumbnailPeekView.frame.minY >= controller.chapterPreviewView.frame.maxY + 5,
          "chapter and time have separate nonoverlapping bubbles below the thumbnail (style \(index))")
    if let directory = ProcessInfo.processInfo.environment["SEEK_PREVIEW_ARTIFACTS"] {
      if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
        content.cacheDisplay(in: content.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) {
          try! data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("chapter-bubbles-\(index).png"))
        }
      }
    }
    for fraction in [0.0, 1.0] {
      controller.positionSeekPreview(fraction, thumbnailSize: thumbnail)
      check([controller.timePreviewView, controller.chapterPreviewView, controller.thumbnailPeekView].allSatisfy {
        $0.frame.minX >= 0 && $0.frame.maxX <= content.bounds.width
      }, "preview bubbles stay inside the window at timeline endpoint \(fraction) (style \(index))")
    }
    controller.player.info.chapterTitle = "Intro"
    controller.updateTimePreview(0.5)
    check(controller.chapterPreviewView.frame.width < thumbnail.width,
          "short chapter keeps a compact bubble (style \(index))")
    controller.oscPosition = .top
    controller.playSlider.frame.origin.y = 260
    controller.positionSeekPreview(0.5, thumbnailSize: thumbnail)
    check(controller.chapterPreviewView.frame.maxY <= controller.timePreviewView.frame.minY - 4 &&
          controller.thumbnailPeekView.frame.maxY <= controller.chapterPreviewView.frame.minY - 5,
          "top OSC mirrors the stack below the slider (style \(index))")
    controller.oscPosition = .floating
    controller.positionSeekPreview(0.5, thumbnailSize: thumbnail)
    check(controller.thumbnailPeekView.frame.minY >= 0 && controller.thumbnailPeekView.frame.maxY < controller.playSlider.frame.minY,
          "floating OSC near the top accounts for chapter height when flipping the stack (style \(index))")
    controller.isSeekingWithSlider = true
    controller.updateTimePreview(0.5)
    check(controller.chapterPreviewView.isHidden && controller.timePreviewView.textField.stringValue == "02:30",
          "active seeking retains the timestamp alone (style \(index))")
    controller.isSeekingWithSlider = false
    for title: String? in [nil, "", " \n "] {
      controller.player.info.chapterTitle = title
      controller.updateTimePreview(0.5)
      check(controller.chapterPreviewView.isHidden, "missing or blank chapters do not leave an empty bubble (style \(index))")
    }
    controller.player.info.chapterTitle = "First line\nSecond line"
    controller.updateTimePreview(0.5)
    check(controller.chapterPreviewView.textField.stringValue == "First line Second line",
          "multiline chapter metadata is displayed on one line (style \(index))")
    controller.hideSeekPreview()
    check(controller.chapterPreviewView.isHidden && controller.timePreviewView.isHidden,
          "shared teardown hides both text bubbles (style \(index))")
  }
}

func runSeekPreviewFadeChecks() {
  func wait(_ duration: TimeInterval, tracking: Bool = false) {
    let deadline = Date().addingTimeInterval(duration)
    while Date() < deadline {
      RunLoop.main.run(mode: tracking ? .eventTracking : .default, before: Date().addingTimeInterval(0.002))
    }
  }
  var visible = false
  var opacity: CGFloat = 1
  var animate = true
  var hides = 0
  let hover = SeekPreviewHoverController(canShow: { _ in true }, show: { _ in visible = true },
    hide: { visible = false; hides += 1 }, setOpacity: { opacity = $0 }, shouldAnimate: { animate })
  hover.hover(at: .zero)
  wait(0.13)
  hover.leave()
  wait(0.12)
  check(visible && opacity == 1, "exit holds full opacity during the 150ms grace period")
  wait(0.10)
  check(visible && opacity > 0 && opacity < 1, "exit fades progressively during the following 150ms")
  hover.leave()
  wait(0.13)
  check(!visible && hides == 1 && opacity == 1, "repeated leave does not restart the fade and completion restores reusable opacity")

  hover.hover(at: .zero)
  wait(0.13)
  hover.leave()
  wait(0.22)
  check(visible && opacity > 0 && opacity < 1, "second presentation can enter a new fade")
  hover.hover(at: NSPoint(x: 20, y: 0))
  check(visible && opacity == 1, "reentry during fade restores full opacity immediately")
  wait(0.20)
  check(visible && hides == 1 && opacity == 1, "cancelled fade cannot hide a reentered preview")

  hover.leave()
  wait(0.08)
  hover.hover(at: .zero)
  wait(0.28)
  check(visible && opacity == 1 && hides == 1, "reentry during grace cancels both delayed fade and hiding")
  hover.leave()
  wait(0.22)
  hover.cancel(hidePreview: false)
  check(visible && opacity == 1, "active-seek cancellation restores opacity without hiding its timestamp")
  wait(0.20)
  check(visible && hides == 1, "active-seek cancellation leaves no pending fade completion")

  hover.hover(at: .zero)
  wait(0.13)
  hover.leave()
  wait(0.22)
  hover.cancel()
  check(!visible && opacity == 1, "lifecycle teardown hides immediately in the middle of a fade")
  let hidesAfterTeardown = hides
  wait(0.20)
  check(!visible && hides == hidesAfterTeardown, "teardown removes every scheduled fade tick")

  animate = false
  hover.hover(at: .zero)
  wait(0.13)
  hover.leave()
  wait(0.12)
  check(visible && opacity == 1, "disabled animation retains the grace period")
  wait(0.07)
  check(!visible && opacity == 1, "disabled animation skips the fade after the grace period")

  animate = true
  hover.hover(at: .zero)
  wait(0.13)
  hover.leave()
  wait(0.22, tracking: true)
  check(visible && opacity > 0 && opacity < 1, "fade advances during native event tracking")
  wait(0.13, tracking: true)
  check(!visible, "fade completes during native event tracking")

  var orphanCallbacks = 0
  var owner: SeekPreviewHoverController? = SeekPreviewHoverController(canShow: { _ in true }, show: { _ in },
    hide: { orphanCallbacks += 1 }, setOpacity: { _ in orphanCallbacks += 1 })
  weak var weakOwner = owner
  owner?.hover(at: .zero)
  wait(0.13)
  owner?.leave()
  wait(0.22)
  let callbacksBeforeRelease = orphanCallbacks
  owner = nil
  wait(0.20)
  check(weakOwner == nil && orphanCallbacks == callbacksBeforeRelease,
        "a running fade neither retains its owner nor calls views after release")
}
