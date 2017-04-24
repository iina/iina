//
//  PrefUIViewController.swift
//  iina
//
//  Created by lhc on 25/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import MASPreferences

class PrefUIViewController: NSViewController, MASPreferencesViewController {

  override var nibName: String {
    return "PrefUIViewController"
  }

  override var identifier: String? {
    get {
      return "ui"
    }
    set {
      super.identifier = newValue
    }
  }

  var toolbarItemImage: NSImage {
    get {
      return NSImage(named: "toolbar_play")!
    }
  }

  var toolbarItemLabel: String {
    get {
      view.layoutSubtreeIfNeeded()
      return NSLocalizedString("preference.ui", comment: "UI")
    }
  }

  var hasResizableWidth: Bool = false
  var hasResizableHeight: Bool = false

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do view setup here.
  }

}
