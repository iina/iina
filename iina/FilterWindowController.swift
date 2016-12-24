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
  
  var observers: [NSObjectProtocol] = []
  
  @IBOutlet weak var tableView: NSTableView!
  
  override func windowDidLoad() {
    super.windowDidLoad()
    
    filters = PlayerCore.shared.mpvController.getFilters("vf")
    tableView.delegate = self
    tableView.dataSource = self
    
    // notifications
    let vfChangeObserver = NotificationCenter.default.addObserver(forName: Constants.Noti.vfChanged, object: nil, queue: OperationQueue.main) { _ in
      self.reloadTable()
    }
    observers.append(vfChangeObserver)
  }
  
  func reloadTable() {
    filters = PlayerCore.shared.mpvController.getFilters("vf")
    tableView.reloadData()
  }
  
  func setFilters() {
    PlayerCore.shared.mpvController.setFilters("vf", filters: filters)
  }
  
  deinit {
    observers.forEach {
      NotificationCenter.default.removeObserver($0)
    }
  }
  
  // MARK: - IBAction
  
  @IBAction func addFilterAction(_ sender: AnyObject) {
    let _ = Utility.quickPromptPanel(messageText: "Add filter", informativeText: "Please enter a filter string in format of MPV's vf command.") { str in
      if let newFilter = MPVFilter(rawString: str) {
        filters.append(newFilter)
        setFilters()
      } else {
        Utility.showAlert(message: "Filter is not in correct format!")
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
      setFilters()
    } else {
      Utility.showAlert(message: "Filter is not in correct format!")
    }
  }
  
}
