//
//  PreferenceGeneralViewController.swift
//  iina
//
//  Created by lhc on 27/10/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import MASPreferences


class PreferenceGeneralViewController: NSViewController, MASPreferencesViewController {
  
  override var nibName: String? {
    get {
      return "PreferenceGeneralViewController"
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
      return "General"
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do view setup here.
  }
    
}
