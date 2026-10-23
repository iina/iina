  func buildNativeGroups() {
    oscPlayControlView.addView(oscSpeedLabelLeftContainer, in: .center)
    oscPlayControlView.addView(oscPlayControlMiddleView, in: .center)
    oscPlayControlView.addView(oscSpeedLabelRightContainer, in: .center)
    oscPlayControlView.userInterfaceLayoutDirection = .leftToRight
    oscSpeedLabelLeft.isHidden = true
    oscSpeedLabelRight.isHidden = true
    leftLabel.stringValue = "01:15"
    rightLabel.stringValue = "4:44:30"
    installFloatingGroups()
    nativeWindow.aspectRatio = NSSize(width: 16, height: 9)
    nativeWindow.contentMinSize = nativeWindow.contentRect(forFrameRect: NSRect(origin: .zero, size: minimumWindowSize)).size
    nativeWindow.toolbar = NSToolbar()
    nativeWindow.toolbarStyle = .unifiedCompact
    let content = nativeWindow.contentView!
    content.addSubview(oscFloatingView)
    oscFloatingView.padding(.horizontal(greaterThan: 1), from: content)
    oscFloatingView.center(.x).padding(.bottom(10), from: content)
    rebuildToolbar(buttonCount: 4)
  }

  func installFloatingGroups() {
// GROUP_SETUP
  }

  func controlIsContained(_ view: NSView) -> Bool {
    let panel = oscFloatingView
    let rect = panel.convert(view.bounds, from: view)
    // AppKit rounds native frames to device pixels at fractional scales.
    return panel.bounds.insetBy(dx: -0.51, dy: -0.51).contains(rect)
      && view.superview != nil && !view.isHiddenOrHasHiddenAncestor
  }

  func assertControlGeometry(expectedToolbarCount: Int = 4) {
    for view in [muteButton!, volumeSlider!, playButton!, leftArrowButton!, rightArrowButton!, playSlider!, leftLabel!, rightLabel!] + oscToolbarView.views {
      precondition(controlIsContained(view), "Control escaped floating panel: \(view.frame) in \(oscFloatingView.frame)")
    }
    let playFrame = oscFloatingView.convert(playButton.bounds, from: playButton)
    precondition(abs(playFrame.midX - oscFloatingView.bounds.midX) <= 1, "Playback button lost center")
    precondition(oscToolbarView.views.count == expectedToolbarCount, "Toolbar count changed")
    precondition(oscPlayControlView.userInterfaceLayoutDirection == .leftToRight, "Transport order changed in RTL")
  }

  func verifyLayout() {
    let content = nativeWindow.contentView!
    var layouts = 0
    var styles: [TranslucentView.Style] = [.visualEffect]
    if #available(macOS 26, *) { styles.append(.liquidGlass) }
    // Floor widths repeatedly change while updateFloatingOSCScale returns early
    // at the same 0.8 value. Both shrinking and expanding paths are exercised.
    let floor = minimumWindowSize.width
    let widths: [CGFloat] = [900, 840, 750, 675, 600, 540, 480, 450, 420, 410, floor + 10, floor + 5, floor + 2, floor, floor + 2, floor + 5, floor + 10, 420, 450, 540, 675, 840, 900]
    for (style, compact) in styles.flatMap({ style in [false, true].map { (style, $0) } }) {
      oscFloatingView.setStyle(style)
      for direction: NSUserInterfaceLayoutDirection in [.leftToRight, .rightToLeft] {
        content.userInterfaceLayoutDirection = direction
        oscFloatingView.userInterfaceLayoutDirection = direction
        oscFloatingView.oscTopView.userInterfaceLayoutDirection = direction
        for _ in 0..<5 {
          for width in widths {
            nativeWindow.setFrame(NSRect(x: 100, y: 100, width: width, height: max(minimumWindowSize.height, width * 9 / 16)), display: false)
            let scale = FloatingOSCScale.factor(for: content.bounds.size)
            updateFloatingOSCScale(scale: scale)
            oscFloatingView.applyScale(scale, compact: compact)
            invalidateFloatingOSCLayout()
            content.layoutSubtreeIfNeeded()
            assertControlGeometry()
            let nominal = FloatingOSCMetrics.panelSize(scale: scale, compact: compact, sliderHeight: playSlider.frame.height)
            precondition(abs(oscFloatingView.frame.height - nominal.height) <= 1, "Preview height diverged from native OSC: \(oscFloatingView.frame.height) vs \(nominal.height)")
            let expectedWidth = nominal.width
            precondition(abs(oscFloatingView.frame.width - expectedWidth) <= 1, "Panel nominal/minimum width changed")
            layouts += 1
          }
        }
      }
    }
    print("PASS: \(layouts) production anchored/control layouts remain contained and centered across material, RTL and scale-floor width cycles")

    // Each proposal is checked immediately, with no event-loop settling. At the
    // minimum these calls never change actual bounds or emit DidResize.
    var proposals = 0
    for actualWidth: CGFloat in [floor, floor + 2] {
      nativeWindow.setFrame(NSRect(x: 100, y: 100, width: actualWidth, height: minimumWindowSize.height), display: false)
      updateFloatingOSCScale(scale: 0.8)
      oscFloatingView.applyScale(0.8)
      invalidateFloatingOSCLayout()
      content.layoutSubtreeIfNeeded()
      let unchangedFrame = nativeWindow.frame
      for style in styles {
        oscFloatingView.setStyle(style)
        for direction: NSUserInterfaceLayoutDirection in [.leftToRight, .rightToLeft] {
          content.userInterfaceLayoutDirection = direction
          oscFloatingView.userInterfaceLayoutDirection = direction
          oscFloatingView.oscTopView.userInterfaceLayoutDirection = direction
          for labelState in 0..<4 {
            oscSpeedLabelLeft.stringValue = labelState == 0 ? "0.5×" : "−2×"
            oscSpeedLabelRight.stringValue = labelState == 1 ? "2×" : ""
            oscSpeedLabelLeft.isHidden = labelState == 2
            oscSpeedLabelRight.isHidden = labelState == 3
            for proposedWidth: CGFloat in [floor - 1, floor - 10, floor - 40, floor - 80, 285, 250, 200, 100, 1, floor - 1] {
              _ = windowWillResize(nativeWindow, to: NSSize(width: proposedWidth, height: 150))
              precondition(nativeWindow.frame == unchangedFrame, "Proposed tick changed actual frame")
              assertControlGeometry()
              let toolbarRect = oscFloatingView.convert(oscToolbarView.bounds, from: oscToolbarView)
              precondition(oscFloatingView.bounds.contains(toolbarRect), "Toolbar group escaped on unchanged-bounds tick")
              proposals += 1
            }
          }
        }
      }
    }
    print("PASS: \(proposals) actual proposed-size callbacks preserve immediate group/button containment and centered playback at unchanged minimum/minimum-plus-2pt bounds across labels, RTL and materials")

    var toolbarLayouts = 0
    for count in 0...5 {
      rebuildToolbar(buttonCount: count)
      for size in [NSSize(width: 400, height: 225), NSSize(width: 900, height: 500),
                   NSSize(width: 900, height: 1600), NSSize(width: 1600, height: 225)] {
        for direction: NSUserInterfaceLayoutDirection in [.leftToRight, .rightToLeft] {
          content.userInterfaceLayoutDirection = direction
          oscFloatingView.userInterfaceLayoutDirection = direction
          oscFloatingView.oscTopView.userInterfaceLayoutDirection = direction
          nativeWindow.setFrame(NSRect(origin: NSPoint(x: 100, y: 100), size: size), display: false)
          let scale = FloatingOSCScale.factor(for: content.bounds.size)
          updateFloatingOSCScale(scale: scale)
          oscFloatingView.applyScale(scale)
          content.layoutSubtreeIfNeeded()
          assertControlGeometry(expectedToolbarCount: count)
          let volume = oscFloatingView.convert(oscVolumeView.bounds, from: oscVolumeView)
          let playback = oscFloatingView.convert(oscPlayControlView.bounds, from: oscPlayControlView)
          let toolbar = oscFloatingView.convert(oscToolbarView.bounds, from: oscToolbarView)
          precondition(!volume.intersects(playback) && !toolbar.intersects(playback), "OSC groups overlap")
          precondition(oscPlayControlView.visibilityPriority(for: oscSpeedLabelLeftContainer) == .mustHold &&
                       oscPlayControlView.visibilityPriority(for: oscSpeedLabelRightContainer) == .mustHold,
                       "Floating speed labels detached")
          precondition(abs(oscFloatingView.frame.width - 460 * scale) <= 1, "Floating OSC shortened")
          toolbarLayouts += 1
        }
      }
    }
    rebuildToolbar(buttonCount: 4)
    print("PASS: \(toolbarLayouts) minimum, portrait and short-wide layouts keep all controls for every supported toolbar count")

    // Removing the normal floating row must deactivate its fragment dimensions
    // before the same controls are installed in a docked stack.
    floatingOSCControlsView?.detachControls()
    floatingOSCControlsView = nil
    oscPosition = .bottom
    applyFloatingOSCControlScale()
    let dock = NSStackView(views: [oscVolumeView, oscPlayControlView, oscToolbarView])
    dock.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(dock)
    dock.leadingAnchor.constraint(equalTo: content.leadingAnchor).isActive = true
    dock.bottomAnchor.constraint(equalTo: content.bottomAnchor).isActive = true
    content.layoutSubtreeIfNeeded()
    precondition(oscToolbarView.distribution == .gravityAreas)
    precondition(oscPlayControlView.distribution == .gravityAreas)
    precondition(oscPlayControlMiddleView.distribution == .gravityAreas)
    precondition(!oscToolbarView.constraints.contains { $0.firstAttribute == .width && $0.secondItem == nil && $0.isActive }, "Floating toolbar dimension leaked into docked layout")
    precondition(!oscPlayControlView.constraints.contains { $0.firstAttribute == .width && $0.secondItem == nil && $0.isActive }, "Floating playback dimension leaked into docked layout")
    [oscVolumeView!, oscPlayControlView!, oscToolbarView!].forEach { $0.removeFromSuperview() }
    dock.removeFromSuperview()
    oscPosition = .floating
    installFloatingGroups()
    oscFloatingView.applyScale(0.8)
    invalidateFloatingOSCLayout()
    content.layoutSubtreeIfNeeded()
    assertControlGeometry()
    precondition(oscToolbarView.distribution == .fill)
    print("PASS: native floating row detaches cleanly, restores shared docked gravity dimensions, and re-enters compact floating layout")
  }
}
NativeScaleHarness().verifyLayout()
