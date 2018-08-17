//
//  PrefGeneralViewController.swift
//  iina
//
//  Created by lhc on 27/10/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import Sparkle

@objcMembers
class PrefGeneralViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    get {
      return NSNib.Name("PrefGeneralViewController")
    }
  }

  var preferenceTabTitle: String {
    get {
      return NSLocalizedString("preference.general", comment: "General")
    }
  }

  override var sectionViews: [NSView] {
    return [behaviorView, historyView, playlistView, screenshotsView]
  }

  @IBOutlet var behaviorView: NSView!
  @IBOutlet var historyView: NSView!
  @IBOutlet var playlistView: NSView!
  @IBOutlet var screenshotsView: NSView!

  // MARK: - IBAction

  @IBAction func chooseScreenshotPathAction(_ sender: AnyObject) {
    Utility.quickOpenPanel(title: "Choose screenshot save path", chooseDir: true, sheetWindow: view.window) { url in
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
