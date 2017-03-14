//
//  SubSelectWindowController.swift
//  iina
//
//  Created by lhc on 13/3/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class SubSelectWindowController: NSWindowController, NSWindowDelegate {

  override var windowNibName: String {
    return "SubSelectWindowController"
  }

  @IBOutlet var arrayController: NSArrayController!

  var whenUserAction: (([OpenSubSubtitle]) -> Void)?
  var whenUserClosed: (() -> Void)?

  private var userActionDone = false

  override func windowDidLoad() {
    super.windowDidLoad()
    window?.appearance = NSAppearance(named: NSAppearanceNameVibrantDark)
  }

  func windowWillClose(_ notification: Notification) {
    guard !userActionDone else { return }
    guard let whenUserClosed = whenUserClosed else { return }
    whenUserClosed()
  }
  
  @IBAction func downloadBtnAction(_ sender: Any) {
    guard let whenUserAction = whenUserAction else { return }
    userActionDone = true
    whenUserAction(arrayController.selectedObjects as! [OpenSubSubtitle])
    self.close()
  }

}
