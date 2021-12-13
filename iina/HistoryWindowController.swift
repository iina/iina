//
//  HistoryWindowController.swift
//  iina
//
//  Created by lhc on 28/4/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

fileprivate let MenuItemTagRevealInFinder = 100
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
  }

  func reloadData() {
    prepareData()
    outlineView.reloadData()
    outlineView.expandItem(nil, expandChildren: true)
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

  // MARK: Key event

  override func keyDown(with event: NSEvent) {
    let commandKey = NSEvent.ModifierFlags.command
    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == commandKey  {
      switch event.charactersIgnoringModifiers! {
      case "f":
        window!.makeFirstResponder(historySearchField)
      case "a":
        outlineView.selectAll(nil)
      default:
        break
      }
    } else if event.charactersIgnoringModifiers == "\u{7f}" {
      let entries = outlineView.selectedRowIndexes.compactMap { outlineView.item(atRow: $0) as? PlaybackHistory }
      HistoryController.shared.remove(entries)
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
        return groupBy == .lastPlayed ?
          DateFormatter.localizedString(from: entry.addedDate, dateStyle: .none, timeStyle: .short) :
          DateFormatter.localizedString(from: entry.addedDate, dateStyle: .short, timeStyle: .short)
      } else if tableColumn?.identifier == .progress {
        return entry.duration.stringRepresentation
      }
    }
    return item
  }

  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    if let identifier = tableColumn?.identifier {
      let view = outlineView.makeView(withIdentifier: identifier, owner: nil)
      if identifier == .filename {
        // Filename cell
        let entry = item as! PlaybackHistory
        let filenameView = (view as! HistoryFilenameCellView)
        let fileExists = !entry.url.isFileURL || FileManager.default.fileExists(atPath: entry.url.path)
        filenameView.textField?.stringValue = entry.url.isFileURL ? entry.name : entry.url.absoluteString
        filenameView.textField?.textColor = fileExists ? .controlTextColor : .disabledControlTextColor
        filenameView.docImage.image = NSWorkspace.shared.icon(forFileType: entry.url.pathExtension)
      } else if identifier == .progress {
        // Progress cell
        let entry = item as! PlaybackHistory
        let filenameView = (view as! HistoryProgressCellView)
        if let progress = entry.mpvProgress {
          filenameView.textField?.stringValue = progress.stringRepresentation
          filenameView.indicator.isHidden = false
          filenameView.indicator.doubleValue = (progress / entry.duration) ?? 0
        } else {
          filenameView.textField?.stringValue = ""
          filenameView.indicator.isHidden = true
        }
      }
      return view
    } else {
      // group columns
      return outlineView.makeView(withIdentifier: .group, owner: nil)
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
      return string.lowercased().contains(searchString)
    }
    prepareData(fromHistory: newObjects)
    outlineView.reloadData()
    outlineView.expandItem(nil, expandChildren: true)
  }

  // MARK: - Menu

  private var selectedEntries: [PlaybackHistory] = []

  func menuNeedsUpdate(_ menu: NSMenu) {
    let selectedRow = outlineView.selectedRowIndexes
    let clickedRow = outlineView.clickedRow
    var indexSet = IndexSet()
    if menu.identifier == .contextMenu {
      if clickedRow != -1 {
        if selectedRow.contains(clickedRow) {
          indexSet = selectedRow
        } else {
          indexSet.insert(clickedRow)
        }
      }
      selectedEntries = indexSet.compactMap { outlineView.item(atRow: $0) as? PlaybackHistory }
    }
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.tag {
    case MenuItemTagRevealInFinder:
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

  @IBAction func revealInFinderAction(_ sender: AnyObject) {
    let urls = selectedEntries.compactMap { FileManager.default.fileExists(atPath: $0.url.path) ? $0.url: nil }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }

  @IBAction func deleteAction(_ sender: AnyObject) {
    Utility.quickAskPanel("delete_history", sheetWindow: window) { respond in
      guard respond == .alertFirstButtonReturn else { return }
      HistoryController.shared.remove(self.selectedEntries)
    }
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
