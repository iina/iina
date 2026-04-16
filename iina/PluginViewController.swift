//
//  PluginViewController.swift
//  iina
//
//  Created by Hechen Li on 11/11/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Cocoa

class PluginViewController: NSViewController, SidebarViewController {

  var downShift: CGFloat = 0 {
    didSet {
      buttonTopConstraint.constant = downShift
    }
  }

  override var nibName: NSNib.Name {
    return NSNib.Name("PluginViewController")
  }

  weak var mainWindow: MainWindowController! {
    didSet {
      self.player = mainWindow.player
    }
  }

  @IBOutlet weak var pluginTabsView: NSView!
  @IBOutlet weak var pluginTabsViewHeightConstraint: NSLayoutConstraint!
  @IBOutlet weak var pluginTabsScrollView: NSScrollView!
  @IBOutlet weak var pluginContentContainerView: NSView!
  @IBOutlet weak var buttonTopConstraint: NSLayoutConstraint!

  private var pluginTabsStackView: NSStackView!
  private var pluginTabs: [String: SidebarTabView] = [:]


  weak var player: PlayerCore!

  var currentPluginID: String?
  private var pendingSwitchRequest: String?

  override func viewDidLoad() {
    super.viewDidLoad()

    pluginContentContainerView.translatesAutoresizingMaskIntoConstraints = false

    setupPluginTabs()
    if pendingSwitchRequest == nil {
      updateTabActiveStatus()
    } else {
      switchToTab(pendingSwitchRequest!)
      pendingSwitchRequest = nil
    }
  }

  func pleaseSwitchToTab(_ id: String) {
    if isViewLoaded {
      switchToTab(id)
    } else {
      // cache the request
      pendingSwitchRequest = id
    }
  }

  func setupPluginTabs() {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false
    pluginTabsStackView = NSStackView()
    pluginTabsStackView.translatesAutoresizingMaskIntoConstraints = false
    pluginTabsStackView.alignment = .centerY
    container.addSubview(pluginTabsStackView)
    pluginTabsScrollView.documentView = container
    Utility.quickConstraints(["H:|-8-[v]-8-|", "V:|-0-[v(==36)]-0-|"], ["v": pluginTabsStackView])
    updatePluginTabs()
  }

  func updatePluginTabs() {
    guard isViewLoaded else { return }
    var added = false
    pluginTabsStackView.arrangedSubviews.forEach {
      pluginTabsStackView.removeArrangedSubview($0)
    }
    pluginTabs.removeAll()
    player.plugins.forEach {
      guard let name = $0.plugin.sidebarTabName else { return }
      let tab = SidebarTabView()
      tab.name = name
      tab.pluginID = $0.plugin.identifier
      tab.pluginSidebarView = self
      pluginTabsStackView.addArrangedSubview(tab.view)
      pluginTabs[$0.plugin.identifier] = tab
      added = true
    }
    pluginTabsView.isHidden = !added
    pluginTabsViewHeightConstraint.constant = added ? 36 : 0
    updateTabActiveStatus()
  }

  private func updateTabActiveStatus() {
    pluginTabs.values.forEach { tab in
      tab.isActive = tab.pluginID == currentPluginID
    }
  }

  private func switchToTab(_ tab: String?) {
    guard isViewLoaded else { return }

    if let plugin = player.plugins.first(where: { $0.plugin.identifier == tab }) {
      pluginContentContainerView.subviews.forEach { $0.removeFromSuperview() }
      pluginContentContainerView.addSubview(plugin.sidebarTabView)
      Utility.quickConstraints(["H:|-0-[v]-0-|", "V:|-0-[v]-0-|"], ["v": plugin.sidebarTabView])
      currentPluginID = tab
    }
    updateTabActiveStatus()
  }

  func removePluginTab(withIdentifier identifier: String) {
    guard isViewLoaded else { return }
    if currentPluginID == identifier {
      switchToTab(nil)
      pluginContentContainerView.subviews.forEach { $0.removeFromSuperview() }
    }
    updatePluginTabs()
  }
}
