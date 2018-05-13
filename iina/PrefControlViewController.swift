//
//  PrefControlViewController.swift
//  iina
//
//  Created by lhc on 20/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import MASPreferences

@objcMembers
class PrefControlViewController: NSViewController, MASPreferencesViewController {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefControlViewController")
  }

  var viewIdentifier: String = "PrefControlViewController"

  var toolbarItemImage: NSImage? {
    return #imageLiteral(resourceName: "toolbar_control")
  }

  var toolbarItemLabel: String? {
    view.layoutSubtreeIfNeeded()
    return NSLocalizedString("preference.control", comment: "Control")
  }

  var hasResizableWidth: Bool = false
  var hasResizableHeight: Bool = false

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do view setup here.
  }

}
