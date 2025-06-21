//
//  SettingsWindow.swift
//  iina
//
//  Created by Hechen Li on 6/19/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Cocoa

fileprivate extension NSView {
  var allSubviews: [NSView] {
    var subviews = [NSView]()
    for subview in self.subviews {
      subviews.append(subview)
      subviews.append(contentsOf: subview.allSubviews)
    }
    return subviews
  }
}

class SettingsWindow: NSWindow {
  static let `default`: SettingsWindow = SettingsWindow([
    SettingsPageGeneral(),
    SettingsPageUI(),
    SettingsPageVideoAudio(),
    SettingsPageSubtitles(),
  ])

  let contentScrollView: NSScrollView
  var pages: [SettingsPage]

  private var sectionNames: [String] = []
  private var sectionNameStackView: NSStackView?
  private var sectionIndicatorTopConstraint: NSLayoutConstraint?

  init(_ pages: [SettingsPage]) {
    self.pages = pages
    contentScrollView = NSScrollView()
    contentScrollView.autohidesScrollers = true

    super.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: 480),
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
    sidebarBackground.padding(.all)
    let searchBox = NSSearchField()
    sidebarBackground.addSubview(searchBox)
    searchBox.translatesAutoresizingMaskIntoConstraints = false
    searchBox.padding(.top(52), .horizontal(8))
    if #available(macOS 11.0, *) {
      searchBox.controlSize = .large
    }
    let sidebarScrollView = NSScrollView()
    sidebarScrollView.hasVerticalScroller = true
    sidebarScrollView.autohidesScrollers = true
    sidebarScrollView.translatesAutoresizingMaskIntoConstraints = false
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

    sidebarBackground.addSubview(sidebarScrollView)
    sidebarScrollView.padding(.bottom, .horizontal)
    sidebarBackground.addConstraint(sidebarScrollView.topAnchor.constraint(equalTo: searchBox.bottomAnchor, constant: 8))

    let contentViewController = NSViewController()
    contentViewController.view = NSView()

    let contentView = FlippedClipView()
    contentView.translatesAutoresizingMaskIntoConstraints = false
    contentScrollView.contentView = contentView
    contentScrollView.translatesAutoresizingMaskIntoConstraints = false
    contentScrollView.hasVerticalScroller = true
    contentScrollView.borderType = .noBorder
    contentScrollView.drawsBackground = false

    contentViewController.view.addSubview(contentScrollView)
    contentScrollView.padding(.all)

    NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
                                           name: NSView.boundsDidChangeNotification, object: nil)

    // Add the sidebar and content view controllers to the split view
    let sidebarSplitItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
    sidebarSplitItem.minimumThickness = 200
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
    sidebarList.addTableColumn(col)
    sidebarScrollView.documentView = sidebarList
    sidebarList.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  }

  func loadPage(at index: Int) {
    guard let page = pages[at: index] else { return }
    let content = page.getContent()
    content.autoresizingMask = [.width, .height]
    contentScrollView.documentView = content
    content.padding(to: contentScrollView.contentView, .horizontal)
    contentScrollView.documentView!.topAnchor.constraint(equalTo: contentView!.topAnchor).isActive = true

    sectionNames = content.allSubviews.compactMap {
      if let view = $0 as? SettingsListView { view.listTitle } else { nil }
    }
    self.title = page.title

    DispatchQueue.main.async {
      self.updateSectionIndicator()
    }
  }

  func show() {
    self.setFrameAutosaveName("IINAPreferenceWindowV2")
    self.makeKeyAndOrderFront(nil)
  }

  @objc func scrolled(_ notification: Notification) {
    titlebarAppearsTransparent = contentScrollView.contentView.bounds.origin.y <= -52
    updateSectionIndicator()
  }

  private func updateSectionIndicator() {
    guard let documentView = contentScrollView.documentView else { return }

    let padding: CGFloat = 40
    var firstVisibleTitle: String?
    if contentScrollView.contentView.bounds.origin.y <= -52 + padding {
      // always return the first section if scrolled amount is small enough
      firstVisibleTitle = sectionNames.first
    } else if contentScrollView.contentView.bounds.maxY > documentView.bounds.height - padding {
      // always return the last section if already scrolled to the end
      firstVisibleTitle = sectionNames.last
    } else {
      // get the section that is in the middle of the viewport
      let vr = documentView.visibleRect
      let midRect = NSRect(x: vr.origin.x, y: vr.origin.y + vr.height * 0.33, width: vr.width, height: 40)
      let listViews = documentView.allSubviews
        .compactMap { $0 as? SettingsListView }
        .filter { !($0 is SettingsSubListView) }
      if
        let visibleIndex = listViews.firstIndex(where: {
          midRect.intersects($0.convert($0.bounds, to: documentView))
        }),
        let title = listViews[0...visibleIndex].last(where: { $0.listTitle != nil })?.listTitle
      {
        firstVisibleTitle = title
      }
    }

    guard let firstVisibleTitle = firstVisibleTitle,
          let sectionNameStackView = sectionNameStackView else { return }

    let titleIndex = sectionNames.firstIndex(of: firstVisibleTitle) ?? 0

    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.1
      context.timingFunction = CAMediaTimingFunction(name: .linear)
      sectionIndicatorTopConstraint?.animator().constant = CGFloat(8 + 22 * titleIndex)
      sectionNameStackView.arrangedSubviews.forEach {
        if let view = $0 as? NSTextField {
          view.animator().textColor = view.stringValue == firstVisibleTitle ? .labelColor : .secondaryLabelColor
        }
      }
    }, completionHandler: {
      sectionNameStackView.arrangedSubviews.forEach {
        if let view = $0 as? NSTextField {
          let isActive = view.stringValue == firstVisibleTitle
          view.font = .systemFont(ofSize: isActive ? NSFont.smallSystemFontSize + 1 : NSFont.smallSystemFontSize,
                                  weight: isActive ? .bold : .regular)
        }
      }
    })
  }

  private var stopCall = true
}


extension SettingsWindow: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int {
    return pages.count + 1
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = NSTableCellView()
    let selectedRow = tableView.selectedRow < 0 ? 0 : tableView.selectedRow

    if row == selectedRow + 1 {
      let sectionStackView = NSStackView()
      sectionStackView.translatesAutoresizingMaskIntoConstraints = false
      sectionStackView.orientation = .horizontal
      sectionStackView.spacing = 8

      let indicatorImage = NSImageView(image: .init(systemSymbolName: "circlebadge.fill", accessibilityDescription: nil)!)
      indicatorImage.contentTintColor = .secondaryLabelColor
      indicatorImage.translatesAutoresizingMaskIntoConstraints = false

      let line = VerticalLine(frame: NSRect(x: 0, y: 0, width: 1, height: 40))
      line.translatesAutoresizingMaskIntoConstraints = false
      line.size(width: 16)
      line.addSubview(indicatorImage)
      indicatorImage.center(x: true).size(width: 8, height: 8)

      self.sectionIndicatorTopConstraint = indicatorImage.centerYAnchor.constraint(equalTo: line.topAnchor, constant: 8)
      sectionIndicatorTopConstraint?.isActive = true
      sectionStackView.addArrangedSubview(line)

      let sectionNameStackView = NSStackView()
      sectionNameStackView.translatesAutoresizingMaskIntoConstraints = false
      sectionNameStackView.orientation = .vertical
      sectionNameStackView.alignment = .leading
      for name in sectionNames {
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        sectionNameStackView.addArrangedSubview(nameLabel)
      }
      sectionStackView.addArrangedSubview(sectionNameStackView)

      cell.addSubview(sectionStackView)
      sectionStackView.center(y: true).padding(.leading(8), .trailing(4))

      self.sectionNameStackView = sectionNameStackView
      return cell
    }

    let row = row > selectedRow ? row - 1 : row

    let textField = NSTextField(labelWithString: pages[row].title)
    textField.stringValue = pages[row].title
    textField.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .bold)
    textField.translatesAutoresizingMaskIntoConstraints = false

    let imageView = NSImageView(image: pages[row].image)
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.size(width: 24, height: 24)
    imageView.contentTintColor = .controlAccentColor

    let labelStackView = NSStackView(views: [imageView, textField])
    labelStackView.orientation = .horizontal
    labelStackView.alignment = .centerY
    labelStackView.translatesAutoresizingMaskIntoConstraints = false

    cell.addSubview(labelStackView)
    labelStackView.center(y: true).padding(.horizontal)
    return cell
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    return ""
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let rowView = NSTableRowView()
    rowView.isEmphasized = false
    return rowView
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    let selectedRow = tableView.selectedRow < 0 ? 0 : tableView.selectedRow
    return if selectedRow + 1 == row {
      CGFloat(12 + sectionNames.count * 22)
    } else {
      CGFloat(36)
    }
  }

  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    return row != tableView.selectedRow + 1
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    let tableView = notification.object as! NSTableView

    if let prevIndex = (notification.userInfo?["NSTableViewPreviousRowSelectionUserInfoKey"] as? NSIndexSet),
       prevIndex.count > 0 {
      let prevRow = prevIndex.firstIndex
      loadPage(at: tableView.selectedRow > prevRow ? tableView.selectedRow - 1 : tableView.selectedRow)
      tableView.removeRows(at: IndexSet(integer: prevRow + 1), withAnimation: [.effectFade, .slideUp])
      tableView.insertRows(at: IndexSet(integer: tableView.selectedRow + 1), withAnimation: [.effectFade, .slideDown])
    }
  }
}


fileprivate class FlippedClipView: NSClipView {
  override var isFlipped: Bool {
    return true
  }
}


fileprivate class VerticalLine: NSView {
  override func draw(_ dirtyRect: NSRect) {
    let color = NSAppearance.currentDrawing().isDark ? NSColor.white : NSColor.black
    color.withAlphaComponent(0.4).setFill()
    NSBezierPath(rect: NSRect(x: frame.width / 2 - 0.5, y: 0, width: 1, height: frame.height)).fill()
    super.draw(dirtyRect)
  }
}
