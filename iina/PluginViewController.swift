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
    0, NSLocalizedString("sidebar.plugins", comment: ""), .plugin)
}

class PluginViewController: SidebarViewController {
  override var sidebarType: SidebarController.ViewType {
    .plugins
  }
  override var leadingPrefKey: Preference.Key {
    .sidebarPluginsDisplayAtLeading
  }

  private lazy var allTabs_: [(id: String, name: String)] = getAllTabs()

  override var allTabs: [TabType] {
    [.pluginPlaceholder] + allTabs_.enumerated().map { (i, tuple) in
      TabType(i + 1, tuple.id, .plugin)
    }
  }
  override var defaultTab: TabType { .pluginPlaceholder }
  override var useTabView: Bool { false }

  private var pluginContentContainerView: NSView!
  private var placeholderView: NSView!

  private var pluginMenu = NSMenu()

  private func getPluginIcon(isSmall: Bool) -> NSImage {
    let config = isSmall ? compactIconConfig : iconConfig
    return NSImage.sf("puzzlepiece.extension.fill", withConfiguration: config) ?? .plugin
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
               wrapping: true, isSmall: true, isSecondary: true)
    ) {
      $0.padding(.all(.sidebarContainerPadding))
    }
    placeholderView.addSubview(message)
    message.padding(.top(.sidebarMargin), .horizontal(.sidebarMargin), .bottom(greaterThan: .sidebarMargin))

    let bottomBorder = ui.separator()
    view.addSubview(bottomBorder)
    bottomBorder.padding(.horizontal).spacing(.bottom, to: pluginContentContainerView)

    tabButtonsSegmentControl.segmentCount = 2
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
  }

  override func updateTabActiveStatus() {
    let name = if currentTab.tag == 0 {
      TabType.pluginPlaceholder.name
    } else {
      allTabs_[currentTab.tag - 1].name
    }
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
    tabButtonsSegmentControl.setImage(.triangleDown, forSegment: 1)

    closeSidebarBtnSizeConstraint.constant =  isCompact ? 28 : 36
  }

  override func switchToTab(_ tab: SidebarViewController.TabType) {
    guard isViewLoaded else { return }

    currentTab = tab
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
    if currentTab.name == identifier {
      pluginContentContainerView.subviews.forEach { $0.removeFromSuperview() }
    }
    updatePluginTabs()
  }

  override func tabBtnSegmentControlAction(_ sender: NSSegmentedControl) {
    pluginMenu.minimumWidth = tabButtonsSegmentControl.frame.width
    let currentItem = pluginMenu.items.first(where: {
      currentTab.name == $0.representedObject as? String
    })
    if sender.selectedSegment == 1 {
      pluginMenu.popUp(positioning: currentItem, at: .zero, in: sender)
    }
  }

  @objc private func menuItemAction(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String,
          let tab = allTabs.first(where: { $0.name == id }) else { return }
    switchToTab(tab)
  }
}


extension PluginViewController: NSMenuDelegate {
  func menuWillOpen(_ menu: NSMenu) {
    for item in menu.items {
      if currentTab.name == item.representedObject as? String {
        item.state = .on
      } else {
        item.state = .off
      }
    }
  }
}
