//
//  PrefGeneralViewController.swift
//  iina
//
//  Created by lhc on 27/10/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import MASPreferences
import Sparkle

@objcMembers
class PrefGeneralViewController: NSViewController, MASPreferencesViewController {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefGeneralViewController")
  }

  var viewIdentifier: String = "PrefGeneralViewController"

  var toolbarItemImage: NSImage? {
    return NSImage(named: .preferencesGeneral)!
  }

  var toolbarItemLabel: String? {
    // dirty hack here: layout the view before `MASPreferencesWIndowController` getting `bounds`.
    view.layoutSubtreeIfNeeded()
    return NSLocalizedString("preference.general", comment: "General")
  }

  // view size is handled by AutoLayout, so it's not resizable
  var hasResizableWidth: Bool = false
  var hasResizableHeight: Bool = false

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do view setup here.
  }

  // MARK: - IBAction

  @IBAction func chooseScreenshotPathAction(_ sender: AnyObject) {
    Utility.quickOpenPanel(title: "Choose screenshot save path", isDir: true) { url in
      Preference.set(url.path, for: .screenshotFolder)
      UserDefaults.standard.synchronize()
    }
  }

  @IBAction func rememberRecentChanged(_ sender: NSButton) {
    if sender.state == .off {
      NSDocumentController.shared.clearRecentDocuments(self)
    }
  }

  @IBAction func receiveBetaUpdatesChanged(_ sender: NSButton) {
    SUUpdater.shared().feedURL = URL(string: sender.state == .on ? AppData.appcastBetaLink : AppData.appcastLink)!
  }

}
