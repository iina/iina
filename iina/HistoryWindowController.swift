//
//  HistoryWindowController.swift
//  iina
//
//  Created by lhc on 28/4/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class HistoryWindowController: NSWindowController, NSOutlineViewDelegate, NSOutlineViewDataSource, NSMenuDelegate {

  enum SortBy {
    case lastPlayed, fileLocation
  }

  private let getKey: [SortBy: (PlaybackHistory) -> String] = [
    .lastPlayed: { HistoryWindowController.dateFormatterDate.string(from: $0.addedDate) },
    .fileLocation: { $0.url.path }
  ]

  override var windowNibName: String {
    return "HistoryWindowController"
  }

  @IBOutlet weak var outlineView: NSOutlineView!

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

  var sortBy: SortBy = .lastPlayed

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
    outlineView.expandItem(nil, expandChildren: true)
  }

  func reloadData() {
    prepareData()
    outlineView.reloadData()
  }

  private func prepareData() {
    // reconstruct data
    historyData.removeAll()
    historyDataKeys.removeAll()

    for entry in HistoryController.shared.history {
      addToData(entry, forKey: getKey[sortBy]!(entry))
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
    if tableColumn?.identifier == "Time", item is PlaybackHistory {
      return HistoryWindowController.dateFormatterTime.string(from: (item as! PlaybackHistory).addedDate)
    }
    return item
  }

  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    if let identifier = tableColumn?.identifier {
      let view = outlineView.make(withIdentifier: identifier, owner: nil)
      if identifier == "Filename" {
        let entry = item as! PlaybackHistory
        let filenameView = (view as! HistoryFilenameCellView)
        filenameView.textField?.stringValue = entry.name
        filenameView.docImage.image = NSWorkspace.shared().icon(forFileType: entry.url.pathExtension)
      }
      return view
    } else {
      // group columns
      return outlineView.make(withIdentifier: "Group", owner: nil)
    }
  }

  // MARK: - Context menu

  private var selectedEntries: [PlaybackHistory] = []

  func menuNeedsUpdate(_ menu: NSMenu) {
    var indexSet = outlineView.selectedRowIndexes
    if outlineView.clickedRow >= 0 {
      indexSet.insert(outlineView.clickedRow)
    }

    selectedEntries = indexSet.flatMap { outlineView.item(atRow: $0) as? PlaybackHistory }
  }

  // MARK: - IBActions

  @IBAction func revealInFinderAction(_ sender: AnyObject) {
    let urls = selectedEntries.map { $0.url }
    NSWorkspace.shared().activateFileViewerSelecting(urls)
  }

  @IBAction func deleteAction(_ sender: AnyObject) {
    if Utility.quickAskPanel("delete_history") {
      
    }
  }

}


class HistoryFilenameCellView: NSTableCellView {

  @IBOutlet var docImage: NSImageView!

}
