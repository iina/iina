//
//  SidebarController.swift
//  iina
//
//  Created by Hechen Li on 2026-06-02.
//  Copyright © 2026 lhc. All rights reserved.
//

import Cocoa

fileprivate let SettingsWidth: CGFloat = 360
fileprivate let PlaylistMinWidth: CGFloat = 240
fileprivate let PlaylistMaxWidth: CGFloat = 800
fileprivate let SideBarAnimationDuration = 0.24

/// View controllers that can be embedded in a sidebar implement this.
protocol SidebarViewController {
  var downShift: CGFloat { get set }
}

/// Owns the two side panels (left/right), the view controllers that can be embedded in them, and
/// all animation, hit-testing, and resize logic. `MainWindowController` delegates mouse events
/// through `handleMouseDown(_:)` / `handleMouseDragged(_:)` / `handleMouseUp(_:)`.
class SidebarController: NSObject {
  /// Side of the window where a sidebar is attached.
  enum Side {
    case leading, trailing
  }

  /// What's currently embedded in a sidebar panel.
  enum ViewType: CaseIterable {
    case hidden
    case settings
    case playlist
    case plugins

    var prefKey: Preference.Key? {
      switch self {
      case .settings: .sidebarSettingsDisplayAtLeading
      case .playlist: .sidebarPlaylistDisplayAtLeading
      case .plugins: .sidebarPluginsDisplayAtLeading
      case .hidden: nil
      }
    }

    var width: CGFloat {
      switch self {
      case .settings, .plugins:
        return SettingsWidth
      case .playlist:
        return CGFloat(Preference.integer(for: .playlistWidth)).clamped(to: PlaylistMinWidth...PlaylistMaxWidth)
      case .hidden:
        return 0
      }
    }
  }

  /// Holds the view, layout constraints, and animation state for one side's sidebar.
  /// The `edgeConstraint` pins the sidebar to its window edge: for a right-side panel it pins
  /// the right edge, for a left-side panel it pins the left edge. The constant is `-width` when
  /// hidden (slid off-screen) and a small positive margin (`visibleEdgeMargin` or `0`) when shown.
  class Panel {
    let side: Side
    let view: SideBarView
    var widthConstraint: NSLayoutConstraint!
    var edgeConstraint: NSLayoutConstraint!
    var status: ViewType = .hidden {
      didSet { NotificationCenter.default.post(name: .iinaSidebarStatusChanged, object: nil) }
    }
    var animationState: MainWindowController.UIAnimationState = .hidden

    init(side: Side, view: SideBarView) {
      self.side = side
      self.view = view
    }

    var visibleEdgeMargin: CGFloat {
      0
    }
  }

  unowned let mainWindow: MainWindowController

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow
    super.init()

    ViewType.allCases.compactMap { $0.prefKey }.forEach {
      UserDefaults.standard.addObserver(self, forKeyPath: $0.rawValue, options: .new, context: nil)
    }
  }

  lazy var leadingSidebar: Panel = Panel(side: .leading, view: SideBarView(mainWindow: mainWindow))
  lazy var trailingSidebar: Panel = Panel(side: .trailing, view: SideBarView(mainWindow: mainWindow))
  var sideBars: [Panel] { [leadingSidebar, trailingSidebar] }

  /// Set while the user is dragging the playlist resize handle. Drives cursor change.
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
  lazy var subPopoverView = playlistView.subPopover?.contentViewController?.view

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
      if #available(macOS 26.0, *) {
        panel.view.setStyle(.liquidGlass)
      }
    }
  }

  // MARK: - Queries

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath else { return }
    ViewType.allCases.forEach { viweType in
      if viweType.prefKey?.rawValue == keyPath, isShowing(viweType) {
        hideAllSideBars(animate: false) {
          switch viweType {
          case .settings: self.showSettings()
          case .playlist: self.showPlaylist()
          case .plugins: self.showPlugin(tab: nil)
          default: break
          }
        }
      }
    }
  }

  func sideBar(for side: Side) -> Panel {
    side == .leading ? leadingSidebar : trailingSidebar
  }

  func isShowing(_ type: ViewType) -> Bool {
    sideBars.contains { $0.status == type }
  }

  var isAnyVisible: Bool {
    sideBars.contains { $0.status != .hidden }
  }

  /// Views that should swallow mouse events instead of letting them reach the video area.
  var mouseActionDisabledViews: [NSView?] {
    [trailingSidebar.view, leadingSidebar.view, subPopoverView]
  }

  func isEventCoveringVisibleSidebar(_ event: NSEvent) -> Bool {
    sideBars.contains { panel in
      !panel.view.isHidden && event.inAnyOf([panel.view])
    } || event.inAnyOf([subPopoverView])
  }

  private func side(for type: ViewType) -> Side {
    switch type {
    case .playlist:
      return Preference.bool(for: .sidebarPlaylistDisplayAtLeading) ? .leading : .trailing
    case .settings:
      return Preference.bool(for: .sidebarSettingsDisplayAtLeading) ? .leading : .trailing
    case .plugins:
      return Preference.bool(for: .sidebarPluginsDisplayAtLeading) ? .leading : .trailing
    default:
      return .trailing
    }
  }

  // MARK: - Mouse routing

  /// Returns true if the event was consumed by sidebar logic (caller should NOT call `super`).
  func handleMouseDown(_ event: NSEvent, at location: NSPoint) -> Bool {
    if let panel = sideBars.first(where: {
      $0.status == .playlist && NSPointInRect(location, playlistDraggingRect(for: $0.side))
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
    let x = event.locationInWindow.x
    let newWidth = (visuallyOnLeft(side) ? x : mainWindow.window!.frame.width - x) - 2
    let maxWidth = min(sidebarMaxWidth, PlaylistMaxWidth)
    let clamped = newWidth.clamped(to: PlaylistMinWidth...maxWidth)
    let panel = sideBar(for: side)
    panel.widthConstraint.constant = clamped
    // Keep the title text container flush against the (resizing) sidebar's inner edge — this also
    // triggers Titlebar.layout(), which refreshes the fade mask off the new sidebar frame.
    setTitlebarConstraint(
      for: side,
      titlebarConstantWhenShown(width: clamped, margin: panel.visibleEdgeMargin, side: side)
    )
    return true
  }

  /// Handles mouseUp for sidebar concerns (finishing a resize, or click-outside-to-dismiss).
  /// Returns true if the event was consumed.
  func handleMouseUp(_ event: NSEvent) -> Bool {
    if let side = resizingSidebarSide {
      resizingSidebarSide = nil
      Preference.set(Int(sideBar(for: side).widthConstraint.constant), for: .playlistWidth)
      return true
    }
    let isSingleClick = event.clickCount <= 1 && mainWindow.videoView.lastEventId == event.eventNumber
    if isSingleClick && isAnyVisible && Preference.bool(for: .edgeToEdgeVideo) {
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
  func playlistDraggingRect(for side: Side) -> NSRect {
    let sf = sideBar(for: side).view.frame
    let originX = visuallyOnLeft(side) ? sf.maxX : sf.minX - 4
    return NSRect(x: originX, y: sf.minY, width: 4, height: sf.height)
  }

  private var sidebarMaxWidth: CGFloat {
    guard let window = mainWindow.window else { return PlaylistMaxWidth }
    return max(window.frame.width * 0.8, PlaylistMinWidth)
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

  private func setTitlebarConstraint(for side: Side, _ constant: CGFloat) {
    if side == .leading {
      mainWindow.titleBarView.setLeadingConstraint(constant)
      mainWindow.oscBottomView.setLeadingConstraint(constant)
    } else {
      mainWindow.titleBarView.setTrailingConstraint(constant)
      mainWindow.oscBottomView.setTrailingConstraint(constant)
    }
  }

  /// Show the given sidebar on its configured side.
  ///
  /// Normally the sidebar is revealed by sliding it into view. However if the macOS [System Settings](https://support.apple.com/guide/mac-help/change-system-settings-mh15217/mac)
  /// [reduce motion](https://support.apple.com/guide/mac-help/stop-or-reduce-onscreen-motion-mchlc03f57a1/mac)
  /// setting is enabled then instead the sidebar will fade in. If the user enables the IINA
  /// `Disable animations` setting then the duration of the animation will be set to zero making the
  /// sidebar appear instantly.
  private func showSideBar(viewController: SidebarViewController, type: ViewType) {
    guard !mainWindow.isInInteractiveMode else { return }
    guard let view = (viewController as? NSViewController)?.view else {
      Logger.fatal("viewController is not a NSViewController")
    }
    let panel = sideBar(for: side(for: type))
    let width = type.width.clamped(to: 0...sidebarMaxWidth)
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
    panel.view.setContent(view)
    view.padding(.all)
    var viewController = viewController
    viewController.downShift = if #available(macOS 26.0, *), panel.view.style == .liquidGlass {
      panel.side == .leading ? 22 : 0
    } else {
      mainWindow.titleBarView.frame.height
    }

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
      panel.status = type
      self.mainWindow.window?.resetCursorRects()
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
    panel.animationState = .willHide

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
      panel.status = .hidden
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
                             isSameTab: () -> Bool,
                             switchTab: () -> Void,
                             force: Bool,
                             hideIfAlreadyShown: Bool) {
    let targetSide = side(for: type)
    let targetPanel = sideBar(for: targetSide)

    if !force, targetPanel.animationState == .willShow || targetPanel.animationState == .willHide {
      return  // don't interrupt in-flight animation on the target side
    }

    // If this type is already visible (possibly on the other side after a config change), treat
    // a same-tab request as toggle-off and a different-tab request as a tab switch in place.
    if let visiblePanel = sideBars.first(where: { $0.status == type }) {
      if isSameTab() {
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
      // Target side currently shows a different type — replace it.
      hideSideBar(side: targetSide) {
        self.showSideBar(viewController: viewController, type: type)
      }
    }
  }

  func showSettings(tab: QuickSettingViewController.TabViewType? = nil, force: Bool = false, hideIfAlreadyShown: Bool = true) {
    let view = quickSettingView
    toggleSideBar(
      type: .settings,
      viewController: view,
      isSameTab: { tab == nil || view.currentTab == tab },
      switchTab: { if let tab = tab { view.pleaseSwitchToTab(tab) } },
      force: force,
      hideIfAlreadyShown: hideIfAlreadyShown
    )
  }

  func showPlaylist(tab: PlaylistViewController.TabViewType? = nil, force: Bool = false, hideIfAlreadyShown: Bool = true) {
    let view = playlistView
    toggleSideBar(
      type: .playlist,
      viewController: view,
      isSameTab: { tab == nil || view.currentTab == tab },
      switchTab: { if let tab = tab { view.pleaseSwitchToTab(tab) } },
      force: force,
      hideIfAlreadyShown: hideIfAlreadyShown
    )
  }

  func showPlugin(tab: String?, force: Bool = false, hideIfAlreadyShown: Bool = true) {
    let view = pluginView
    toggleSideBar(
      type: .plugins,
      viewController: view,
      isSameTab: { tab == nil || view.currentPluginID == tab },
      switchTab: { if let tab = tab { view.pleaseSwitchToTab(tab) } },
      force: force,
      hideIfAlreadyShown: hideIfAlreadyShown
    )
  }
}
