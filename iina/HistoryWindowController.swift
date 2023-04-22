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

  override var windowNibName: NSNib.Name {
    return NSNib.Name("HistoryWindowController")
  }

  @IBOutlet weak var outlineView: NSOutlineView!
  @IBOutlet weak var historySearchField: NSSearchField!

  var groupBy: SortOption = .lastPlayed
  var searchOption: SearchOption = .fullPath

  private var historyData: [String: [PlaybackHistory]] = [:]
  private var historyDataKeys: [String] = []

  override func windowDidLoad() {
    super.windowDidLoad()

    NotificationCenter.default.addObserver(forName: .iinaHistoryUpdated, object: nil, queue: .main) { [unowned self] _ in
      self.reloadData()
    }

    prepareData()
    outlineView.delegate = self
    outlineView.dataSource = self
    outlineView.menu?.delegate = self
    outlineView.target = self
    outlineView.doubleAction = #selector(doubleAction)
    outlineView.expandItem(nil, expandChildren: true)
    AccessibilityPreferences.adjustElasticityInSubviews(outlineView)
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

  // MARK: Key event

  override func keyDown(with event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags == .command  {
      switch event.charactersIgnoringModifiers! {
      case "f":
        window!.makeFirstResponder(historySearchField)
      case "a":
        outlineView.selectAll(nil)
      default:
        break
      }
    } else {
      let key = KeyCodeHelper.mpvKeyCode(from: event)
      if key == "DEL" || key == "BS" {
        let entries = outlineView.selectedRowIndexes.compactMap { outlineView.item(atRow: $0) as? PlaybackHistory }
        removeAfterConfirmation(entries)
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

  func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
    if let entry = item as? PlaybackHistory {
      if tableColumn?.identifier == .time {
        return getTimeString(from: entry)
      } else if tableColumn?.identifier == .progress {
        return entry.duration.stringRepresentation
      }
    }
    return item
  }

  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    if let identifier = tableColumn?.identifier {
      guard let cell: NSTableCellView = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView else { return nil }
      guard let entry = item as? PlaybackHistory else { return cell }
      if identifier == .filename {
        // Filename cell
        let filenameView = cell as! HistoryFilenameCellView
        let fileExists = !entry.url.isFileURL || FileManager.default.fileExists(atPath: entry.url.path)
        filenameView.textField?.stringValue = entry.url.isFileURL ? entry.name : entry.url.absoluteString
        filenameView.textField?.textColor = fileExists ? .controlTextColor : .disabledControlTextColor
        filenameView.docImage.image = NSWorkspace.shared.icon(forFileType: entry.url.pathExtension)
      } else if identifier == .progress {
        // Progress cell
        let progressView = cell as! HistoryProgressCellView
        // Do not animate! Causes unneeded slowdown
        progressView.indicator.usesThreadedAnimation = false
        if let progress = entry.mpvProgress {
          progressView.textField?.stringValue = progress.stringRepresentation
          progressView.indicator.isHidden = false
          progressView.indicator.doubleValue = (progress / entry.duration) ?? 0
        } else {
          progressView.textField?.stringValue = ""
          progressView.indicator.isHidden = true
        }
      }
      return cell
    } else {
      // group columns
      return outlineView.makeView(withIdentifier: .group, owner: nil)
    }
  }

  private func getTimeString(from entry: PlaybackHistory) -> String {
    if groupBy == .lastPlayed {
      return DateFormatter.localizedString(from: entry.addedDate, dateStyle: .none, timeStyle: .short)
    } else {
      return DateFormatter.localizedString(from: entry.addedDate, dateStyle: .short, timeStyle: .short)
    }
  }

  // MARK: - Searching

  @IBAction func searchFieldAction(_ sender: NSSearchField) {
    let searchString = sender.stringValue
    guard !searchString.isEmpty else {
      reloadData()
      return
    }
    let newObjects = HistoryController.shared.history.filter { entry in
      let string = searchOption == .filename ? entry.name : entry.url.path
      // Do a locale-aware, case and diacritic insensitive search:
      return string.localizedStandardContains(searchString)
    }
    prepareData(fromHistory: newObjects)
    outlineView.reloadData()
    outlineView.expandItem(nil, expandChildren: true)
  }

  // MARK: - Menu

  private var selectedEntries: [PlaybackHistory] = []

  func menuNeedsUpdate(_ menu: NSMenu) {
    let selectedRowIndexes = outlineView.selectedRowIndexes
    let clickedRow = outlineView.clickedRow
    var indexSet = IndexSet()
    if menu.identifier == .contextMenu {
      if clickedRow != -1 {
        if selectedRowIndexes.contains(clickedRow) {
          indexSet = selectedRowIndexes
        } else {
          indexSet.insert(clickedRow)
        }
      }
      selectedEntries = indexSet.compactMap { outlineView.item(atRow: $0) as? PlaybackHistory }
    }
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.tag {
    case MenuItemTagShowInFinder:
      if selectedEntries.isEmpty { return false }
      return selectedEntries.contains { FileManager.default.fileExists(atPath: $0.url.path) }
    case MenuItemTagDelete, MenuItemTagPlay, MenuItemTagPlayInNewWindow:
      return !selectedEntries.isEmpty
    case MenuItemTagSearchFilename:
      menuItem.state = searchOption == .filename ? .on : .off
    case MenuItemTagSearchFullPath:
      menuItem.state = searchOption == .fullPath ? .on : .off
    default:
      break
    }
    return menuItem.isEnabled
  }

  // MARK: - IBActions

  @IBAction func playAction(_ sender: AnyObject) {
    guard let firstEntry = selectedEntries.first else { return }
    PlayerCore.active.openURL(firstEntry.url)
  }

  @IBAction func playInNewWindowAction(_ sender: AnyObject) {
    guard let firstEntry = selectedEntries.first else { return }
    PlayerCore.newPlayerCore.openURL(firstEntry.url)
  }

  @IBAction func groupByChangedAction(_ sender: NSPopUpButton) {
    groupBy = SortOption(rawValue: sender.selectedTag()) ?? .lastPlayed
    reloadData()
  }

  @IBAction func showInFinderAction(_ sender: AnyObject) {
    let urls = selectedEntries.compactMap { FileManager.default.fileExists(atPath: $0.url.path) ? $0.url: nil }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }

  @IBAction func deleteAction(_ sender: AnyObject) {
    removeAfterConfirmation(self.selectedEntries)
  }

  @IBAction func searchOptionFilenameAction(_ sender: AnyObject) {
    searchOption = .filename
  }

  @IBAction func searchOptionFullPathAction(_ sender: AnyObject) {
    searchOption = .fullPath
  }

}


// MARK: - Other classes

class HistoryFilenameCellView: NSTableCellView {

  @IBOutlet var docImage: NSImageView!

}

class HistoryProgressCellView: NSTableCellView {

  @IBOutlet var indicator: NSProgressIndicator!

}
