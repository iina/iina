//
//  SettingsWindow.swift
//  iina
//
//  Created by Hechen Li on 6/19/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Cocoa

class SettingsWindow: NSWindow {
  static let `default`: SettingsWindow = SettingsWindow([
    SettingsPageGeneral()
  ])

  let contentScrollView: NSScrollView
  var pages: [SettingsPage]

  init(_ pages: [SettingsPage]) {
    self.pages = pages
    contentScrollView = NSScrollView()

    super.init(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
               styleMask: [.closable, .miniaturizable, .resizable, .titled, .fullSizeContentView],
               backing: .buffered, defer: false)

    let splitViewController = NSSplitViewController()
    self.contentViewController = splitViewController

    let sidebarViewController = NSViewController()
    sidebarViewController.view = NSView()
    sidebarViewController.view.wantsLayer = true
    let sidebarBackground = NSVisualEffectView()
    sidebarViewController.view.addSubview(sidebarBackground)
    sidebarBackground.translatesAutoresizingMaskIntoConstraints = false
    sidebarBackground.fillSuperView()
    let searchBox = NSSearchField()
    sidebarBackground.addSubview(searchBox)
    searchBox.translatesAutoresizingMaskIntoConstraints = false
    searchBox.paddingToSuperView(top: 52, leading: 8, trailing: 8)
    if #available(macOS 11.0, *) {
      searchBox.controlSize = .large
    }
    let sidebarScrollView = NSScrollView()
    sidebarScrollView.translatesAutoresizingMaskIntoConstraints = false
    sidebarScrollView.hasVerticalScroller = true
    sidebarScrollView.borderType = .noBorder
    sidebarScrollView.drawsBackground = false
    let sidebarList = NSTableView()
    if #available(macOS 11.0, *) {
      sidebarList.style = .sourceList
    } else {
      sidebarList.selectionHighlightStyle = .sourceList
    }
    sidebarList.autoresizingMask = [.width, .height]
    sidebarList.headerView = nil
    sidebarList.dataSource = self
    sidebarList.delegate = self
    let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "col"))
    sidebarList.addTableColumn(col)
    sidebarScrollView.documentView = sidebarList

    sidebarBackground.addSubview(sidebarScrollView)
    sidebarScrollView.paddingToSuperView(bottom: 0, leading: 0, trailing: 0)
    sidebarBackground.addConstraint(sidebarScrollView.topAnchor.constraint(equalTo: searchBox.bottomAnchor, constant: 8))

    let contentViewController = NSViewController()
    contentViewController.view = NSView()

    contentScrollView.translatesAutoresizingMaskIntoConstraints = false
    contentScrollView.hasVerticalScroller = true
    contentScrollView.borderType = .noBorder
    contentScrollView.drawsBackground = false

    contentViewController.view.addSubview(contentScrollView)
    contentScrollView.fillSuperView()

    NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
                                           name: NSView.boundsDidChangeNotification, object: nil)

    // Add the sidebar and content view controllers to the split view
    let sidebarSplitItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
    sidebarSplitItem.minimumThickness = 180
    sidebarSplitItem.canCollapse = false
    splitViewController.addSplitViewItem(sidebarSplitItem)

    let contentSplitItem = NSSplitViewItem(viewController: contentViewController)
    contentSplitItem.minimumThickness = 400
    splitViewController.addSplitViewItem(contentSplitItem)

    if #available(macOS 11.0, *) {
      sidebarSplitItem.titlebarSeparatorStyle = .automatic
      contentSplitItem.titlebarSeparatorStyle = .automatic
    } else {
      // Fallback on earlier versions
    }

    self.title = "Settings"
    self.isOpaque = false
    self.isMovableByWindowBackground = true
    self.titlebarAppearsTransparent = true
    if #available(macOS 11.0, *) {
      self.toolbarStyle = .unified
      self.toolbar = NSToolbar()
    }

    loadPage(at: 0)
  }

  func loadPage(at index: Int) {
    guard let page = pages[at: index] else { return }
    let content = page.getContent()
    content.autoresizingMask = [.width, .height]
    contentScrollView.documentView = content
    content.paddingToView(contentScrollView.contentView, top: 44, bottom: 8, leading: 0, trailing: 0)
  }

  func show() {
    self.center()
    self.makeKeyAndOrderFront(nil)
  }

  @objc func scrolled(_ notification: Notification) {
    titlebarAppearsTransparent = contentScrollView.contentView.bounds.origin.y >= 8
  }
}


extension SettingsWindow: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int {
    return 3
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let text = NSTextField()
    text.stringValue = "Hello World"
    let cell = NSTableCellView()
    cell.addSubview(text)
    text.drawsBackground = false
    text.isBordered = false
    text.translatesAutoresizingMaskIntoConstraints = false
    cell.addConstraint(NSLayoutConstraint(item: text, attribute: .centerY, relatedBy: .equal, toItem: cell, attribute: .centerY, multiplier: 1, constant: 0))
    cell.addConstraint(NSLayoutConstraint(item: text, attribute: .left, relatedBy: .equal, toItem: cell, attribute: .left, multiplier: 1, constant: 8))
    cell.addConstraint(NSLayoutConstraint(item: text, attribute: .right, relatedBy: .equal, toItem: cell, attribute: .right, multiplier: 1, constant: -8))
    return cell
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    return "AAAAAA"
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let rowView = NSTableRowView()
    rowView.isEmphasized = false
    return rowView
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    return 36
  }
}

