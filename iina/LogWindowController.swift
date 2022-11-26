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
  let logString: String

  init(subsystem: String, level: Int, message: String, date: String, logString: String) {
    self.subsystem = subsystem
    self.level = level
    self.message = message
    self.date = date
    self.logString = logString
  }

  override var description: String {
      return logString
  }
}

class LogWindowController: NSWindowController, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
  override var windowNibName: NSNib.Name {
    return NSNib.Name("LogWindowController")
  }

  @IBOutlet weak var logTableView: NSTableView!
  @IBOutlet var logArrayController: NSArrayController!
  @IBOutlet weak var subsystemPopUpButton: NSPopUpButton!
  @IBOutlet weak var levelPopUpButton: NSPopUpButton!

  @objc dynamic var logs: [Log] = []
  @objc dynamic var predicate = NSPredicate(value: true)

  override func windowDidLoad() {
    super.windowDidLoad()

    logTableView.sizeLastColumnToFit()
    subsystemPopUpButton.menu!.delegate = self
    subsystemPopUpButton.selectItem(withTag: Preference.integer(for: .logLevel))
  }

  // NSMenuDelegate

  func menuNeedsUpdate(_ menu: NSMenu) {
    Logger.Subsystem.subsystems.forEach {
      if !$0.added {
        menu.addItem(withTitle: $0.rawValue)
        $0.added = true
      }
    }
  }

  private func updatePredicate() {
    var subsystemPredicate = NSPredicate(value: true)
    if subsystemPopUpButton.indexOfSelectedItem != 0 {
      subsystemPredicate = NSPredicate(format: "subsystem = %@", subsystemPopUpButton.titleOfSelectedItem!)
    }
    let levelPredicate = NSPredicate(format: "level >= %d", levelPopUpButton.selectedTag())
    predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [subsystemPredicate, levelPredicate])
  }

  @IBAction func subsystemUpdated(_ sender: Any) {
    updatePredicate()
  }

  @IBAction func save(_ sender: Any) {
    Utility.quickSavePanel(title: "Log", filename: "log.txt", sheetWindow: window) { URL in
      var logs = ""
      (self.logArrayController.arrangedObjects as? [Log])!.forEach {
        logs += $0.logString
      }
      do {
        try logs.write(to: URL, atomically: true, encoding: .utf8)
      } catch {}
    }
  }

}
