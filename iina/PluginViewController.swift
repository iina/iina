//
//  PluginViewController.swift
//  iina
//
//  Created by Hechen Li on 11/11/24.
//  Copyright © 2024 lhc. All rights reserved.
//

fileprivate let ui = UIHelper.shared


extension SidebarViewController.TabType {
  static let pluginPlaceholder = SidebarViewController.TabType(
    0, NSLocalizedString("sidebar.plugins", comment: ""), .puzzlepieceExtensionFill)
}

class PluginViewController: SidebarViewController {
  override var sidebarType: SidebarController.ViewType {
    .plugins
  }
  override var leadingPrefKey: Preference.Key {
    .sidebarPluginsDisplayAtLeading
  }

  private lazy var allTabs_: [(id: String, name: String)] = getAllTabs()
  private var initialPluginIdentifier = Preference.string(for: .lastSelectedPlugin)
  private var windowSessionActive = false

  override var allTabs: [TabType] {
    [.pluginPlaceholder] + allTabs_.enumerated().map { (i, tuple) in
      TabType(i + 1, tuple.id, .puzzlepieceExtensionFill)
    }
  }
  private var firstAvailableTab: TabType { allTabs.first { $0.tag != 0 } ?? .pluginPlaceholder }
  override var defaultTab: TabType {
    allTabs.first { $0.tag != 0 && $0.name == initialPluginIdentifier } ?? firstAvailableTab
  }
  override var useTabView: Bool { false }

  private var pluginContentContainerView: NSView!
  private var placeholderView: NSView!

  private var pluginMenu = NSMenu()

  func beginWindowSession() {
    guard !windowSessionActive else { return }
    windowSessionActive = true
    // Snapshot at window opening, even if the sidebar is loaded much later.
    initialPluginIdentifier = Preference.string(for: .lastSelectedPlugin)
    allTabs_ = getAllTabs()
    currentTab = defaultTab
    if isViewLoaded { updatePluginTabs() }
  }

  func endWindowSession() {
    windowSessionActive = false
  }

  func selectPlugin(withIdentifier identifier: String) {
    _ = view
    guard let tab = allTabs.first(where: { $0.tag != 0 && $0.name == identifier }) else { return }
    switchToTab(tab)
    // Existing windows retain currentTab; only deliberate selection updates the shared preference.
    Preference.set(identifier, for: .lastSelectedPlugin)
  }

  private func getPluginIcon(isSmall: Bool) -> NSImage {
    let config = isSmall ? compactIconConfig : iconConfig
    return NSImage.sf("puzzlepiece.extension.fill", withConfiguration: config) ?? .puzzlepieceExtensionFill
  }

  override func makeTabSegmentControl() -> NSSegmentedControl {
    let selector = ScrollSelectionControl()
    selector.switchSelection = { [weak self] direction in
      self?.switchPlugin(direction)
    }
    return selector
  }

  override func setupTabs() {
    pluginMenu.minimumWidth = 200
    pluginMenu.delegate = self

    self.pluginContentContainerView = NSView()
    pluginContentContainerView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(pluginContentContainerView)

    pluginContentContainerView.padding(.bottom, .horizontal)
      .spacing(.top(1), to: tabButtonsStackView)

    self.placeholderView = NSView()
    placeholderView.translatesAutoresizingMaskIntoConstraints = false
    let message = SidebarScrollView.Container(
      ui.label("sidebar.plugins_placeholder",
               wrapping: true, isSmall: true, isSecondary: true, canCompress: false)
    ) {
      $0.padding(.all(.sidebarContainerPadding))
    }
    placeholderView.addSubview(message)
    message.padding(.top(.sidebarMargin), .horizontal(.sidebarMargin), .bottom(greaterThan: .sidebarMargin))

    let bottomBorder = ui.separator()
    view.addSubview(bottomBorder)
    bottomBorder.padding(.horizontal).spacing(.bottom, to: pluginContentContainerView)

    tabButtonsSegmentControl.segmentCount = 1
    tabButtonsSegmentControl.trackingMode = .momentary

    updatePluginTabs()
    updateTabActiveStatus()
    installView()

    player.observe(.iinaPluginChanged) { [unowned self] _ in
      updatePluginTabs()
    }
  }

  private func getAllTabs() -> [(id: String, name: String)] {
    player.plugins
      .filter { $0.plugin.sidebarTabName != nil }
      .map { ($0.plugin.identifier, $0.plugin.sidebarTabName!) }
  }

  func updatePluginTabs() {
    guard isViewLoaded else { return }
    allTabs_ = getAllTabs()

    pluginMenu.removeAllItems()
    allTabs_.forEach { tab in
      pluginMenu.addItem(
        withTitle: tab.name,
        action: #selector(menuItemAction),
        target: self,
        obj: tab.id
      )
    }
    // Preserve selection by identifier when plugins are reordered or removed.
    switchToTab(currentTab)
  }

  override func updateTabActiveStatus() {
    let name = allTabs_.first { $0.id == currentTab.name }?.name ?? TabType.pluginPlaceholder.name
    tabButtonsSegmentControl.setLabel(name, forSegment: 0)
  }

  override func updateTabButtonSize() {
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
    tabButtonsSegmentControl.setImage(getPluginIcon(isSmall: isCompact), forSegment: 0)

    closeSidebarBtnSizeConstraint.constant =  isCompact ? 28 : 36
  }

  override func updateTabButtonLayout() {
    super.updateTabButtonLayout()
    guard let selector = tabButtonsSegmentControl as? ScrollSelectionControl else { return }
    tabButtonsStackView.removeArrangedSubview(selector)
    selector.removeFromSuperview()
    let host = PluginSelectorHostView(selector, isLeading: isLeading)
    tabButtonsStackView.insertArrangedSubview(host, at: isLeading ? 0 : 1)
    tabButtonsStackView.distribution = .fill
    tabButtonsStackView.spacing = 10
  }

  override func switchToTab(_ tab: SidebarViewController.TabType) {
    guard isViewLoaded else { return }

    currentTab = allTabs.first { $0.tag != 0 && $0.name == tab.name } ?? firstAvailableTab
    installView()
    updateTabActiveStatus()
  }

  private func installView() {
    if currentTab.tag == 0 {
      pluginContentContainerView.subviews.forEach { $0.removeFromSuperview() }
      pluginContentContainerView.addSubview(placeholderView)
      placeholderView.padding(.all)
    } else {
      let id = currentTab.name
      if let plugin = player.plugins.first(where: { $0.plugin.identifier == id }) {
        pluginContentContainerView.subviews.forEach { $0.removeFromSuperview() }
        pluginContentContainerView.addSubview(plugin.sidebarTabView)
        plugin.sidebarTabView.padding(.all)
      }
    }
  }

  func removePluginTab(withIdentifier identifier: String) {
    guard isViewLoaded else { return }
    allTabs_.removeAll { $0.id == identifier }
    if let item = pluginMenu.items.first(where: { $0.representedObject as? String == identifier }) {
      pluginMenu.removeItem(item)
    }
    switchToTab(currentTab)
  }

  override func tabBtnSegmentControlAction(_ sender: NSSegmentedControl) {
    (sender as? ScrollSelectionControl)?.finishRoll()
    preparePluginMenu(pluginMenu)
    pluginMenu.minimumWidth = tabButtonsSegmentControl.frame.width
    let currentItem = pluginMenu.items.first(where: {
      currentTab.name == $0.representedObject as? String
    })
    mainWindow.trackPluginMenu {
      pluginMenu.popUp(positioning: currentItem, at: .zero, in: sender)
    }
  }

  func switchPlugin(_ direction: Int) {
    _ = view
    let tabs = allTabs.filter { $0.tag != 0 }
    guard let index = PluginScrollNavigation.destination(
      ids: tabs.map(\.name), currentID: currentTab.name, direction: direction
    ) else { return }
    guard let selector = tabButtonsSegmentControl as? ScrollSelectionControl else { return }
    let previousTitle = selector.label(forSegment: 0) ?? TabType.pluginPlaceholder.name
    selectPlugin(withIdentifier: tabs[index].name)
    selector.roll(through: [previousTitle, selector.label(forSegment: 0) ?? ""], direction: direction)
  }

  @objc private func menuItemAction(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    selectPlugin(withIdentifier: id)
  }
}


extension PluginViewController: NSMenuDelegate {
  func menuWillOpen(_ menu: NSMenu) {
    preparePluginMenu(menu)
  }

  private func preparePluginMenu(_ menu: NSMenu) {
    let items = menu.items
    if let current = items.firstIndex(where: { $0.representedObject as? String == currentTab.name }),
       current > 0 {
      menu.removeAllItems()
      for item in items[current...] + items[..<current] {
        menu.addItem(item)
      }
    }
    for item in menu.items {
      if currentTab.name == item.representedObject as? String {
        item.state = .on
      } else {
        item.state = .off
      }
    }
  }
}


struct PluginScrollNavigation {
  static func destination(ids: [String], currentID: String, direction: Int) -> Int? {
    guard !ids.isEmpty, direction != 0 else { return nil }
    guard let current = ids.firstIndex(of: currentID) else { return 0 }
    guard ids.count > 1 else { return nil }
    return (current + (direction > 0 ? 1 : -1) + ids.count) % ids.count
  }
}

private final class PluginSelectorHostView: NSView {
  private let selector: ScrollSelectionControl

  init(_ selector: ScrollSelectionControl, isLeading: Bool) {
    self.selector = selector
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    addSubview(selector)
    selector.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      isLeading ? selector.leadingAnchor.constraint(equalTo: leadingAnchor)
        : selector.trailingAnchor.constraint(equalTo: trailingAnchor),
      selector.centerYAnchor.constraint(equalTo: centerYAnchor),
      isLeading ? selector.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        : selector.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layout() {
    if bounds.width > 0 { selector.maximumWidth = bounds.width }
    super.layout()
  }
}
