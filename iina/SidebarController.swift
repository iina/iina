//
//  SidebarController.swift
//  iina
//
//  Created by Hechen Li on 2026-06-02.
//  Copyright © 2026 lhc. All rights reserved.
//

import Cocoa

fileprivate let SideBarAnimationDuration = 0.24


/// Owns the two side panels (left/right), the view controllers that can be embedded in them, and
/// all animation, hit-testing, and resize logic. `MainWindowController` delegates mouse events
/// through `handleMouseDown(_:)` / `handleMouseDragged(_:)` / `handleMouseUp(_:)`.
class SidebarController: NSObject {
  /// Side of the window where a sidebar is attached.
  enum Side {
    case leading, trailing
  }

  /// What's currently embedded in a sidebar panel.
  enum ViewType {
    case hidden
    case settings
    case playlist
    case plugins
  }

  /// Holds the view, layout constraints, and animation state for one side's sidebar.
  /// The `edgeConstraint` pins the sidebar to its window edge: for a right-side panel it pins
  /// the right edge, for a left-side panel it pins the left edge. The constant is `-width` when
  /// hidden (slid off-screen) and a small positive margin (`visibleEdgeMargin` or `0`) when shown.
  class Panel {
    let side: Side
    let view: SideBarContainer
    var widthConstraint: NSLayoutConstraint!
    var edgeConstraint: NSLayoutConstraint!
    var status: ViewType = .hidden
    var animationState: MainWindowController.UIAnimationState = .hidden {
      didSet {
        if animationState == .hidden || animationState == .shown {
          NotificationCenter.default.post(name: .iinaSidebarStatusChanged, object: nil)
        }
      }
    }

    init(side: Side, view: SideBarContainer) {
      self.side = side
      self.view = view
    }

    var visibleEdgeMargin: CGFloat {
      0
    }
  }

  unowned let mainWindow: MainWindowController
  let prefObserver = Preference.Observer()

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow
    super.init()

    // observe sidebar positions
    prefObserver.addAll(viewControllers.map { $0.leadingPrefKey }) { [unowned self] key in
      guard let vc = viewControllers.first(where: { $0.leadingPrefKey == key }) else { return }
      if isShowing(vc.sidebarType) {
        hideAllSideBars(animate: false) {
          self.show(sidebar: vc.sidebarType)
        }
      }
    }

    prefObserver.add(.useLiquidGlassSidebar, runNow: true) { [unowned self] _ in
      sideBars.forEach {
        $0.view.setStyle(Preference.liquidGlass(.sidebar) ? .liquidGlass : .visualEffect)
      }
    }
  }

  lazy var leadingSidebar: Panel = Panel(
    side: .leading,
    view: SideBarContainer(mainWindow: mainWindow, isLeading: true)
  )
  lazy var trailingSidebar: Panel = Panel(
    side: .trailing,
    view: SideBarContainer(mainWindow: mainWindow, isLeading: false)
  )
  var sideBars: [Panel] { [leadingSidebar, trailingSidebar] }

  /// Set while the user is dragging a sidebar's resize handle. Drives cursor change.
  var resizingSidebarSide: Side? {
    didSet {
      if resizingSidebarSide != nil {
        mainWindow.window?.disableCursorRects()
        NSCursor.resizeLeftRight.push()
      } else {
        NSCursor.pop()
        mainWindow.window?.resetCursorRects()
        mainWindow.window?.enableCursorRects()
      }
    }
  }

  // MARK: - Embedded view controllers

  lazy var quickSettingView = QuickSettingViewController(mainWindow: mainWindow)
  lazy var playlistView = PlaylistViewController(mainWindow: mainWindow)
  lazy var pluginView = PluginViewController(mainWindow: mainWindow)

  private func viewController(for viewType: ViewType) -> SidebarViewController? {
    switch viewType {
    case .settings: quickSettingView
    case .playlist: playlistView
    case .plugins: pluginView
    case .hidden: nil
    }
  }

  private var viewControllers: [SidebarViewController] {
    [quickSettingView, playlistView, pluginView]
  }

  // MARK: - Layout setup (called from windowDidLoad)

  func installSubviews(in contentView: NSView) {
    contentView.addSubview(trailingSidebar.view)
    contentView.addSubview(leadingSidebar.view)
    for panel in sideBars {
      panel.view.padding(.bottom(panel.visibleEdgeMargin), .top(panel.visibleEdgeMargin))
      panel.widthConstraint = panel.view.widthAnchor.constraint(equalToConstant: 60)
      panel.widthConstraint.isActive = true
      switch panel.side {
      case .leading:
        panel.edgeConstraint = panel.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: -60)
      case .trailing:
        panel.edgeConstraint = contentView.trailingAnchor.constraint(equalTo: panel.view.trailingAnchor, constant: -60)
      }
      panel.edgeConstraint.isActive = true
      panel.view.isHidden = true
      if Preference.liquidGlass(.sidebar) {
        panel.view.setStyle(.liquidGlass)
      }
    }
  }

  // MARK: - Queries

  func sideBar(for side: Side) -> Panel {
    side == .leading ? leadingSidebar : trailingSidebar
  }

  func isShowing(_ type: ViewType, tab: QuickSettingViewController.TabType? = nil) -> Bool {
    if let tab {
      sideBars.contains { viewController(for: $0.status)?.currentTab == tab }
    } else {
      // only return whether sidebar type is showing
      sideBars.contains { $0.status == type }
    }
  }

  var isAnyVisible: Bool {
    sideBars.contains { $0.status != .hidden }
  }

  /// Views that should swallow mouse events instead of letting them reach the video area.
  var mouseActionDisabledViews: [NSView?] {
    [trailingSidebar.view, leadingSidebar.view]
  }

  func isEventCoveringVisibleSidebar(_ event: NSEvent) -> Bool {
    sideBars.contains { panel in
      !panel.view.isHidden && event.inAnyOf([panel.view])
    }
  }

  private func side(for type: ViewType) -> Side {
    guard let vc = viewController(for: type) else { return .trailing }
    return vc.isLeading ? .leading : .trailing
  }

  // MARK: - Mouse routing

  /// Returns true if the event was consumed by sidebar logic (caller should NOT call `super`).
  func handleMouseDown(_ event: NSEvent, at location: NSPoint) -> Bool {
    if let panel = sideBars.first(where: {
      $0.status != .hidden && NSPointInRect(location, resizeHandleRect(for: $0.side))
    }) {
      resizingSidebarSide = panel.side
      return true
    } else if !isEventCoveringVisibleSidebar(event) && isAnyVisible {
      return true
    }
    return false
  }

  /// Returns true if the event was consumed (an in-progress sidebar resize).
  func handleMouseDragged(_ event: NSEvent) -> Bool {
    guard let side = resizingSidebarSide else { return false }
    let panel = sideBar(for: side)
    guard let range = viewController(for: panel.status)?.widthRange else { return false }
    let x = event.locationInWindow.x
    let newWidth = (visuallyOnLeft(side) ? x : mainWindow.window!.frame.width - x) - 2
    let maxWidth = max(range.lowerBound, min(sidebarMaxWidth, range.upperBound))
    let clamped = newWidth.clamped(to: range.lowerBound...maxWidth)
    panel.widthConstraint.constant = clamped
    // Keep the title text container flush against the (resizing) sidebar's inner edge — this also
    // triggers Titlebar.layout(), which refreshes the fade mask off the new sidebar frame.
    setTitlebarConstraint(
      for: side,
      titlebarConstantWhenShown(width: clamped, margin: panel.visibleEdgeMargin, side: side),
      animated: false
    )
    return true
  }

  /// Handles mouseUp for sidebar concerns (finishing a resize, or click-outside-to-dismiss).
  /// Returns true if the event was consumed.
  func handleMouseUp(_ event: NSEvent) -> Bool {
    if let side = resizingSidebarSide {
      resizingSidebarSide = nil
      let panel = sideBar(for: side)
      let key: Preference.Key = side == .leading ? .leadingSidebarWidth : .trailingSidebarWidth
      Preference.set(Int(panel.widthConstraint.constant), for: key)
      return true
    }
    let isSingleClick = event.clickCount <= 1 && mainWindow.videoView.lastEventId == event.eventNumber
    if isSingleClick && isAnyVisible && Preference.bool(for: .edgeToEdgeVideo) && !isEventCoveringVisibleSidebar(event) {
      hideAllSideBars()
      return true
    }
    return false
  }

  // MARK: - Geometry

  /// True when `side` ends up visually on the left after RTL mirroring is taken into account.
  private func visuallyOnLeft(_ side: Side) -> Bool {
    (side == .leading) != (mainWindow.videoView.userInterfaceLayoutDirection == .rightToLeft)
  }

  /// 4pt strip on the sidebar's inner edge (toward the video center) used as the resize handle.
  func resizeHandleRect(for side: Side) -> NSRect {
    let sf = sideBar(for: side).view.frame
    let originX = visuallyOnLeft(side) ? sf.maxX : sf.minX - 4
    return NSRect(x: originX, y: sf.minY, width: 4, height: sf.height)
  }

  private var sidebarMaxWidth: CGFloat {
    guard let window = mainWindow.window else { return .greatestFiniteMagnitude }
    return window.frame.width * 0.8
  }

  // MARK: - Show

  /// macOS reduce-motion is honored by fading; the IINA "Disable animations" pref short-circuits
  /// the animation duration to zero, but fade with zero duration is glitchy, so we slide instead.
  private var useFadeForSidebar: Bool {
    AccessibilityPreferences.motionReductionEnabled && !Preference.bool(for: PK.disableAnimations)
  }

  /// Constant for the titlebar edge constraint when this side's sidebar is fully shown — sits the
  /// title text container flush against the sidebar's inner edge.
  private func titlebarConstantWhenShown(width: CGFloat, margin: CGFloat, side: Side) -> CGFloat {
    width + margin
  }

  private func setTitlebarConstraint(for side: Side, _ constant: CGFloat, animated: Bool = true) {
    if side == .leading {
      mainWindow.titleBarView.setLeadingConstraint(constant, animated: animated)
      mainWindow.oscBottomView.setLeadingConstraint(constant, animated: animated)
    } else {
      mainWindow.titleBarView.setTrailingConstraint(constant, animated: animated)
      mainWindow.oscBottomView.setTrailingConstraint(constant, animated: animated)
    }
  }

  private func replaceSideBar(with viewController: SidebarViewController, type: ViewType, in panel: Panel) {
    panel.status = type
    panel.view.setContent(viewController.view)
    viewController.view.padding(.all)
    viewController.downShift = 0
    NotificationCenter.default.post(name: .iinaSidebarStatusChanged, object: nil)
  }

  /// Show the given sidebar on its configured side.
  ///
  /// Normally the sidebar is revealed by sliding it into view. However if the macOS [System Settings](https://support.apple.com/guide/mac-help/change-system-settings-mh15217/mac)
  /// [reduce motion](https://support.apple.com/guide/mac-help/stop-or-reduce-onscreen-motion-mchlc03f57a1/mac)
  /// setting is enabled then instead the sidebar will fade in. If the user enables the IINA
  /// `Disable animations` setting then the duration of the animation will be set to zero making the
  /// sidebar appear instantly.
  private func showSideBar(viewController: SidebarViewController, type: ViewType) {
    guard !mainWindow.interactiveMode.isActive else { return }
    let panel = sideBar(for: side(for: type))
    let width = viewController.width.clamped(to: 0...sidebarMaxWidth)
    let margin = panel.visibleEdgeMargin

    panel.animationState = .willShow
    panel.widthConstraint.constant = width
    // Position the sidebar before animation: fade-in starts at the visible position with
    // `isHidden=true`; slide-in starts off-screen with `isHidden=false`.
    if useFadeForSidebar {
      panel.edgeConstraint.constant = 0
    } else {
      panel.edgeConstraint.constant = -width
      panel.view.isHidden = false
    }
    panel.status = type
    panel.view.setContent(viewController.view)
    viewController.view.padding(.all)
    viewController.downShift = 0

    NSAnimationContext.runAnimationGroup({ context in
      context.duration = AccessibilityPreferences.adjustedDuration(SideBarAnimationDuration)
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      if useFadeForSidebar {
        panel.view.animator().isHidden = false
      } else {
        panel.edgeConstraint.animator().constant = margin
        setTitlebarConstraint(
          for: panel.side,
          titlebarConstantWhenShown(width: width, margin: margin, side: panel.side)
        )
      }
    }) {
      panel.animationState = .shown
      self.mainWindow.window?.resetCursorRects()
      self.mainWindow.setWindowToolbar()
    }
  }

  // MARK: - Hide

  /// Hide the sidebar on the given side. If neither showing nor about-to-show, the callback fires
  /// immediately.
  func hideSideBar(side: Side, animate: Bool = true, after: @escaping () -> Void = {}) {
    let panel = sideBar(for: side)
    guard panel.status != .hidden || panel.animationState == .willShow else {
      after()
      return
    }
    let currWidth = panel.widthConstraint.constant
    panel.status = .hidden
    panel.animationState = .willHide
    mainWindow.setWindowToolbar()

    NSAnimationContext.runAnimationGroup({ context in
      context.duration = animate ? AccessibilityPreferences.adjustedDuration(SideBarAnimationDuration) : 0
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      if useFadeForSidebar {
        panel.view.animator().alphaValue = 0
      } else {
        panel.edgeConstraint.animator().constant = -currWidth
        setTitlebarConstraint(for: panel.side, 0)
      }
    }) {
      // A new show may have started during the hide animation; only finalize if we still mean to hide.
      guard panel.animationState == .willHide else { return }
      panel.view.subviews.removeAll()
      panel.view.isHidden = true
      // When fading, the view stays in its visible position during the animation. Push it
      // off-screen now so AdditionalInfoView (anchored against the right sidebar) can align with
      // the window edge in full-screen.
      if self.useFadeForSidebar {
        panel.edgeConstraint.constant = -currWidth
        panel.view.alphaValue = 1
      }
      panel.animationState = .hidden
      self.mainWindow.window?.resetCursorRects()
      after()
    }
  }

  /// Hide every visible sidebar.
  func hideAllSideBars(animate: Bool = true, after: @escaping () -> Void = {}) {
    let visible = sideBars.filter { $0.status != .hidden }
    guard !visible.isEmpty else { after(); return }
    for (i, panel) in visible.enumerated() {
      hideSideBar(side: panel.side, animate: animate, after: i == visible.count - 1 ? after : {})
    }
  }

  /// Hide whichever side currently shows `type`. If not visible, `after` fires immediately.
  func hide(_ type: ViewType, animate: Bool = true, after: @escaping () -> Void = {}) {
    if let panel = sideBars.first(where: { $0.status == type }) {
      hideSideBar(side: panel.side, animate: animate, after: after)
    } else {
      after()
    }
  }

  // MARK: - High-level toggle

  /// Toggle/show a sidebar of the given `type` on its configured side.
  /// - If `type` is already visible somewhere, this either switches its tab or toggles it off.
  /// - Otherwise it shows on the configured side, displacing any other type currently there.
  private func toggleSideBar(type: ViewType,
                             viewController: SidebarViewController,
                             tab: SidebarViewController.TabType?,
                             force: Bool,
                             hideIfAlreadyShown: Bool) {
    let targetSide = side(for: type)
    let targetPanel = sideBar(for: targetSide)

    if !force, targetPanel.animationState == .willShow || targetPanel.animationState == .willHide {
      return  // don't interrupt in-flight animation on the target side
    }

    let switchTab = { if let tab = tab { viewController.pleaseSwitchToTab(tab) } }

    // If this type is already visible (possibly on the other side after a config change), treat
    // a same-tab request as toggle-off and a different-tab request as a tab switch in place.
    if let visiblePanel = sideBars.first(where: { $0.status == type }) {
      if tab == nil || viewController.currentTab == tab {
        if hideIfAlreadyShown { hideSideBar(side: visiblePanel.side) }
      } else {
        switchTab()
      }
      return
    }

    switchTab()
    if targetPanel.status == .hidden {
      showSideBar(viewController: viewController, type: type)
    } else {
      replaceSideBar(with: viewController, type: type, in: targetPanel)
    }
  }

  func show(sidebar: ViewType? = nil, tab: String? = nil, force: Bool = false, hideIfAlreadyShown: Bool = true) {
    let view: SidebarViewController = if let sidebar {
      switch sidebar {
      case .settings: quickSettingView
      case .playlist: playlistView
      case .plugins: pluginView
      default: fatalError("sidebar must be settings, playlist or plugin")
      }
    } else {
      if let tab {
        [quickSettingView, playlistView, pluginView].first { $0.findTab(named: tab) != nil }!
      } else {
        fatalError("sidebar or tab is required")
      }
    }
    let tabType = tab.flatMap(view.findTab(named:))

    let sidebar = sidebar ?? (view == quickSettingView ? .settings : view == playlistView ? .playlist : .plugins)

    toggleSideBar(type: sidebar, viewController: view, tab: tabType,
                  force: force, hideIfAlreadyShown: hideIfAlreadyShown)
  }
}
