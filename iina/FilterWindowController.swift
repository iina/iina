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

  override func windowDidLoad() {
    super.windowDidLoad()

    // title
    window?.title = filterType == MPVProperty.af ? NSLocalizedString("filter.audio_filters", comment: "Audio Filters") : NSLocalizedString("filter.video_filters", comment: "Video Filters")

    filters = PlayerCore.active.mpvController.getFilters(filterType)
    tableView.delegate = self
    tableView.dataSource = self

    // notifications
    let notiName = filterType == MPVProperty.af ? Constants.Noti.afChanged : Constants.Noti.vfChanged
    NotificationCenter.default.addObserver(self, selector: #selector(reloadTable), name: notiName, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(reloadTable), name: Constants.Noti.mainWindowChanged, object: nil)
  }

  @objc
  func reloadTable() {
    filters = PlayerCore.active.mpvController.getFilters(filterType)
    tableView.reloadData()
  }

  func setFilters() {
    PlayerCore.active.mpvController.setFilters(filterType, filters: filters)
  }

  deinit {
    ObjcUtils.silenced {
      NotificationCenter.default.removeObserver(self)
    }
  }

  // MARK: - IBAction

  @IBAction func addFilterAction(_ sender: AnyObject) {
    let _ = Utility.quickPromptPanel("add_filter") { str in
      if let newFilter = MPVFilter(rawString: str) {
        filters.append(newFilter)
        setFilters()
      } else {
        Utility.showAlert("filter.incorrect")
      }
    }
  }

  @IBAction func removeFilterAction(_ sender: AnyObject) {
    if tableView.selectedRow >= 0 {
      filters.remove(at: tableView.selectedRow)
      setFilters()
    }
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
