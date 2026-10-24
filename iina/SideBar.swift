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
  private let sectionScroll = SidebarSectionScrollNavigation()

  var downShift: CGFloat {
    get { topConstraint.constant }
    set { setTopInset(newValue, animated: false) }
  }

  func setTopInset(_ height: CGFloat, animated: Bool) {
    if animated {
      topConstraint.animator().constant = height
    } else {
      topConstraint.constant = height
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
    self.view = SidebarSectionView()
    view.translatesAutoresizingMaskIntoConstraints = false
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    if useTabView {
      (view as? SidebarSectionView)?.horizontalScroll = { [weak self] event in
        self?.handleSectionScroll(event) ?? false
      }
    }

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

      let bottomBorder = UIHelper.shared.separator()
      view.addSubview(bottomBorder)
      bottomBorder.padding(.horizontal).spacing(.bottom, to: tabViewController.view)
    }

    self.tabButtonsSegmentControl = makeTabSegmentControl()
    tabButtonsSegmentControl.target = self
    tabButtonsSegmentControl.action = #selector(tabBtnSegmentControlAction_(_:))
    if useTabView {
      (tabButtonsSegmentControl as? SidebarTabSelectorControl)?.horizontalScroll = { [weak self] event in
        self?.handleSectionScroll(event) ?? false
      }
    }

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
    // Activate cross-view constraints only after the observer inserts the selector into the header.
    if useTabView {
      tabButtonsSegmentControl.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor,
        constant: -76).isActive = true
    }
  }

  func makeTabSegmentControl() -> NSSegmentedControl {
    SidebarTabSelectorControl(titles: allTabs.map { NSLocalizedString("sidebar.\($0.name)", comment: $0.name) })
  }

  func setupTabs() {
    guard useTabView else {
      fatalError("must override setupTabs if useTabView is false")
    }

    tabButtonsSegmentControl.segmentCount = allTabs.count

    for tab in allTabs {
      // segment control
      tabButtonsSegmentControl.setTag(tab.tag, forSegment: tab.tag)
      // tab view
      let view = getTabView(for: tab)
      view.horizontalScroll = { [weak self] event in self?.handleSectionScroll(event) ?? false }
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
    let tabs = allTabs
    guard let current = tabs.firstIndex(of: currentTab) else { return }
    let next = current + (isForward ? 1 : -1)
    if tabs.indices.contains(next) { switchToTab(tabs[next]) }
  }

  private func handleSectionScroll(_ event: NSEvent) -> Bool {
    // Aspect/crop strips keep their own horizontal scrolling, including at an edge.
    if let parent = view.superview {
      var hit = view.hitTest(parent.convert(event.locationInWindow, from: nil))
      while let child = hit, child !== view {
        if let scroll = child as? NSScrollView, !(scroll is SidebarSectionScrollView),
           let document = scroll.documentView, document.frame.width > scroll.contentView.bounds.width + 1 {
          return abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        }
        hit = child.superview
      }
    }
    switch sectionScroll.handle(event) {
    case .passThrough: return false
    case .consumed: return true
    case .navigate(let forward):
      switchTabByScrolling(forward)
      return true
    }
  }

  func updateTabActiveStatus() {
    let selector = tabButtonsSegmentControl as? SidebarTabSelectorControl
    selector?.showsSelectedTitle = true
    let currentTag = currentTab.tag
    for tab in allTabs {
      let isSelected = tab.tag == currentTag
      let label = NSLocalizedString("sidebar.\(tab.name)", comment: tab.name)
      tabButtonsSegmentControl.setLabel(isSelected ? label : "", forSegment: tab.tag)
    }
    tabButtonsSegmentControl.selectedSegment = currentTag
    selector?.updateSelection()
  }

  func updateTabButtonSize() {
    let height: CGFloat = isCompact ? 48 : 52
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
      tabButtonsLeadingConstraint.constant = 10
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

}


private final class SidebarSelectorOverlay: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@available(macOS 26.0, *)
private final class SidebarSelectorGlass: NSGlassEffectView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

class SidebarTabSelectorControl: NSSegmentedControl {
  var horizontalScroll: ((NSEvent) -> Bool)?

  override func scrollWheel(with event: NSEvent) {
    if horizontalScroll?(event) == true { return }
    super.scrollWheel(with: event)
  }

  var showsSelectedTitle = true {
    didSet {
      guard oldValue != showsSelectedTitle else { return }
      invalidateIntrinsicContentSize()
      displayedBounds = .null
      needsLayout = true
    }
  }
  private let titles: [String]
  private let foreground = SidebarSelectorOverlay()
  private let selection = SidebarSelectorOverlay()
  private let backgroundView: NSView
  private var icons: [NSImageView] = []
  private var labels: [NSTextField] = []
  private var segmentFrames: [NSRect] = []
  private var displayedSelection = -1
  private var displayedBounds = NSRect.zero

  private var capsuleHeight: CGFloat {
    if #available(macOS 26.0, *), controlSize == .extraLarge { return 36 }
    return 30
  }
  private var itemWidth: CGFloat { capsuleHeight - 2 }
  private let titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
  private var titleWidth: CGFloat {
    guard showsSelectedTitle else { return 0 }
    return ceil(labels.map { $0.cell?.cellSize.width ?? 0 }.max() ?? 0) + 7
  }

  init(titles: [String]) {
    self.titles = titles
    if #available(macOS 26.0, *) {
      let glass = SidebarSelectorGlass()
      if #available(macOS 27.0, *) { glass.effectIsInteractive = false }
      backgroundView = glass
    } else {
      let effect = NSVisualEffectView()
      effect.material = .headerView
      effect.blendingMode = .withinWindow
      effect.state = .active
      backgroundView = effect
    }
    super.init(frame: .zero)
    wantsLayer = true
    setContentCompressionResistancePriority(.init(1), for: .horizontal)
    backgroundView.wantsLayer = true
    backgroundView.setAccessibilityElement(false)
    addSubview(backgroundView)
    foreground.wantsLayer = true
    foreground.setAccessibilityElement(false)
    addSubview(foreground)
    selection.wantsLayer = true
    selection.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
    selection.setAccessibilityElement(false)
    foreground.addSubview(selection)
    for title in titles {
      let icon = NSImageView()
      icon.imageScaling = .scaleProportionallyDown
      icon.contentTintColor = .labelColor
      icon.setAccessibilityElement(false)
      foreground.addSubview(icon)
      icons.append(icon)
      let label = NSTextField(labelWithString: title)
      label.font = titleFont
      label.lineBreakMode = .byTruncatingTail
      label.setAccessibilityElement(false)
      label.wantsLayer = true
      label.alphaValue = 0
      foreground.addSubview(label)
      labels.append(label)
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize {
    NSSize(width: CGFloat(titles.count) * itemWidth + titleWidth + 8, height: capsuleHeight)
  }

  override var controlSize: NSControl.ControlSize {
    didSet {
      guard !icons.isEmpty else { return }
      invalidateIntrinsicContentSize()
      needsLayout = true
    }
  }

  override func setImage(_ image: NSImage?, forSegment segment: Int) {
    super.setImage(image, forSegment: segment)
    guard icons.indices.contains(segment) else { return }
    icons[segment].image = image
  }

  override func draw(_ dirtyRect: NSRect) {}

  override func layout() {
    super.layout()
    updateSelection(animated: false)
  }

  func updateSelection(animated: Bool = true) {
    guard !titles.isEmpty, icons.indices.contains(selectedSegment) else { return }
    let changed = displayedSelection != selectedSegment
    let canAnimate = animated && changed && displayedSelection >= 0 && window != nil &&
      !isHiddenOrHasHiddenAncestor
    let duration = canAnimate ? SidebarTabMotion.duration : 0
    // An unchanged layout pass must not cancel an in-flight selection movement.
    guard changed || displayedBounds != bounds || segmentFrames.isEmpty else { return }
    displayedSelection = selectedSegment
    displayedBounds = bounds
    let height = min(bounds.height, capsuleHeight)
    let outer = NSRect(x: 0, y: bounds.midY - height / 2, width: bounds.width, height: height)
    backgroundView.frame = outer
    backgroundView.layer?.cornerRadius = height / 2
    if #available(macOS 26.0, *), let glass = backgroundView as? NSGlassEffectView {
      glass.cornerRadius = height / 2
    }
    foreground.frame = outer
    let baseWidth = min(itemWidth, max(0, (bounds.width - 8) / CGFloat(titles.count)))
    let availableTitleWidth = max(0, bounds.width - 8 - CGFloat(titles.count) * baseWidth)
    let selectedTitleWidth = showsSelectedTitle ? min(availableTitleWidth,
      ceil(labels[selectedSegment].cell?.cellSize.width ?? 0) + 7) : 0
    let inactiveWidth = baseWidth + (showsSelectedTitle && titles.count > 1 ?
      (availableTitleWidth - selectedTitleWidth) / CGFloat(titles.count - 1) : 0)
    let rtl = userInterfaceLayoutDirection == .rightToLeft
    var x: CGFloat = 4
    segmentFrames = titles.indices.map { index in
      let width = index == selectedSegment ? baseWidth + selectedTitleWidth : inactiveWidth
      let frame = NSRect(x: rtl ? bounds.width - x - width : x, y: 4, width: width, height: max(0, height - 8))
      x += width
      setWidth(width, forSegment: index)
      setToolTip(titles[index], forSegment: index)
      return frame
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      context.timingFunction = SidebarTabMotion.timingFunction
      selection.layer?.cornerRadius = max(0, height - 8) / 2
      if duration > 0 { selection.animator().frame = segmentFrames[selectedSegment] }
      else { selection.frame = segmentFrames[selectedSegment] }
      for index in titles.indices {
        let frame = segmentFrames[index]
        let active = index == selectedSegment && showsSelectedTitle
        let iconX = active ? (rtl ? frame.maxX - baseWidth : frame.minX) : frame.midX - baseWidth / 2
        let iconFrame = NSRect(x: iconX + (baseWidth - 18) / 2, y: height / 2 - 9, width: 18, height: 18)
        let labelFrame = NSRect(x: rtl ? frame.minX + 4 : frame.minX + baseWidth,
                               y: height / 2 - 8, width: max(0, frame.width - baseWidth - 5), height: 17)
        if duration > 0 {
          icons[index].animator().frame = iconFrame
          labels[index].animator().frame = labelFrame
        } else {
          icons[index].frame = iconFrame
          labels[index].frame = labelFrame
        }
        labels[index].animator().alphaValue = active ? 1 : 0
      }
    }
  }

  override func mouseDown(with event: NSEvent) {
    guard isEnabled else { return }
    let point = convert(event.locationInWindow, from: nil)
    let local = foreground.convert(point, from: self)
    guard let index = segmentFrames.firstIndex(where: { $0.contains(local) }) else { return }
    selectedSegment = index
    sendAction(action, to: target)
  }
}
