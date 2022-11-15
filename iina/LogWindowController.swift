//
//  LogWindowController.swift
//  iina
//
//  Created by Yuze Jiang on 2022/11/10.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class Log: NSObject {
  @objc dynamic let subsystem: String
  @objc dynamic let level: Int
  @objc dynamic let message: String
  @objc dynamic let date: String

  init(subsystem: String, level: Int, message: String, date: String) {
    self.subsystem = subsystem
    self.level = level
    self.message = message
    self.date = date
  }
}

class LogWindowController: NSWindowController, NSTableViewDelegate, NSTableViewDataSource {
  override var windowNibName: NSNib.Name {
    return NSNib.Name("LogWindowController")
  }

  convenience init() {
    self.init(windowNibName: "LogWindowController")
  }

  @IBOutlet weak var logTableView: NSTableView!
  @IBOutlet weak var subsystemPopUpButton: NSPopUpButton!

  @objc dynamic var logs: [Log] = []
//  private static var subsystems = Set<Logger.Subsystem>()

  override func windowWillLoad() {
    super.windowWillLoad()
  }

  override func windowDidLoad() {
    super.windowDidLoad()

//    NotificationCenter.default.addObserver(self, selector: #selector(updateLog), name: .iinaNewLog, object: nil)

//    updateSubsystems()
    logTableView.sizeLastColumnToFit()
  }

//  func updateSubsystems()
//  {
//    DispatchQueue.main.async { [unowned self] in
//      guard isWindowLoaded else { return }
//      subsystemPopupButton.removeAllItems()
//      subsystemPopupButton.addItem(withTitle: NSLocalizedString("All", comment: "All"))
//      subsystemPopupButton.addItems(withTitles: Logger.subsystems.map { $0.rawValue })
//    }
//  }

//  // NSTableViewDataSource
//  func numberOfRows(in tableView: NSTableView) -> Int {
//    return Logger.logs.count
//  }
//
//  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
//    return Logger.logs[row]
//  }
//
//  // NSTableViewDelegate
//  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
//    let log = Logger.logs[row]
//
//    guard let column = tableColumn,
//          let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? NSTableCellView else { return nil }
//
//    switch column.identifier.rawValue {
//    case "subsystem":
//      cell.textField?.stringValue = log.subsystem.rawValue
//    case "message":
//      cell.textField?.stringValue = log.message
//    case "time":
//      cell.textField?.stringValue = Logger.dateFormatter.string(from: log.date)
//    case "level":
//      cell.imageView!.wantsLayer = true
//      let colorDict: [Logger.Level: CGColor] =
//      [
//        .verbose: NSColor.lightGray.cgColor,
//        .debug: NSColor.green.cgColor,
//        .warning: NSColor.yellow.cgColor,
//        .error: NSColor.red.cgColor,
//      ]
//      cell.imageView!.layer?.backgroundColor = colorDict[log.level]
//    default:
//      break
//    }
//    return cell
//  }
//
}
