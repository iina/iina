//
//  FilterWindowController.swift
//  iina
//
//  Created by lhc on 25/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class FilterWindowController: NSWindowController {

  override var windowNibName: String {
    return "FilterWindowController"
  }

  var filterType: String!

  var filters: [MPVFilter] = []

  @IBOutlet weak var tableView: NSTableView!
  @IBOutlet var newFilterSheet: NSWindow!

  override func windowDidLoad() {
    super.windowDidLoad()

    // title
    window?.title = filterType == MPVProperty.af ? NSLocalizedString("filter.audio_filters", comment: "Audio Filters") : NSLocalizedString("filter.video_filters", comment: "Video Filters")

    filters = PlayerCore.active.mpv.getFilters(filterType)
    tableView.delegate = self
    tableView.dataSource = self

    // notifications
    let notiName = filterType == MPVProperty.af ? Constants.Noti.afChanged : Constants.Noti.vfChanged
    NotificationCenter.default.addObserver(self, selector: #selector(reloadTable), name: notiName, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(reloadTable), name: Constants.Noti.mainWindowChanged, object: nil)
  }

  @objc
  func reloadTable() {
    filters = PlayerCore.active.mpv.getFilters(filterType)
    tableView.reloadData()
  }

  func setFilters() {
    PlayerCore.active.mpv.setFilters(filterType, filters: filters)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - IBAction

  @IBAction func addFilterAction(_ sender: AnyObject) {
//    let _ = Utility.quickPromptPanel("add_filter", mode: .sheetModal, sheetWindow: window) { str in
//      if let newFilter = MPVFilter(rawString: str) {
//        self.filters.append(newFilter)
//        self.setFilters()
//      } else {
//        Utility.showAlert("filter.incorrect")
//      }
//    }

    window!.beginSheet(newFilterSheet) { response in
      print(response)
    }
  }

  @IBAction func removeFilterAction(_ sender: AnyObject) {
    if tableView.selectedRow >= 0 {
      filters.remove(at: tableView.selectedRow)
      setFilters()
    }
  }

  @IBAction func sheetAddBtnAction(_ sender: Any) {
    window!.endSheet(newFilterSheet, returnCode: NSModalResponseOK)
  }

  @IBAction func sheetCancelBtnAction(_ sender: Any) {
    window!.endSheet(newFilterSheet, returnCode: NSModalResponseCancel)
  }
}

extension FilterWindowController: NSTableViewDelegate, NSTableViewDataSource {

  func numberOfRows(in tableView: NSTableView) -> Int {
    return filters.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    guard let filter = filters.at(row) else { return nil }
    if tableColumn?.identifier == Constants.Identifier.key {
      return row.toStr()
    } else if tableColumn?.identifier == Constants.Identifier.value {
      return filter.stringFormat
    }
    return ""
  }

  func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
    guard let value = object as? String, tableColumn?.identifier == Constants.Identifier.value else { return }

    if let newFilter = MPVFilter(rawString: value) {
      filters[row] = newFilter
      setFilters()
    } else {
      Utility.showAlert("filter.incorrect")
    }
  }

}


class NewFilterSheetViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {

  @IBOutlet weak var filterWindow: NSWindowController!
  @IBOutlet weak var tableView: NSTableView!

  override func awakeFromNib() {
    tableView.dataSource = self
    tableView.delegate = self
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    return FilterPreset.presets.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    return FilterPreset.presets.at(row)?.name
  }
}
