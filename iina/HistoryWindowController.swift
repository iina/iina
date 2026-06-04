//
//  HistoryWindowController.swift
//  iina
//
//  Created by lhc on 28/4/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

fileprivate let MenuItemTagShowInFinder = 100
fileprivate let MenuItemTagDelete = 101
fileprivate let MenuItemTagDeleteFile = 102
fileprivate let MenuItemTagSearchFilename = 200
fileprivate let MenuItemTagSearchFullPath = 201
fileprivate let MenuItemTagPlay = 300
fileprivate let MenuItemTagPlayInNewWindow = 301

fileprivate extension NSUserInterfaceItemIdentifier {
  static let time = NSUserInterfaceItemIdentifier("Time")
  static let filename = NSUserInterfaceItemIdentifier("Filename")
  static let progress = NSUserInterfaceItemIdentifier("Progress")
  static let group = NSUserInterfaceItemIdentifier("Group")
  static let contextMenu = NSUserInterfaceItemIdentifier("ContextMenu")
}

class HistoryWindowController: NSWindowController, NSOutlineViewDelegate, NSOutlineViewDataSource, NSMenuDelegate, NSMenuItemValidation {

  enum SortOption: Int {
    case lastPlayed = 0
    case fileLocation
  }

  enum SearchOption {
    case filename, fullPath
  }

  private static let timeColMinWidths: [SortOption: CGFloat] = [
    .lastPlayed: 60,
    .fileLocation: 145
  ]

  private let getKey: [SortOption: (PlaybackHistory) -> String] = [
    .lastPlayed: { DateFormatter.localizedString(from: $0.addedDate, dateStyle: .medium, timeStyle: .none) },
    .fileLocation: { $0.url.deletingLastPathComponent().path }
  ]

  let scrollView = NSScrollView()
  let outlineView = OutlineView()

  var groupBy: SortOption = .lastPlayed
  var searchOption: SearchOption = .fullPath

  private var historyData: [String: [PlaybackHistory]] = [:]
  private var historyDataKeys: [String] = []

  init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Playback History"
    window.setFrameAutosaveName("PlaybackHistoryWindow")
    window.minSize = NSMakeSize(400, 200)
    super.init(window: window)

    let toolbar = NSToolbar(identifier: "HitoryWindowToolbar")
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = false
    toolbar.autosavesConfiguration = false
    if #available(macOS 13, *) {
      toolbar.centeredItemIdentifiers = [Self.groupBy]
    }
    window.toolbar = toolbar
    window.toolbarStyle = .unified

    NotificationCenter.default.addObserver(forName: .iinaHistoryUpdated, object: nil, queue: .main) { [unowned self] _ in
      self.reloadData()
    }

    scrollView.documentView = outlineView
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.hasHorizontalScroller = false
    window.contentView?.addSubview(scrollView)
    scrollView.padding(.all)

    outlineView.style = .fullWidth
    outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
    outlineView.allowsMultipleSelection = true
    outlineView.autosaveName = "HistoryWindowTable"
    outlineView.allowsColumnReordering = false
    outlineView.allowsExpansionToolTips = true

    [(NSUserInterfaceItemIdentifier.filename, "Media", 200, 5000), (.progress, "Progress", 110, 1000), (.time, "Played at", 60, 300)].map {
      let column = NSTableColumn(identifier: $0.0)
      column.title = $0.1
      column.minWidth = $0.2
      column.maxWidth = $0.3
      return column
    }.forEach { outlineView.addTableColumn($0) }

    prepareData()
    outlineView.delegate = self
    outlineView.dataSource = self
    outlineView.menu = makeContextMenu()
    outlineView.menu?.delegate = self
    outlineView.target = self
    outlineView.doubleAction = #selector(doubleAction)
    outlineView.expandItem(nil, expandChildren: true)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func reloadData() {
    prepareData()
    adjustTimeColumnMinWidth()
    outlineView.reloadData()
    outlineView.expandItem(nil, expandChildren: true)
  }

  // Change min width of "Played at" column
  private func adjustTimeColumnMinWidth() {
    guard let timeColumn = outlineView.tableColumn(withIdentifier: .time) else { return }
    let newMinWidth = HistoryWindowController.timeColMinWidths[groupBy]!
    guard newMinWidth != timeColumn.minWidth else { return }
    if timeColumn.width < newMinWidth {
      if let filenameColumn = outlineView.tableColumn(withIdentifier: .filename) {
        donateColWidth(to: timeColumn, targetWidth: newMinWidth, from: filenameColumn)
      }
      if timeColumn.width < timeColumn.minWidth {
        if let progressColumn = outlineView.tableColumn(withIdentifier: .progress) {
          donateColWidth(to: timeColumn, targetWidth: newMinWidth, from: progressColumn)
        }
      }
    }
    // Do not set this until after width has been adjusted! Otherwise AppKit will change its width property
    // but will not actually resize it:
    timeColumn.minWidth = newMinWidth
    outlineView.layoutSubtreeIfNeeded()
    Logger.log("Updated \"\(timeColumn.identifier.rawValue)\" col width: \(timeColumn.width), minWidth: \(timeColumn.minWidth)", level: .verbose)
  }

  private func donateColWidth(to targetColumn: NSTableColumn, targetWidth: CGFloat, from donorColumn: NSTableColumn) {
    let extraWidthNeeded = targetWidth - targetColumn.width
    // Don't take more than needed, or more than possible:
    let widthToDonate = min(extraWidthNeeded, max(donorColumn.width - donorColumn.minWidth, 0))
    if widthToDonate > 0 {
      Logger.log("Donating \(widthToDonate) pts width to col \"\(targetColumn.identifier.rawValue)\" from \"\(donorColumn.identifier.rawValue)\" width (\(donorColumn.width))")
      donorColumn.width -= widthToDonate
      targetColumn.width += widthToDonate
    }
  }

  private func prepareData(fromHistory historyList: [PlaybackHistory]? = nil) {
    // reconstruct data
    historyData.removeAll()
    historyDataKeys.removeAll()

    let historyList = historyList ?? HistoryController.shared.history

    for entry in historyList {
      addToData(entry, forKey: getKey[groupBy]!(entry))
    }
  }

  private func addToData(_ entry: PlaybackHistory, forKey key: String) {
    if historyData[key] == nil {
      historyData[key] = []
      historyDataKeys.append(key)
    }
    historyData[key]!.append(entry)
  }

  private func removeAfterConfirmation(_ entries: [PlaybackHistory]) {
    Utility.quickAskPanel("delete_history", sheetWindow: window) { respond in
      guard respond == .alertFirstButtonReturn else { return }
      HistoryController.shared.remove(entries)
    }
  }

  private func removeFileAfterConfirmation(_ entries: [PlaybackHistory]) {
    Utility.quickAskPanel("delete_file", sheetWindow: window) { respond in
      guard respond == .alertFirstButtonReturn else { return }
      entries.forEach {
        try? FileManager.default.trashItem(at: $0.url, resultingItemURL: nil)
      }
    }
  }

  // MARK: Key event

  override func keyDown(with event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags == .command  {
      switch event.charactersIgnoringModifiers! {
      case "f":
        // window!.makeFirstResponder(historySearchField)
        break
      case "a":
        outlineView.selectAll(nil)
      case "\r":
        playInNewWindowAction(nil)
      case "l":
        showInFinderAction(nil)
      default:
        break
      }
    } else {
      let key = KeyCodeHelper.mpvKeyCode(from: event)
      switch key {
      case "DEL", "BS":
        deleteAction(nil)
      case "ENTER":
        playAction(nil)
      default:
        break
      }
    }
  }

  // MARK: NSOutlineViewDelegate

  @objc func doubleAction() {
    if let selected = outlineView.item(atRow: outlineView.clickedRow) as? PlaybackHistory {
      PlayerCore.activeOrNew.openURL(selected.url)
    }
  }

  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    return item is String
  }

  func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
    return item is String
  }

  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    if let item = item {
      return historyData[item as! String]!.count
    } else {
      return historyData.count
    }
  }

  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    if let item = item {
      return historyData[item as! String]![index]
    } else {
      return historyDataKeys[index]
    }
  }

  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    if let identifier = tableColumn?.identifier {
      guard let entry = item as? PlaybackHistory else { return nil }
      switch identifier {
      case .filename:
        let cell = (outlineView.makeView(withIdentifier: .filename, owner: nil) as? HistoryFilenameCellView) ?? HistoryFilenameCellView()
        let fileExists = !entry.url.isFileURL || FileManager.default.fileExists(atPath: entry.url.path)
        cell.textField?.stringValue = entry.url.isFileURL ? entry.name : entry.url.absoluteString
        cell.textField?.textColor = fileExists ? .controlTextColor : .disabledControlTextColor
        cell.docImage.image = Utility.icon(for: entry.url)
        return cell
      case .progress:
        // Progress cell
        let cell = (outlineView.makeView(withIdentifier: .progress, owner: nil) as? HistoryProgressCellView) ?? HistoryProgressCellView()
        // Do not animate! Causes unneeded slowdown
        cell.indicator.usesThreadedAnimation = false
        if let progress = entry.mpvProgress {
          cell.textField?.stringValue = progress.stringRepresentation
          cell.indicator.isHidden = false
          cell.indicator.doubleValue = (progress / entry.duration) ?? 0
        } else {
          cell.textField?.stringValue = ""
          cell.indicator.isHidden = true
        }
        return cell
      case .time:
        let cell = (outlineView.makeView(withIdentifier: .time, owner: nil) as? NSTableCellView) ?? makeTimeCellView()
        cell.textField?.stringValue = getTimeString(from: entry)
        return cell
      default:
        return nil
      }
    } else {
      // group columns
      let cell = (outlineView.makeView(withIdentifier: .group, owner: nil) as? NSTableCellView) ?? makeGroupCellView()
      if let key = item as? String {
        cell.textField?.stringValue = key
      }
      return cell
    }
  }

  private func makeTimeCellView() -> NSTableCellView {
    let cell = NSTableCellView()
    cell.identifier = .time
    let textField = NSTextField(labelWithString: "")
    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    cell.addSubview(textField)
    textField.padding(.leading(4), .trailing)
    textField.center(.y)
    textField.textColor = .secondaryLabelColor
    cell.textField = textField
    return cell
  }

  private func makeGroupCellView() -> NSTableCellView {
    let cell = NSTableCellView()
    cell.identifier = .group
    let textField = NSTextField(labelWithString: "")
    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.lineBreakMode = .byTruncatingTail
    cell.addSubview(textField)
    textField.padding(.leading(4), .trailing)
    textField.center(.y)
    cell.textField = textField
    return cell
  }

  private func getTimeString(from entry: PlaybackHistory) -> String {
    if groupBy == .lastPlayed {
      return DateFormatter.localizedString(from: entry.addedDate, dateStyle: .none, timeStyle: .short)
    } else {
      return DateFormatter.localizedString(from: entry.addedDate, dateStyle: .short, timeStyle: .short)
    }
  }

  // MARK: - Searching

  @objc func searchFieldAction(_ sender: NSSearchField) {
    let searchString = sender.stringValue
    guard !searchString.isEmpty else {
      reloadData()
      return
    }
    let newObjects = HistoryController.shared.$history.withLock {
      $0.filter { entry in
        let string = searchOption == .filename ? entry.name : entry.url.path
        // Do a locale-aware, case and diacritic insensitive search:
        return string.localizedStandardContains(searchString)
      }
    }
    prepareData(fromHistory: newObjects)
    outlineView.reloadData()
    outlineView.expandItem(nil, expandChildren: true)
  }

  // MARK: - Menu

  func makeContextMenu() -> NSMenu {
    let playItem = NSMenuItem(title: "Play", action: #selector(playAction(_:)), keyEquivalent: "\r")
    playItem.keyEquivalentModifierMask = []
    playItem.image = .sf("play")
    playItem.tag = MenuItemTagPlay
    let playInNewWindowItem = NSMenuItem(title: "Play in New Window", action: #selector(playInNewWindowAction(_:)), keyEquivalent: "\r")
    playInNewWindowItem.image = .sf("play.square")
    playInNewWindowItem.tag = MenuItemTagPlayInNewWindow

    let showInFinderItem = NSMenuItem(title: "Show in Finder", action: #selector(showInFinderAction(_:)), keyEquivalent: "l")
    showInFinderItem.image = .sf("finder")
    showInFinderItem.tag = MenuItemTagShowInFinder
    let deleteItem = NSMenuItem(title: "Delete…", action: #selector(deleteAction(_:)), keyEquivalent: "\u{8}")
    deleteItem.keyEquivalentModifierMask = []
    deleteItem.image = .sf("delete.backward")
    deleteItem.tag = MenuItemTagDelete
    let deleteFileItem = NSMenuItem(title: "Delete File…", action: #selector(deleteFileAction(_:)), keyEquivalent: "\u{8}")
    deleteFileItem.image = .sf("trash")
    deleteFileItem.tag = MenuItemTagDeleteFile

    let menu = NSMenu()
    menu.identifier = .contextMenu
    [playItem, playInNewWindowItem, .separator(), showInFinderItem, .separator(), deleteItem, deleteFileItem].forEach { menu.addItem($0) }
    return menu
  }

  private var selectedEntries: [PlaybackHistory] {
    var indexSet = outlineView.selectedRowIndexes
    indexSet.insert(outlineView.clickedRow)
    return indexSet.compactMap { outlineView.item(atRow: $0) as? PlaybackHistory }
  }

  private var selectedFiles: [URL] {
    if selectedEntries.isEmpty { return [] }
    return selectedEntries.map { $0.url }.filter { FileManager.default.fileExists(atPath: $0.path) }
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.tag {
    case MenuItemTagShowInFinder, MenuItemTagDeleteFile:
      return !selectedFiles.isEmpty
    case MenuItemTagDelete, MenuItemTagPlay, MenuItemTagPlayInNewWindow:
      return !selectedEntries.isEmpty
    default:
      break
    }
    return menuItem.isEnabled
  }

  // MARK: - Action

  @objc func playAction(_ sender: Any?) {
    guard !selectedFiles.isEmpty else { return }
    PlayerCore.active.openURLs(selectedFiles, shouldAutoLoad: false)
  }

  @objc func playInNewWindowAction(_ sender: Any?) {
    guard !selectedFiles.isEmpty else { return }
    PlayerCore.newPlayerCore.openURLs(selectedFiles, shouldAutoLoad: false)
  }

  @objc func showInFinderAction(_ sender: Any?) {
    guard !selectedFiles.isEmpty else { return }
    NSWorkspace.shared.activateFileViewerSelecting(selectedFiles)
  }

  @objc func deleteAction(_ sender: Any?) {
    if !selectedFiles.isEmpty {
      removeAfterConfirmation(self.selectedEntries)
    }
  }

  @objc func deleteFileAction(_ sender: Any?) {
    if !selectedFiles.isEmpty {
      removeFileAfterConfirmation(self.selectedEntries)
    }
  }

  @objc func searchInOption(_ sender: NSMenuItem) {
    searchOption = sender.tag == MenuItemTagSearchFilename ? .filename : .fullPath
  }

  @objc func groupByChangedAction(_ sender: NSSegmentedControl) {
    groupBy = SortOption(rawValue: sender.selectedTag()) ?? .lastPlayed
    reloadData()
  }
}

// MARK: - Toolbar

extension HistoryWindowController: NSToolbarDelegate {
  private static let groupBy = NSToolbarItem.Identifier("GrouopBy")
  private static let searchField = NSToolbarItem.Identifier("SearchField")
  private static let toolbarItems = [groupBy, .flexibleSpace, searchField]

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    Self.toolbarItems
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    Self.toolbarItems
  }

  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
    switch itemIdentifier {
    case Self.groupBy:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Group By"
      let segmentedControl = NSSegmentedControl(labels: ["Date", "Folder"], trackingMode: .selectOne, target: self, action: #selector(groupByChangedAction(_:)))
      segmentedControl.setTag(SortOption.lastPlayed.rawValue, forSegment: 0)
      segmentedControl.setTag(SortOption.fileLocation.rawValue, forSegment: 1)
      segmentedControl.selectedSegment = 0
      item.view = segmentedControl
      return item

    case Self.searchField:
      let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
      item.preferredWidthForSearchField = 100
      let searchField = item.searchField
      searchField.target = self
      searchField.action = #selector(searchFieldAction(_:))
      searchField.searchMenuTemplate = makeSearchMenu()
      searchField.recentsAutosaveName = "IINAHistorySearchField"
      return item

    default: return nil
    }
  }

  func makeSearchMenu() -> NSMenu {
    let searchIn: NSMenuItem
    if #available(macOS 14, *) {
      searchIn = NSMenuItem.sectionHeader(title: "Search in")
    } else {
      searchIn = NSMenuItem(title: "Search in", action: nil, keyEquivalent: "")
      searchIn.isEnabled = false
    }

    let filenameItem = NSMenuItem(title: "Filename", action: #selector(searchInOption(_:)), keyEquivalent: "")
    filenameItem.tag = MenuItemTagSearchFilename
    filenameItem.target = self
    filenameItem.image = .sf("document")

    let fullPathItem = NSMenuItem(title: "Full Path", action: #selector(searchInOption(_:)), keyEquivalent: "")
    fullPathItem.tag = MenuItemTagSearchFullPath
    fullPathItem.target = self
    fullPathItem.image = .sf("folder")

    if #unavailable(macOS 14) {
      [filenameItem, fullPathItem].forEach { $0.indentationLevel = 1 }
    }

    // Managed by AppKit; placeholders
    let noRecents = NSMenuItem(title: "No Recent Searches", action: nil, keyEquivalent: "")
    noRecents.tag = NSSearchField.noRecentsMenuItemTag
    noRecents.isEnabled = false
    let recentsTitle = NSMenuItem(title: "Recent Searches", action: nil, keyEquivalent: "")
    recentsTitle.tag = NSSearchField.recentsTitleMenuItemTag
    recentsTitle.isEnabled = false
    let recentItem = NSMenuItem(title: "Item", action: nil, keyEquivalent: "")
    recentItem.tag = NSSearchField.recentsMenuItemTag
    if #unavailable(macOS 14) {
      recentItem.indentationLevel = 1
    }
    let clear = NSMenuItem(title: "Clear Recents", action: nil, keyEquivalent: "")
    clear.tag = NSSearchField.clearRecentsMenuItemTag
    clear.image = .sf("trash")

    let menu = NSMenu()
    [searchIn, filenameItem, fullPathItem, .separator(), noRecents, recentsTitle, recentItem, .separator(), clear].forEach { menu.addItem($0) }

    return menu
  }
}

// MARK: - Other classes

class HistoryFilenameCellView: NSTableCellView {
  let docImage = NSImageView()

  init() {
    super.init(frame: .zero)
    self.identifier = .filename

    docImage.translatesAutoresizingMaskIntoConstraints = false
    docImage.imageScaling = .scaleProportionallyDown
    addSubview(docImage)

    let textField = NSTextField(labelWithString: "")
    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.lineBreakMode = .byTruncatingMiddle
    addSubview(textField)
    self.textField = textField

    docImage.size(width: 18, height: 18)
    docImage.padding(.leading)
    docImage.spacing(.trailing(4), to: textField)
    textField.padding(.trailing)
    [docImage, textField].forEach { $0.center(.y) }
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

class HistoryProgressCellView: NSTableCellView {
  let indicator = NSProgressIndicator()

  init() {
    super.init(frame: .zero)
    self.identifier = .progress

    indicator.translatesAutoresizingMaskIntoConstraints = false
    indicator.userInterfaceLayoutDirection = .leftToRight
    let textField = NSTextField(labelWithString: "")
    textField.translatesAutoresizingMaskIntoConstraints = false
    self.textField = textField
    addSubview(indicator)
    addSubview(textField)

    [indicator, textField].forEach { $0.center(.y) }
    indicator.padding(.leading)
    indicator.widthAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
    indicator.spacing(.trailing(6), to: textField)
    textField.padding(.trailing)
  }
  
  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
