//
//  HistoryWindowController.swift
//  iina
//
//  Created by lhc on 28/4/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class HistoryWindowController: NSWindowController, NSOutlineViewDelegate, NSOutlineViewDataSource, NSMenuDelegate {

  enum SortOption: Int {
    case lastPlayed = 0
    case fileLocation
  }

  enum SearchOption {
    case filename, fullPath
  }

  private let getKey: [SortOption: (PlaybackHistory) -> String] = [
    .lastPlayed: { HistoryWindowController.dateFormatterDate.string(from: $0.addedDate) },
    .fileLocation: { $0.url.deletingLastPathComponent().path }
  ]

  override var windowNibName: String {
    return "HistoryWindowController"
  }

  @IBOutlet weak var outlineView: NSOutlineView!
  @IBOutlet weak var historySearchField: NSSearchField!

  private static let dateFormatterDate: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd"
    return formatter
  }()

  private static let dateFormatterTime: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
  }()

  private static let dateFormatterDateAndTime: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter
  }()

  var groupBy: SortOption = .lastPlayed
  var searchOption: SearchOption = .fullPath

  private var historyData: [String: [PlaybackHistory]] = [:]
  private var historyDataKeys: [String] = []

  override func windowDidLoad() {
    super.windowDidLoad()

    NotificationCenter.default.addObserver(forName: Constants.Noti.historyUpdated, object: nil, queue: .main) { [unowned self] _ in
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

  // MARK: NSOutlineViewDelegate

  func doubleAction() {
    if let selected = outlineView.item(atRow: outlineView.clickedRow) as? PlaybackHistory {
      PlayerCore.shared.openFile(selected.url)
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
      if tableColumn?.identifier == "Time" {
        let formatter = groupBy == .lastPlayed ? HistoryWindowController.dateFormatterTime : HistoryWindowController.dateFormatterDateAndTime
        return formatter.string(from: entry.addedDate)
      } else if tableColumn?.identifier == "Progress" {
        return entry.duration.stringRepresentation
      }
    }
    return item
  }

  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    if let identifier = tableColumn?.identifier {
      let view = outlineView.make(withIdentifier: identifier, owner: nil)
      if identifier == "Filename" {
        // Filename cell
        let entry = item as! PlaybackHistory
        let filenameView = (view as! HistoryFilenameCellView)
        filenameView.textField?.stringValue = entry.name
        filenameView.docImage.image = NSWorkspace.shared().icon(forFileType: entry.url.pathExtension)
      } else if identifier == "Progress" {
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
      return outlineView.make(withIdentifier: "Group", owner: nil)
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
    if menu.identifier == "ContextMenu" {
      var indexSet = outlineView.selectedRowIndexes
      if outlineView.clickedRow >= 0 {
        indexSet.insert(outlineView.clickedRow)
      }
      selectedEntries = indexSet.flatMap { outlineView.item(atRow: $0) as? PlaybackHistory }
    }
  }
  override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.tag == 200 {
      menuItem.state = searchOption == .filename ? NSOnState : NSOffState
    } else if menuItem.tag == 201 {
      menuItem.state = searchOption == .fullPath ? NSOnState : NSOffState
    }
    return menuItem.isEnabled
  }

  // MARK: - IBActions

  @IBAction func groupByChangedAction(_ sender: NSPopUpButton) {
    groupBy = SortOption(rawValue: sender.selectedTag()) ?? .lastPlayed
    reloadData()
  }

  @IBAction func revealInFinderAction(_ sender: AnyObject) {
    let urls = selectedEntries.map { $0.url }
    NSWorkspace.shared().activateFileViewerSelecting(urls)
  }

  @IBAction func deleteAction(_ sender: AnyObject) {
    if Utility.quickAskPanel("delete_history") {
      for entry in selectedEntries {
        HistoryController.shared.remove(entry)
      }
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
