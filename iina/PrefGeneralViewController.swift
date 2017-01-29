//
//  PreferenceGeneralViewController.swift
//  iina
//
//  Created by lhc on 27/10/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import MASPreferences


class PrefGeneralViewController: NSViewController, MASPreferencesViewController {

  override var nibName: String? {
    get {
      return "PrefGeneralViewController"
    }
  }

  override var identifier: String? {
    get {
      return "general"
    }
    set {
      super.identifier = newValue
    }
  }

  var toolbarItemImage: NSImage {
    get {
      return NSImage(named: NSImageNamePreferencesGeneral)!
    }
  }

  var toolbarItemLabel: String {
    get {
      // dirty hack here: layout the view before `MASPreferencesWIndowController` getting `bounds`.
      view.layoutSubtreeIfNeeded()
      return NSLocalizedString("preference.general", comment: "General")
    }
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
    let _ = Utility.quickOpenPanel(title: "Choose screenshot save path", isDir: true) {
      url in
      UserDefaults.standard.set(url.path, forKey: Preference.Key.screenshotFolder)
      UserDefaults.standard.synchronize()
    }
  }

  @IBAction func rememberRecentChanged(_ sender: NSButton) {
    if sender.state == NSOffState {
      NSDocumentController.shared().clearRecentDocuments(self)
    }
  }


}
