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
  
  var filters: [MPVFilter] = []
  
  @IBOutlet weak var tableView: NSTableView!
  
  override func windowDidLoad() {
    super.windowDidLoad()
    
    filters = PlayerCore.shared.mpvController.getFilters("vf")
    tableView.delegate = self
    tableView.dataSource = self
  }
  
  func reloadTable() {
    filters = PlayerCore.shared.mpvController.getFilters("vf")
    tableView.reloadData()
  }
  
}

extension FilterWindowController: NSTableViewDelegate, NSTableViewDataSource {
  
  func numberOfRows(in tableView: NSTableView) -> Int {
    return filters.count
  }
  
  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    let filter = filters[row]
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
      PlayerCore.shared.mpvController.setFilters("vf", filters: filters)
    }
  }
  
}
