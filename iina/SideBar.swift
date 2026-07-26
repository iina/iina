//
//  Sidebar.swift
//  iina
//
//  Created by Hechen Li on 2026-05-27.
//  Copyright © 2026 lhc. All rights reserved.
//

class SideBarContainer: TranslucentView {
  weak var mainWindow: MainWindowController!
  private let prefObserver = Preference.Observer()
  private let isLeading: Bool
  var leadingBorder: NSBox!

  init(mainWindow: MainWindowController, isLeading: Bool) {
    self.mainWindow = mainWindow
    self.isLeading = isLeading

    super.init(liquidGlassCornerRadius: 12, vevCornerRadius: 0, padding: (0, 0))

    LayoutValue.panelCornerRadius.use { [weak self] value in
      self?.setCornerRadius(liquidGlass: value, vev: 0)
    }

    // only draw leading border when docked
    prefObserver.addAll(.dockedControlBarAndTitlebar, .edgeToEdgeVideo) { [unowned self] _ in
      leadingBorder?.isHidden = !Preference.isDocked
      setShadow()
    }
  }

  override func setStyle(_ newStyle: TranslucentView.Style, force: Bool = false) {
    super.setStyle(newStyle, force: force)

    if let container = container as? NSVisualEffectView {
      leadingBorder = NSBox()
      leadingBorder.translatesAutoresizingMaskIntoConstraints = false
      leadingBorder.boxType = .separator
      container.addSubview(leadingBorder)
      leadingBorder.padding(.vertical, isLeading ? .trailing : .leading).size(width: 1)
      leadingBorder.isHidden = !Preference.isDocked
    }
    setShadow()
  }

  func setShadow() {
    let showShadow = style == .visualEffect && !Preference.isDocked
    if showShadow {
      let shadow = NSShadow()
      shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
      shadow.shadowBlurRadius = 6
      self.shadow = shadow
    } else {
      self.shadow = nil
    }
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}


class SidebarViewController: NSViewController {
  unowned let player: PlayerCore
  unowned let mainWindow: MainWindowController
  let prefObserver = Preference.Observer()

  let iconConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
  let compactIconConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)

  var downShift: CGFloat = 0 {
    didSet {
      topConstraint.constant = downShift
    }
  }

  var sidebarType: SidebarController.ViewType { fatalError() }
  var leadingPrefKey: Preference.Key { fatalError() }
  var widthRange: ClosedRange<CGFloat> { 300...500 }
  var width: CGFloat {
    let key: Preference.Key = isLeading ? .leadingSidebarWidth : .trailingSidebarWidth
    return CGFloat(Preference.integer(for: key)).clamped(to: widthRange)
  }

  var defaultTab: TabType { fatalError() }
  var allTabs: [TabType] { fatalError() }
  var useTabView: Bool { true }
  var isLeading: Bool { Preference.bool(for: leadingPrefKey) }
  var isCompact: Bool { Preference.bool(for: .compactUI) }

  var tabPanes: [NSView] = []

  var pendingSwitchRequest: TabType?
  lazy var currentTab: TabType = defaultTab

  var tabButtonsStackView: NSStackView!
  var tabButtonsSegmentControl: NSSegmentedControl!
  var tabButtonsLeadingConstraint: NSLayoutConstraint!
  var tabButtonsTrailingConstraint: NSLayoutConstraint!
  var tabButtonsHeightConstraint: NSLayoutConstraint!
  var topConstraint: NSLayoutConstraint!

  var tabViewController: SidebarTabViewController!
  var closeSidebarBtn: NSButton!
  var closeSidebarBtnSizeConstraint: NSLayoutConstraint!

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow
    self.player = mainWindow.player

    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    self.view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    self.tabButtonsStackView = NSStackView()
    tabButtonsStackView.translatesAutoresizingMaskIntoConstraints = false
    tabButtonsStackView.orientation = .horizontal
    view.addSubview(tabButtonsStackView)
    topConstraint = tabButtonsStackView.topAnchor.constraint(equalTo: view.topAnchor)
    topConstraint.isActive = true
    tabButtonsLeadingConstraint = tabButtonsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
    tabButtonsLeadingConstraint.isActive = true
    tabButtonsTrailingConstraint = view.trailingAnchor.constraint(equalTo: tabButtonsStackView.trailingAnchor)
    tabButtonsTrailingConstraint.isActive = true
    tabButtonsHeightConstraint = tabButtonsStackView.heightAnchor.constraint(equalToConstant: 64)
    tabButtonsHeightConstraint.isActive = true

    if useTabView {
      self.tabViewController = SidebarTabViewController()
      view.addSubview(tabViewController.view)

      tabViewController.view.padding(.bottom, .horizontal)
        .spacing(.top(1), to: tabButtonsStackView)

      tabViewController.tabView.padding(.all)
      tabViewController.tabView.wantsLayer = true
    }

    self.tabButtonsSegmentControl = NSSegmentedControl()
    tabButtonsSegmentControl.target = self
    tabButtonsSegmentControl.action = #selector(tabBtnSegmentControlAction_(_:))

    // close button
    self.closeSidebarBtn = NSButton(
      image: .sf("sidebar.squares.leading")!,
      target: self, action: #selector(dismissSidebar)
    )
    closeSidebarBtn.widthAnchor.constraint(equalTo: closeSidebarBtn.heightAnchor).isActive = true
    closeSidebarBtnSizeConstraint = closeSidebarBtn.widthAnchor.constraint(equalToConstant: 28)
    closeSidebarBtnSizeConstraint.isActive = true
    if #available(macOS 26.0, *) {
      if #available(macOS 27.0, *) {
        closeSidebarBtn.bezelStyle = .glass
        closeSidebarBtn.borderShape = .circle
      } else {
        closeSidebarBtn.bezelStyle = .circular
      }
    } else {
      closeSidebarBtn.bezelStyle = .accessoryBar
      closeSidebarBtn.controlSize = .large
    }

    setupTabs()

    // observer
    prefObserver.addAll(.compactUI, leadingPrefKey, runNow: true) {
      [unowned self] key in
      updateTabButtonSize()
      if key == leadingPrefKey {
        updateTabButtonLayout()
        updateTabActiveStatus()
      }
    }

    if useTabView && defaultTab.tag == 0 {
      // if the default tab is 0, it is already loaded and transition() was not called initially.
      // set previousIndex manually, so animation will be triggered on next tab switch.
      tabViewController.previousIndex = 0
    }
    // handle pending switch tab request
    if pendingSwitchRequest != nil {
      switchToTab(pendingSwitchRequest!)
      pendingSwitchRequest = nil
    } else {
      // tabViewController can be nil
      tabViewController?.selectedTabViewItemIndex = defaultTab.tag
    }
  }

  func setupTabs() {
    guard useTabView else {
      fatalError("must override setupTabs if useTabView is false")
    }

    func makeTabButton(_ title: String, image: NSImage?, tag: Int) -> NSButton {
      let item = TabButton(title: title,
                           target: self, action: #selector(tabBtnAction))
      item.bezelStyle = .smallSquare
      item.isBordered = false
      if let image {
        image.size = .init(width: 26, height: 18)
        item.image = image
        item.imageScaling = .scaleProportionallyUpOrDown
        item.imagePosition = .imageAbove
      }
      item.font = .systemFont(ofSize: 11, weight: .regular)
      item.tag = tag
      return item
    }

    tabButtonsSegmentControl.segmentCount = allTabs.count

    for tab in allTabs {
      // segment control
      tabButtonsSegmentControl.setTag(tab.tag, forSegment: tab.tag)
      // tab view
      let view = getTabView(for: tab)
      view.horizontalScroll = self.switchTabByScrolling(_:)
      let vc = NSViewController()
      vc.view = view
      let viewItem = NSTabViewItem(viewController: vc)
      tabViewController.addTabViewItem(viewItem)
    }
  }

  func getTabView(for tab: TabType) -> SidebarPane {
    fatalError()
  }

  // MARK: - Tab switching

  func findTab(named name: String) -> TabType? {
    allTabs.first { $0.name == name }
  }

  func switchToTab(_ tab: TabType) {
    guard useTabView else {
      fatalError("must override switchToTab if useTabView is false")
    }
    guard isViewLoaded else { return }
    currentTab = tab
    tabViewController.selectedTabViewItemIndex = tab.tag
    updateTabActiveStatus()
  }

  private func switchToTab(withTag: Int) {
    switchToTab(allTabs.first { $0.tag == withTag }!)
  }

  /** Switch tab (call from other objects) */
  func pleaseSwitchToTab(_ tab: TabType) {
    if isViewLoaded {
      switchToTab(tab)
    } else {
      // cache the request
      pendingSwitchRequest = tab
    }
  }

  private func switchTabByScrolling(_ isForward: Bool) {
    let tags = allTabs.map(\.tag)
    guard let max = tags.max(), let min = tags.min() else { return }
    if isForward {
      if currentTab.tag < max {
        switchToTab(withTag: currentTab.tag + 1)
      }
    } else {
      if currentTab.tag > min {
        switchToTab(withTag: currentTab.tag - 1)
      }
    }
  }

  func updateTabActiveStatus() {
    let currentTag = currentTab.tag
    for tab in allTabs {
      // don't show label if isLeading
      let isSelected = tab.tag == currentTag && !isLeading
      let label = NSLocalizedString("sidebar.\(tab.name)", comment: tab.name)
      tabButtonsSegmentControl.setLabel(isSelected ? label : "", forSegment: tab.tag)
    }
    tabButtonsSegmentControl.selectedSegment = currentTag
  }

  func updateTabButtonSize() {
    // on macOS 26, window corner radius will be larger with a regular toolbar.
    // should use the normal (non-compact) height if the sidebar is on the leading side.
    let largeLeadingHeight = if #available(macOS 26.0, *) { isLeading } else { false }
    let height: CGFloat = (isCompact && !largeLeadingHeight) ? 48 : 52
    tabButtonsHeightConstraint.constant = height

    if #available(macOS 26.0, *), !isCompact {
      tabButtonsSegmentControl.controlSize = .extraLarge
    } else {
      tabButtonsSegmentControl.controlSize = .large
    }

    let config = isCompact ? compactIconConfig : iconConfig
    for tab in allTabs {
      let image = tab.image.withSymbolConfiguration(config) ?? tab.image
      tabButtonsSegmentControl.setImage(image, forSegment: tab.tag)
    }

    closeSidebarBtnSizeConstraint.constant =  isCompact ? 28 : 36
  }

  func updateTabButtonLayout() {
    tabButtonsStackView.arrangedSubviews.forEach {
      tabButtonsStackView.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    if isLeading {
      closeSidebarBtn.image = .sf("chevron.backward")
      tabButtonsLeadingConstraint.constant = 96
      tabButtonsTrailingConstraint.constant = 10
      tabButtonsStackView.distribution = .equalSpacing
      tabButtonsStackView.addArrangedSubview(tabButtonsSegmentControl)
      tabButtonsStackView.addArrangedSubview(closeSidebarBtn)
    } else {
      closeSidebarBtn.image = .sf("chevron.forward")
      tabButtonsLeadingConstraint.constant = 10
      tabButtonsTrailingConstraint.constant = 10
      tabButtonsStackView.distribution = .equalSpacing
      tabButtonsStackView.addArrangedSubview(closeSidebarBtn)
      tabButtonsStackView.addArrangedSubview(tabButtonsSegmentControl)
    }
  }

  // MARK: - Actions

  @objc func dismissSidebar(_ sender: AnyObject) {
    mainWindow.sidebars.hide(sidebarType)
  }

  @objc private func tabBtnAction(_ sender: NSButton) {
    switchToTab(withTag: sender.tag)
  }

  func tabBtnSegmentControlAction(_ sender: NSSegmentedControl) {
    switchToTab(withTag: sender.selectedTag())
  }

  @objc private func tabBtnSegmentControlAction_(_ sender: NSSegmentedControl) {
    tabBtnSegmentControlAction(sender)
  }
}


extension SidebarViewController {
  struct TabType: Equatable {
    var tag: Int
    var name: String
    var image: NSImage

    init(_ value: Int, _ name: String, _ image: NSImage) {
      self.tag = value
      self.name = name
      self.image = image
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.tag == rhs.tag
    }
  }

  class TabButton: NSButton {
    class Cell: NSButtonCell {
      override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        if state == .on {
          let frame = NSInsetRect(cellFrame, 0, -4)
          let rect = NSBezierPath(roundedRect: frame, xRadius: 16, yRadius: 16)

          if let gradient = NSGradient(starting: .gray.withAlphaComponent(0.1), ending: .gray.withAlphaComponent(0.2)) {
            gradient.draw(in: rect, angle: 90)
          }

          NSColor.sidebarTabBtnBorder.setStroke()
          rect.lineWidth = 1
          rect.stroke()
        }

        super.draw(withFrame: cellFrame, in: controlView)
      }

      override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        (controlView as? NSButton)?.contentTintColor = state == .on ?
          .sidebarTabTintActive : .sidebarTabTint
        super.drawInterior(withFrame: cellFrame, in: controlView)
      }
    }

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      self.cell = Cell()
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }
}
