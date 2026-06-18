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
    SettingsPageVideo(),
    SettingsPageAudio(),
    SettingsPageSubtitles(),
    SettingsPageNetwork(),
    SettingsPageControl(),
    SettingsPageKeyBindings(),
    SettingsPageAdvanced(),
    SettingsPagePlugin(),
    SettingsPageUtilities(),
  ])

  let sidebarList: NSTableView
  private let contentScrollView: NSScrollView
  private let highlightView: HighlightView

  var pages: [SettingsPage]
  private var cachedPageViews: [String: NSView] = [:]

  private var sectionNames: [String] = []
  private var sectionNameStackView: NSStackView?
  private var sectionIndicatorTopConstraint: NSLayoutConstraint?

  private var currentPageIndex: Int?

  private let searchBox: NSSearchField
  private lazy var completionPopover: NSPopover = createSearchPopover()
  private var currentCompletionResults: [SettingsSearch.Entry] = []

  private var pendingHighlightItem: (id: Int, parentId: Int?)?

  init(_ pages: [SettingsPage]) {
    self.pages = pages
    contentScrollView = NSScrollView()
    contentScrollView.autohidesScrollers = true

    self.sidebarList = NSTableView()
    self.searchBox = NSSearchField()
    self.highlightView = HighlightView()

    super.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: 480),
               styleMask: [.closable, .miniaturizable, .resizable, .titled, .fullSizeContentView],
               backing: .buffered, defer: false)

    self.isReleasedWhenClosed = false

    let splitViewController = NSSplitViewController()
    self.contentViewController = splitViewController

    let sidebarViewController = NSViewController()
    sidebarViewController.view = NSView()
    sidebarViewController.view.wantsLayer = true
    let sidebarBackground = if #available(macOS 26, *) {
      NSGlassEffectView()
    } else {
      NSVisualEffectView()
    }
    sidebarViewController.view.addSubview(sidebarBackground)
    sidebarBackground.translatesAutoresizingMaskIntoConstraints = false
    sidebarBackground.padding(.all)
    sidebarBackground.addSubview(searchBox)
    searchBox.translatesAutoresizingMaskIntoConstraints = false
    searchBox.controlSize = .large

    searchBox.target = self
    searchBox.action = #selector(searchBoxAction(_:))

    let sidebarScrollView = NSScrollView()
    sidebarScrollView.hasVerticalScroller = true
    sidebarScrollView.autohidesScrollers = true
    sidebarScrollView.translatesAutoresizingMaskIntoConstraints = false
    sidebarScrollView.borderType = .noBorder
    sidebarScrollView.drawsBackground = false

    sidebarList.translatesAutoresizingMaskIntoConstraints = false
    sidebarList.style = .sourceList
    sidebarList.autoresizingMask = [.width, .height]
    sidebarList.headerView = nil
    sidebarList.dataSource = self
    sidebarList.delegate = self
    let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "col"))

    sidebarBackground.addSubview(sidebarScrollView)
    sidebarScrollView.padding(.bottom, .horizontal)

    if #available(macOS 26, *) {
      searchBox.padding(.top(40), .horizontal(8))
      sidebarScrollView.spacing(.top(16), to: searchBox)
    } else {
      searchBox.padding(.top(52), .horizontal(8))
      sidebarScrollView.spacing(.top(8), to: searchBox)
    }

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

    highlightView.translatesAutoresizingMaskIntoConstraints = false
    contentViewController.view.addSubview(highlightView)
    highlightView.padding(.all)

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

    sidebarSplitItem.titlebarSeparatorStyle = .automatic
    contentSplitItem.titlebarSeparatorStyle = .automatic

    self.title = "Settings"
    self.isOpaque = false
    self.isMovableByWindowBackground = true
    self.titlebarAppearsTransparent = true
    self.toolbarStyle = .unified
    self.toolbar = NSToolbar()
    self.toolbar?.displayMode = .iconOnly

    pages.forEach { $0.registerSearchEntries() }
    SettingsSearch.makeTries()

    loadPage(at: 0)
    sidebarList.addTableColumn(col)
    sidebarScrollView.documentView = sidebarList
    sidebarList.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  }

  func loadPage(at index: Int) {
    guard let page = pages[at: index] else { return }
    if cachedPageViews[page.identifier] == nil {
      cachedPageViews[page.identifier] = page.getView()
    }
    let content = cachedPageViews[page.identifier]!
    content.autoresizingMask = [.width, .height]
    contentScrollView.documentView = content
    content.padding(.horizontal, from: contentScrollView.contentView)
    contentScrollView.documentView!.topAnchor.constraint(equalTo: contentView!.topAnchor).isActive = true

    sectionNames = content.allSubviews.compactMap {
      ($0 as? SettingsSection.View)?.sectionTitle
    }
    // if no section name, add the page name to avoid layout issues
    if sectionNames.isEmpty {
      sectionNames.append(page.title)
    }

    self.title = page.title

    DispatchQueue.main.async {
      self.updateSectionIndicator()
      page.pageLoaded()
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
      let sectionViews = documentView.allSubviews
        .compactMap { $0 as? SettingsSection.View }
      if
        let visibleIndex = sectionViews.firstIndex(where: {
          midRect.intersects($0.convert($0.bounds, to: documentView))
        }),
        let title = sectionViews[0...visibleIndex].last(where: { $0.sectionTitle != nil })?.sectionTitle
      {
        firstVisibleTitle = title
      } else if sectionNames.count == 1 {
        firstVisibleTitle = sectionNames.first
      }
    }

    guard let firstVisibleTitle = firstVisibleTitle,
          let sectionNameStackView = sectionNameStackView else { return }

    let titleIndex = sectionNames.firstIndex(of: firstVisibleTitle) ?? 0

    NSAnimationContext.runAnimationGroup({ context in
      context.duration = AccessibilityPreferences.adjustedDuration(0.1)
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

  private func highlightItem() {
    guard let pendingHighlightItem,
          let view = contentView?.allSubviews.first(where: { $0.tag == pendingHighlightItem.id })
    else { return }

    if let currentPageIndex, let parentId = pendingHighlightItem.parentId,
       let parent = pages[currentPageIndex].builtSections
         .compactMap ({ $0.find(where: { $0.itemID == parentId }) as? SettingsItem.General }).first,
       !parent.isExpanded {
      parent.toggleExpandable(true, animated: false)
    }

    contentScrollView.scrollToVisible(highlightView.bounds)

    highlightView.highlight(view)
    self.pendingHighlightItem = nil
  }
}


extension SettingsWindow {
  private class HighlightView: NSView {
    private var maskRect: NSRect?
    private var ticket: Int = 0

    override static func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
      if key == "alphaValue" {
        let kfa = CAKeyframeAnimation(keyPath: "alphaValue")
        kfa.duration = 1.0
        kfa.timingFunctions = [CAMediaTimingFunction(name: .default), CAMediaTimingFunction(name: .linear)]
        kfa.values = [1, 1, 0]
        kfa.keyTimes = [0, 0.8, 1.0]
        return kfa
      } else {
        return super.defaultAnimation(forKey: key)
      }
    }

    override func draw(_ dirtyRect: NSRect) {
      guard let maskRect = maskRect else { return }
      NSGraphicsContext.saveGraphicsState()
      let borderPath = NSBezierPath(roundedRect: maskRect, xRadius: 8, yRadius: 8)
      borderPath.lineWidth = 4
      NSColor.white.setStroke()
      borderPath.stroke()
      let rectPath = NSBezierPath(roundedRect: maskRect, xRadius: 8, yRadius: 8)
      rectPath.lineWidth = 3
      NSColor.controlAccentColor.setStroke()
      rectPath.stroke()
      NSGraphicsContext.restoreGraphicsState()
    }

    func highlight(_ view: NSView) {
      ticket += 1
      let currentTicket = ticket

      view.scrollToVisible(view.bounds.insetBy(dx: 0, dy: -20))
      isHidden = false
      alphaValue = 1

      let rectInWindow = view.convert(view.bounds.insetBy(dx: -4, dy: -4), to: nil)
      maskRect = convert(rectInWindow, from: nil)
      needsDisplay = true

      NSAnimationContext.runAnimationGroup({ _ in
        self.animator().alphaValue = 0
      }, completionHandler: { [unowned self] in
        guard currentTicket == self.ticket else { return }
        self.isHidden = true
      })
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
      return nil
    }
  }
}


fileprivate extension NSUserInterfaceItemIdentifier {
  static let searchResultItem: NSUserInterfaceItemIdentifier = .init(rawValue: "searchResultItem")
  static let searchResultItemWithParent: NSUserInterfaceItemIdentifier = .init(rawValue: "searchResultItemWithParent")
  static let searchResultHeader: NSUserInterfaceItemIdentifier = .init(rawValue: "searchResultHeader")
}


extension SettingsWindow {
  private class PopoverViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
    unowned var window: SettingsWindow

    let tableView: NSTableView = NSTableView()
    let scrollView: NSScrollView = NSScrollView()
    let noResultLabel: NSTextField = NSTextField(labelWithString: NSLocalizedString("general.no_result", comment: "No Result"))
    var results: [SettingsSearch.Entry] = []

    private var contentHeightConstraint: NSLayoutConstraint!

    init(window: SettingsWindow) {
      self.window = window
      super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
      tableView.translatesAutoresizingMaskIntoConstraints = false
      tableView.style = .plain
      tableView.delegate = self
      tableView.dataSource = self
      tableView.headerView = nil
      tableView.floatsGroupRows = false
      tableView.addTableColumn(NSTableColumn(identifier: .searchResultItem))
      tableView.target = self
      tableView.doubleAction = #selector(closePopover)

      // make the scroll view's height synchronize with its content
      tableView.postsFrameChangedNotifications = true
      NotificationCenter.default.addObserver(
        forName: NSView.frameDidChangeNotification,
        object: tableView,
        queue: .main
      ) { [unowned self] notification in
        guard let tableView = notification.object as? NSTableView else { return }
        let height = tableView.numberOfRows == 0 ? 0 :
          tableView.rect(ofRow: tableView.numberOfRows - 1).maxY + tableView.intercellSpacing.height
        self.contentHeightConstraint.constant = height + 8 // bottom inset
      }

      scrollView.translatesAutoresizingMaskIntoConstraints = false
      scrollView.documentView = tableView
      view.addSubview(scrollView)
      scrollView.padding(.all(0))
      scrollView.automaticallyAdjustsContentInsets = false
      scrollView.contentInsets.bottom = 8
      scrollView.widthAnchor.constraint(equalToConstant: 340).isActive = true
      scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
      scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: 400).isActive = true
      self.contentHeightConstraint = scrollView.heightAnchor.constraint(equalToConstant: 0)
      contentHeightConstraint.priority = .defaultHigh
      contentHeightConstraint.isActive = true

      noResultLabel.translatesAutoresizingMaskIntoConstraints = false
      noResultLabel.textColor = .secondaryLabelColor
      noResultLabel.isHidden = true
      view.addSubview(noResultLabel)
      noResultLabel.center()
    }

    func reloadData(_ data: [SettingsSearch.Entry]) {
      let dict = Dictionary(grouping: data, by: \.page)
      results = []
      for page in SettingsWindow.default.pages {
        if let entries = dict[page.identifier] {
          entries.forEach { $0.pageTitle = page.title }
          results.append(SettingsSearch.Entry(pageHeader: page.title, icon: page.image))
          // only show one entry per anchor
          // make sure parent entries displayed before children
          let sorted = Dictionary(grouping: entries, by: \.anchor).values.map { $0.first! }.sorted {
            if $0.parentEntry === $1 { return false }
            if $1.parentEntry === $0 { return true }
            if let section0 = $0.section, let section1 = $1.section {
              switch section0.localizedCompare(section1) {
              case .orderedSame: return $0.title.localizedCompare($1.title) == .orderedAscending
              case .orderedAscending: return true
              case .orderedDescending: return false
              }
            }
            return $0.title.localizedCompare($1.title) == .orderedAscending
          }
          results.append(contentsOf: sorted)
        }
      }
      noResultLabel.isHidden = !data.isEmpty
      tableView.reloadData()
    }

    @objc func closePopover() {
      window.completionPopover.close()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
      return results.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
      guard let entry = results[at: row] else { return 0 }
      return entry.isPageHeader ? 38 : entry.parentEntry != nil ? 46 : 25
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
      return results[at: row]?.isPageHeader == true
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
      guard let entry = results[at: row] else { return nil }

      if entry.isPageHeader {
        let view = (tableView.makeView(withIdentifier: .searchResultHeader,
                                       owner: self) as? HeaderView) ?? HeaderView()
        view.setup(entry: entry)
        return view
      } else if entry.parentEntry != nil {
        let view = (tableView.makeView(withIdentifier: .searchResultItemWithParent,
                                       owner: self) as? ItemWithParentView) ?? ItemWithParentView()
        view.setup(entry: entry)
        return view
      } else {
        let view = (tableView.makeView(withIdentifier: .searchResultItem,
                                       owner: self) as? ItemView) ?? ItemView()
        view.setup(entry: entry)
        return view
      }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
      guard let entry = results[at: tableView.selectedRow] else { return }
      window.pendingHighlightItem = (entry.anchor, entry.parent)
      window.navigateTo(page: entry.page)

      DispatchQueue.main.async {
        self.window.highlightItem()
      }
    }

    class HeaderView: NSTableCellView {
      var titleLabel: NSTextField!
      var iconView: NSImageView!

      func setup(entry: SettingsSearch.Entry) {
        if textField == nil {
          titleLabel = NSTextField(labelWithString: "")
          titleLabel.textColor = .secondaryLabelColor
          titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .bold)
          titleLabel.translatesAutoresizingMaskIntoConstraints = false
          addSubview(titleLabel)

          iconView = NSImageView(image: entry.icon!)
          iconView.imageScaling = .scaleProportionallyDown
          iconView.translatesAutoresizingMaskIntoConstraints = false
          addSubview(iconView)

          titleLabel.padding(.trailing(8), .bottom(8))
          iconView.padding(.leading(8), .bottom(8))
            .spacing(.trailing(8), to: titleLabel)
            .size(width: 16, height: 16)
        }
        titleLabel.stringValue = entry.page
        iconView.image = entry.icon
      }
    }

    class ItemView: NSTableCellView {
      var sectionLabel: NSTextField!
      var titleLabel: NSTextField!

      func setup(entry: SettingsSearch.Entry) {
        if textField == nil {
          sectionLabel = NSTextField(labelWithString: "")
          sectionLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
          sectionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
          sectionLabel.textColor = .textBackgroundColor
          sectionLabel.translatesAutoresizingMaskIntoConstraints = false
          sectionLabel.wantsLayer = true
          sectionLabel.layer?.cornerRadius = 3
          sectionLabel.drawsBackground = true
          sectionLabel.backgroundColor = .secondaryLabelColor
          addSubview(sectionLabel)

          titleLabel = NSTextField(labelWithString: "")
          titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
          titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
          titleLabel.lineBreakMode = .byTruncatingMiddle
          titleLabel.translatesAutoresizingMaskIntoConstraints = false
          addSubview(titleLabel)

          sectionLabel.padding(.leading(8), .bottom(6))
            .spacing(.trailing(4), to: titleLabel)
          titleLabel.padding(.trailing(8), .bottom(6))
        }
        sectionLabel.stringValue = entry.section ?? entry.pageTitle ?? ""
        titleLabel.stringValue = entry.titleForDisplay
      }
    }

    class ItemWithParentView: NSTableCellView {
      var sectionLabel: NSTextField!
      var parentLabel: NSTextField!
      var titleLabel: NSTextField!

      func setup(entry: SettingsSearch.Entry) {
        if textField == nil {
          sectionLabel = NSTextField(labelWithString: "")
          sectionLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
          sectionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
          sectionLabel.textColor = .textBackgroundColor
          sectionLabel.translatesAutoresizingMaskIntoConstraints = false
          sectionLabel.wantsLayer = true
          sectionLabel.layer?.cornerRadius = 3
          sectionLabel.drawsBackground = true
          sectionLabel.backgroundColor = .secondaryLabelColor
          addSubview(sectionLabel)

          parentLabel = NSTextField(labelWithString: "")
          parentLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
          parentLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
          parentLabel.textColor = .secondaryLabelColor
          parentLabel.lineBreakMode = .byTruncatingMiddle
          parentLabel.translatesAutoresizingMaskIntoConstraints = false
          addSubview(parentLabel)

          let icon = NSImageView(image: .sf("arrow.turn.down.right")!)
          icon.translatesAutoresizingMaskIntoConstraints = false
          addSubview(icon)

          titleLabel = NSTextField(labelWithString: "")
          titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
          titleLabel.lineBreakMode = .byTruncatingMiddle
          titleLabel.translatesAutoresizingMaskIntoConstraints = false
          addSubview(titleLabel)

          sectionLabel.padding(.leading(8)).spacing(.trailing(4), to: parentLabel)
            .center(.y, with: parentLabel)
          parentLabel.padding(.top(6), .trailing(8))
            .spacing(.bottom(4), to: titleLabel)
          icon.padding(.leading(12)).spacing(.trailing(4), to: titleLabel)
            .size(width: 11, height: 11).center(.y, with: titleLabel)
          titleLabel.padding(.trailing(8), .bottom(6))
        }

        sectionLabel.stringValue = entry.section ?? entry.pageTitle ?? ""
        parentLabel.stringValue = entry.parentEntry!.titleForDisplay
        titleLabel.stringValue = entry.titleForDisplay
      }
    }
  }

  private func createSearchPopover() -> NSPopover {
    let popover = NSPopover()
    popover.behavior = .transient
    popover.animates = false
    popover.contentViewController = PopoverViewController(window: self)
    return popover
  }

  @objc func searchBoxAction(_ sender: Any) {
    let searchString = searchBox.stringValue.lowercased().trimWhitespaceSuffix().removedLastSemicolon()
    // if no search string, close the popover
    guard !searchString.isEmpty else {
      completionPopover.close()
      return
    }

    let popoverViewController = completionPopover.contentViewController as! PopoverViewController
    if !completionPopover.isShown {
      let range = searchBox.currentEditor()?.selectedRange
      completionPopover.show(relativeTo: searchBox.bounds, of: searchBox, preferredEdge: .maxY)
      searchBox.selectText(self)
      searchBox.currentEditor()?.selectedRange = range ?? NSMakeRange(0, 0)
    }
    if let result = SettingsSearch.search(searchString) {
      popoverViewController.reloadData(result)
    }
  }

  func navigateTo(page: String) {
    guard let idx = pages.firstIndex(where: { $0.identifier == page }) else { return }

    if idx != sidebarList.selectedRow {
      let selectIdx = idx < sidebarList.selectedRow ? idx : idx + 1
      sidebarList.selectRowIndexes(IndexSet(integer: selectIdx), byExtendingSelection: false)
    }
  }
}


extension SettingsWindow: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int {
    return pages.count + 1
  }

  @objc
  private func jumpToSection(_ sender: NSButton) {
    guard let documentView = contentScrollView.documentView else { return }
    let sectionName = sender.title

    guard let view = documentView.allSubviews.first(where: {
      ($0 as? SettingsSection.View)?.sectionTitle == sectionName
    }) else { return }

    guard let label = (view as? SettingsSection.View)?.titleField else { return }
    let clipView = contentScrollView.contentView
    let labelRect = label.convert(label.bounds, to: clipView)

    let vr = documentView.visibleRect
    let y = labelRect.minY - vr.height * 0.33 - 40
    let rect = NSRect(x: labelRect.minX, y: y, width: labelRect.width, height: vr.height - 40)

    var newOrigin = clipView.bounds.origin
    if newOrigin.x > rect.origin.x {
      newOrigin.x = rect.origin.x
    }
    if rect.origin.x > newOrigin.x + clipView.bounds.width - rect.width {
      newOrigin.x = rect.origin.x - clipView.bounds.width + rect.width
    }
    if newOrigin.y > rect.origin.y {
      newOrigin.y = rect.origin.y
    }
    if rect.origin.y > newOrigin.y + clipView.bounds.height - rect.height {
      newOrigin.y = rect.origin.y - clipView.bounds.height + rect.height
    }

    NSAnimationContext.runAnimationGroup({ context in
      context.duration = AccessibilityPreferences.adjustedDuration(0.25)
      clipView.animator().setBoundsOrigin(newOrigin)
    }, completionHandler: {
      self.contentScrollView.reflectScrolledClipView(clipView)
    })
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
      indicatorImage.contentTintColor = .init(white: 0.5, alpha: 1)
      indicatorImage.translatesAutoresizingMaskIntoConstraints = false

      let line = VerticalLine(frame: NSRect(x: 0, y: 0, width: 1, height: 40))
      line.translatesAutoresizingMaskIntoConstraints = false
      line.size(width: 16)
      line.addSubview(indicatorImage)
      indicatorImage.center(.x).size(width: 8, height: 8)

      self.sectionIndicatorTopConstraint = indicatorImage.centerYAnchor.constraint(equalTo: line.topAnchor, constant: 8)
      sectionIndicatorTopConstraint?.isActive = true
      sectionStackView.addArrangedSubview(line)

      let sectionNameStackView = NSStackView()
      sectionNameStackView.translatesAutoresizingMaskIntoConstraints = false
      sectionNameStackView.orientation = .vertical
      sectionNameStackView.alignment = .leading
      for name in sectionNames {
        let nameLabel = NSButton(title: name, target: self, action: #selector(jumpToSection))
        nameLabel.controlSize = .small
        nameLabel.isBordered = false
        sectionNameStackView.addArrangedSubview(nameLabel)
      }
      sectionStackView.addArrangedSubview(sectionNameStackView)

      cell.addSubview(sectionStackView)
      sectionStackView.center(.y).padding(.leading(8), .trailing(4))

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
    if #unavailable(macOS 14) {
      imageView.imageScaling = .scaleProportionallyUpOrDown
    }
    if #available(macOS 26, *) {
      imageView.contentTintColor = .textColor
    } else {
      imageView.contentTintColor = .controlAccentColor
    }

    let labelStackView = NSStackView(views: [imageView, textField])
    labelStackView.orientation = .horizontal
    labelStackView.alignment = .centerY
    labelStackView.translatesAutoresizingMaskIntoConstraints = false

    cell.addSubview(labelStackView)
    labelStackView.center(.y).padding(.horizontal)
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
    guard let currentPageIndex else { return false }
    return row != currentPageIndex + 1
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    let tableView = notification.object as! NSTableView

    if let prevRow = currentPageIndex {
      loadPage(at: tableView.selectedRow > prevRow ? tableView.selectedRow - 1 : tableView.selectedRow)
      let options: NSTableView.AnimationOptions = Preference.bool(for: PK.disableAnimations) ?
        [] : [.effectFade, .slideDown]
      tableView.removeRows(at: IndexSet(integer: prevRow + 1), withAnimation: options)
      tableView.insertRows(at: IndexSet(integer: tableView.selectedRow + 1), withAnimation: options)
    }
    currentPageIndex = tableView.selectedRow
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


fileprivate extension String {
  func removedLastSemicolon() -> String {
    let trimmed = trimWhitespaceSuffix()
    guard !trimmed.hasSuffix(":") else { return String(trimmed.dropLast()) }
    return self
  }

  func trimWhitespaceSuffix() -> String {
    self.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
  }
}

