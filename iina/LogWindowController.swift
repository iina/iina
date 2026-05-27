//
//  LogWindowController.swift
//  iina
//
//  Created by Yuze Jiang on 2022/11/10.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

extension NSToolbarItem.Identifier {
  static let followButton = NSToolbarItem.Identifier("iina.logWindow.toolbar.followButton")
  static let logLevelButton = NSToolbarItem.Identifier("iina.logWindow.toolbar.logLevelButton")
  static let subsystemButton = NSToolbarItem.Identifier("iina.logWindow.toolbar.subsystemButton")
  static let saveButton = NSToolbarItem.Identifier("iina.logWindow.toolbar.saveButton")
  static let searchField = NSToolbarItem.Identifier("iina.logWindow.toolbar.searchField")
}

fileprivate let textFieldHorizontalPadding: CGFloat = 4
fileprivate let textFieldVerticalPadding: CGFloat = 2

fileprivate let logFont = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

fileprivate func indicatorIcon(withColor color: NSColor) -> NSImage {
  return NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)!.withSymbolConfiguration(.init(scale: .small))!.tinted(color)
}

class LogWindowController: NSWindowController, NSMenuDelegate, NSToolbarDelegate, NSSearchFieldDelegate {
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()

  @Atomic private var buffer: [Logger.Log] = []
  private let arrayController = NSArrayController()
  private var isWindowVisible: Bool {
    window?.occlusionState.contains(.visible) ?? false
  }
  private var flushTimer: Timer? = nil

  private let logLevelMenu = NSMenu()
  private let subsystemMenu = NSMenu()

  private var following: Bool = false {
    didSet {
      guard let button = toolbarItem(withID: .followButton) else { return }
      let symbolName = following ? "arrow.up.left.circle.fill" : "arrow.up.left.circle"
      button.image = .sf(symbolName)
    }
  }
  private var filteredLogLevel = Logger.Level.preferred {
    didSet {
      updatePredicate()
    }
  }
  private var filteredSubsystems = Set<String>() {
    didSet {
      updatePredicate()
    }
  }
  private let searchField = NSSearchField()
  private var filterString = ""

  @objc private dynamic var predicate = NSPredicate(value: false) {
    didSet {
      guard let window else { return }
      var subtitleString = ""
      if filteredSubsystems.isEmpty {
        subtitleString = NSLocalizedString("logwindow.all_subsystems", comment: "All subsystems")
      } else {
        subtitleString = String(describing: filteredSubsystems)
      }
      subtitleString += " - "
      subtitleString += String(describing: filteredLogLevel)
      window.subtitle = subtitleString

    }
  }

  private var hasSetup = false

  convenience init() {
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: NSSize(width: 800, height: 500)),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.minSize = NSMakeSize(800, 500)
    window.title = NSLocalizedString("logwindow.title", comment: "Log Viewer")
    self.init(window: window)
    self.windowFrameAutosaveName = "LogWindow"
  }

  override func showWindow(_ sender: Any?) {
    guard let window else { return }
    if !hasSetup {
      setupTableView()

      arrayController.selectsInsertedObjects = false
      arrayController.avoidsEmptySelection = false
      arrayController.clearsFilterPredicateOnInsertion = false
      arrayController.bind(.filterPredicate, to: self, withKeyPath: "predicate", options: nil)
      tableView.bind(.content, to: arrayController, withKeyPath: "arrangedObjects", options: nil)
      tableView.bind(.selectionIndexes, to: arrayController, withKeyPath: "selectionIndexes", options: nil)

      NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged(_:)),
                                             name: NSWindow.didChangeOcclusionStateNotification, object: window)

      let toolbar = NSToolbar(identifier: "iina.logWindow.toolbar")
      toolbar.delegate = self
      toolbar.autosavesConfiguration = true
      toolbar.displayMode = .iconOnly
      window.toolbar = toolbar

      logLevelMenu.addItem(withTitle: "Dummy", action: nil, keyEquivalent: "")
      subsystemMenu.addItem(withTitle: "Dummy", action: nil, keyEquivalent: "")
      subsystemMenu.addItem(withTitle: NSLocalizedString("logwindow.clear_subsystem_selections", comment: "Clear Selections"),
                            action: #selector(clearSubsystemFilter(_:)), keyEquivalent: "")
      subsystemMenu.addItem(.separator())

      for level in Logger.Level.allCases {
        let item = NSMenuItem(title: level.description, action: #selector(logLevelChanged), keyEquivalent: "")
        item.tag = level.rawValue
        item.image = indicatorIcon(withColor: level.color)
        logLevelMenu.addItem(item)
      }
      subsystemMenu.delegate = self

      // to update the subtitle
      predicate = NSPredicate(value: true)

      hasSetup = true
    }

    super.showWindow(sender)
  }

  private func setupTableView() {
    guard let contentView = window?.contentView else { return }

    tableView.delegate = self
    tableView.style = .inset
    tableView.usesAlternatingRowBackgroundColors = true
    tableView.usesAutomaticRowHeights = true
    tableView.userInterfaceLayoutDirection = .leftToRight
    tableView.allowsMultipleSelection = true
    tableView.allowsColumnReordering = false
    tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

    tableView.menu = NSMenu()
    let copyItem = NSMenuItem(title: NSLocalizedString("logwindow.copy", comment: "Copy"), action: #selector(menuCopy), keyEquivalent: "")
    if #available(macOS 26, *) {
      copyItem.image = .sf("document.on.document")
    }
    tableView.menu?.addItem(copyItem)

    func makeColumn(key: String, minWidth: CGFloat? = nil, maxWidth: CGFloat? = nil, noTitle: Bool = false) -> NSTableColumn {
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
      column.title = noTitle ? "" : NSLocalizedString("logwindow." + key, comment: key)
      if let minWidth {
        column.minWidth = minWidth
        column.maxWidth = minWidth
      }
      if let maxWidth {
        column.maxWidth = maxWidth
      } else {
        column.resizingMask = .autoresizingMask
      }
      return column
    }

    tableView.addTableColumn(makeColumn(key: "level", minWidth: 10, noTitle: true))
    tableView.addTableColumn(makeColumn(key: "time", minWidth: 90))
    tableView.addTableColumn(makeColumn(key: "subsystem", minWidth: 100, maxWidth: 200))
    tableView.addTableColumn(makeColumn(key: "message"))

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(scrollView)

    NotificationCenter.default.addObserver(self, selector: #selector(checkIfAtBottom),
                                           name: NSScrollView.didLiveScrollNotification, object: scrollView)
    NotificationCenter.default.addObserver(self, selector: #selector(columnDidResize),
                                           name: NSTableView.columnDidResizeNotification, object: tableView)

    scrollView.padding(.all)
  }

  // MARK: - NSToolbarDelegate

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    return [.followButton, .logLevelButton, .subsystemButton, .saveButton, .searchField]
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    return [.followButton, .logLevelButton, .subsystemButton, .saveButton, .searchField]
  }

  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
    switch itemIdentifier {
    case .followButton:
      return makeFollowButton()
    case .logLevelButton:
      return makeLogLevelButton()
    case .subsystemButton:
      return makeSubsystemButton()
    case .saveButton:
      return makeSaveButton()
    case .searchField:
      return makeSearchField()
    default:
      return nil
    }
  }

  private func toolbarItem(withID id: NSToolbarItem.Identifier) -> NSToolbarItem? {
    return window?.toolbar?.items.first(where: { $0.itemIdentifier == id })
  }

  // MARK: - Item Factory

  private func makeFollowButton() -> NSToolbarItem {
    let item = NSToolbarItem(itemIdentifier: .followButton)
    item.label = NSLocalizedString("logwindow.now", comment: "Now")
    item.paletteLabel = NSLocalizedString("logwindow.now", comment: "Now")
    item.toolTip = NSLocalizedString("logwindow.now.desc", comment: "Follow latest logs")
    item.image = .sf("arrow.up.left.circle")
    item.action = #selector(followAction)
    return item
  }

  private func makeLogLevelButton() -> NSMenuToolbarItem {
    let item = NSMenuToolbarItem(itemIdentifier: .logLevelButton)
    item.label = NSLocalizedString("logwindow.log_level", comment: "Log level")
    item.paletteLabel = NSLocalizedString("logwindow.log_level", comment: "Log level")
    item.toolTip = NSLocalizedString("logwindow.log_level", comment: "Log level")
    item.showsIndicator = true
    item.title = NSLocalizedString("logwindow.log_level", comment: "Log level")
    item.menu = logLevelMenu
    updateLogLevelButtonImage(toolBarItem: item)
    return item
  }

  private func makeSubsystemButton() -> NSMenuToolbarItem {
    let item = NSMenuToolbarItem(itemIdentifier: .subsystemButton)
    item.label = NSLocalizedString("logwindow.subsystem", comment: "Subsystem")
    item.paletteLabel = NSLocalizedString("logwindow.subsystem", comment: "Subsystem")
    item.toolTip = NSLocalizedString("logwindow.subsystem", comment: "Subsystem")
    item.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Subsystem")!
    item.showsIndicator = true
    item.title = NSLocalizedString("logwindow.subsystem", comment: "Subsystem")
    item.menu = subsystemMenu
    return item
  }

  private func makeSaveButton() -> NSToolbarItem {
    let item = NSMenuToolbarItem(itemIdentifier: .saveButton)
    item.label = NSLocalizedString("logwindow.save", comment: "Save")
    item.paletteLabel = NSLocalizedString("logwindow.save", comment: "Save")
    item.toolTip = NSLocalizedString("logwindow.save", comment: "Save")
    item.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")!
    item.action = #selector(save)
    item.menu = NSMenu()
    item.menu.addItem(withTitle: NSLocalizedString("logwindow.save_filtered", comment: "Save filtered logs"), action: #selector(save), keyEquivalent: "")
    return item
  }

  private func makeSearchField() -> NSSearchToolbarItem {
    let item = NSSearchToolbarItem(itemIdentifier: .searchField)
    item.label = NSLocalizedString("logwindow.filter", comment: "Filter")
    item.paletteLabel = NSLocalizedString("logwindow.filter", comment: "Filter")
    item.toolTip = NSLocalizedString("logwindow.filter", comment: "Filter")
    searchField.placeholderString = NSLocalizedString("logwindow.filter", comment: "Filter")
    searchField.delegate = self
    item.searchField = searchField
    return item
  }

  // MARK: - NSMenuDelegate

  func menuNeedsUpdate(_ menu: NSMenu) {
    Logger.$subsystems.withLock() { subsystems in
      for (index, subsystem) in subsystems.enumerated() {
        guard !subsystem.added else { continue }
        subsystem.added = true
        let item = NSMenuItem.init(title: subsystem.rawValue, action: #selector(subsystemChanged), keyEquivalent: "")
        item.image = subsystem.image
        // 3 = dummy + clear selection item + separator
        menu.insertItem(item, at: index + 3)
      }
    }
  }

  // MARK: - Menu actions

  @IBAction func copy(_ sender: Any) {
    menuCopy()
  }

  @objc private func menuCopy() {
    let string = (arrayController.selectedObjects as! [Logger.Log]).map { $0.logString }.joined()
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(string, forType: .string)
  }

  @objc private func clearSubsystemFilter(_ sender: NSMenuItem) {
    filteredSubsystems = []
    if #available(macOS 14.0, *) {
      subsystemMenu.selectedItems = []
    } else {
      subsystemMenu.items.forEach { $0.state = .off }
    }
  }

  @objc private func subsystemChanged(_ sender: NSMenuItem) {
    if filteredSubsystems.contains(sender.title) {
      sender.state = .off
      filteredSubsystems.remove(sender.title)
    } else {
      sender.state = .on
      filteredSubsystems.insert(sender.title)
    }
  }

  @objc private func logLevelChanged(_ sender: NSMenuItem) {
    guard let newLevel = Logger.Level(rawValue: sender.tag) else { return }
    filteredLogLevel = newLevel
    updateLogLevelButtonImage()
  }

  // MARK: - UI & Log synchronization

  private func updatePredicate() {
    var predicates: [NSPredicate] = []
    if !filteredSubsystems.isEmpty {
      let subsystemPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: filteredSubsystems.map {
          NSPredicate(format: "subsystem == %@", $0)
      })
      predicates.append(subsystemPredicate)
    }
    predicates.append(NSPredicate(format: "level >= %d", filteredLogLevel.rawValue))
    if !filterString.isEmpty {
      predicates.append(NSPredicate(format: "message CONTAINS[c] %@", filterString))
    }
    predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
  }

  private func updateLogLevelButtonImage(toolBarItem: NSToolbarItem? = nil) {
    let item = toolBarItem ?? toolbarItem(withID: .logLevelButton)
    if let item {
      item.image = indicatorIcon(withColor: filteredLogLevel.color).withSymbolConfiguration(.init(scale: .medium))
    }
  }

  private func scrollToBottom() {
    guard tableView.numberOfRows > 0 else { return }
    // Force layout so auto row heights are up to date before scrolling.
    tableView.layoutSubtreeIfNeeded()
    tableView.scrollRowToVisible(tableView.numberOfRows - 1)
  }

  @objc private func checkIfAtBottom() {
    let visibleRect = tableView.visibleRect
    let totalHeight = tableView.bounds.height

    guard totalHeight > visibleRect.height else {
      following = true
      return
    }

    let tolerance: CGFloat = 2.0
    following = visibleRect.maxY >= totalHeight - tolerance
  }

  @objc private func followAction(_ sender: NSToolbarItem) {
    following = true
    scrollToBottom()
  }

  @objc private func save(_ sender: Any) {
    let saveAll = sender is NSToolbarItem
    let filename = saveAll ? "iina.log" : (window?.subtitle ?? "filtered") + " iina.log"
    Utility.quickSavePanel(title: "Log", filename: filename, sheetWindow: window) { url in
      let content: Any? = saveAll ? self.arrayController.content : self.arrayController.arrangedObjects
      let logs = (content as! [Logger.Log]).map { $0.logString }.joined()
      do {
        try logs.write(to: url, atomically: true, encoding: .utf8)
      } catch let error {
        Utility.showAlert("error_saving_file", arguments: [NSLocalizedString("logwindow.logs", comment: "logs"), error.localizedDescription])
      }
    }
  }

  func controlTextDidChange(_ notification: Notification) {
    filterString = searchField.stringValue
    updatePredicate()
  }

  func append(_ log: Logger.Log) {
    $buffer.withLock {
      $0.append(log)
    }
    if isWindowVisible {
      scheduleFlush()
    }
  }

  private func scheduleFlush() {
    guard flushTimer == nil else { return }
    flushTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
      self?.flushTimer = nil
      self?.flushBuffer()
    }
  }

  private func flushBuffer() {
    let toFlush: [Logger.Log] = $buffer.withLock {
      let copy = $0
      $0.removeAll(keepingCapacity: true)
      return copy
    }

    if !toFlush.isEmpty {
      checkIfAtBottom()
      arrayController.add(contentsOf: toFlush)
      if following {
        scrollToBottom()
      }
    }
  }

  @objc private func occlusionChanged(_ note: Notification) {
    if isWindowVisible {
      flushBuffer()
    } else {
      flushTimer = nil
    }
  }
}

extension LogWindowController: NSTableViewDelegate {
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let column = tableColumn,
          let logs = arrayController.arrangedObjects as? [Logger.Log],
          row < logs.count else { return nil }

    let log = logs[row]

    let columnID = column.identifier.rawValue
    let identifier = NSUserInterfaceItemIdentifier("\(columnID)Cell")

    let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
      ?? makeCell(identifier: identifier, columnID: columnID)
    switch columnID {
    case "level":
      cell.imageView?.image = indicatorIcon(withColor: log.level.color)
    case "time":
      cell.textField?.stringValue = log.date
    case "subsystem":
      cell.textField?.stringValue = log.subsystem
    case "message":
      cell.textField?.stringValue = log.message
      cell.textField?.preferredMaxLayoutWidth = column.width - textFieldHorizontalPadding * 2
    default:
      break
    }
    return cell
  }

  // Only provide an estimation for NSTableView, actual height will be calculated from Autolayout
  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    return 18
  }

  func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
    return false
  }

  private func makeCell(identifier: NSUserInterfaceItemIdentifier, columnID: String) -> NSTableCellView {
    let cell = NSTableCellView()
    cell.identifier = identifier

    if columnID == "level" {
      let imageView = NSImageView()
      imageView.translatesAutoresizingMaskIntoConstraints = false
      imageView.imageScaling = .scaleProportionallyDown
      cell.addSubview(imageView)
      cell.imageView = imageView
      imageView.size(width: 12, height: 12)
      imageView.padding(.top(2.5))
      imageView.center(.x)
    } else {
      let textField = NSTextField(wrappingLabelWithString: "")
      textField.font = logFont
      textField.isSelectable = false
      textField.translatesAutoresizingMaskIntoConstraints = false
      cell.addSubview(textField)
      cell.textField = textField

      if columnID == "message" {
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = 0
        textField.cell?.isScrollable = false
        textField.padding(.vertical(textFieldVerticalPadding))
      } else {
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.padding(.top(textFieldVerticalPadding))
      }
      textField.padding(.horizontal(textFieldHorizontalPadding))
    }
    return cell
  }

  @objc private func columnDidResize() {
    let messageColumn = tableView.tableColumns[3]
    let maxWidth = messageColumn.width - textFieldHorizontalPadding * 2

    tableView.enumerateAvailableRowViews { rowView, row in
      guard let cell = rowView.view(atColumn: 3) as? NSTableCellView else { return }
      cell.textField?.preferredMaxLayoutWidth = maxWidth
      cell.textField?.invalidateIntrinsicContentSize()
    }
  }

}

@objc(LogLevelTransformer) class LogLevelTransformer: ValueTransformer {
  static override func allowsReverseTransformation() -> Bool {
    return false
  }

  static override func transformedValueClass() -> AnyClass {
    return NSImage.self
  }

  override func transformedValue(_ value: Any?) -> Any? {
    guard let intValue = value as? Int, let level = Logger.Level(rawValue: intValue) else { return nil }
    return indicatorIcon(withColor: level.color)
  }
}

