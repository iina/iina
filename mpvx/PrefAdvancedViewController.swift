//
//  PrefAdvancedViewController.swift
//  mpvx
//
//  Created by lhc on 14/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import MASPreferences

class PrefAdvancedViewController: NSViewController, MASPreferencesViewController {
  
  override var nibName: String? {
    return "PrefAdvancedViewController"
  }
  
  override var identifier: String? {
    get {
      return "advanced"
    }
    set {
      super.identifier = newValue
    }
  }
  
  var toolbarItemImage: NSImage {
    return NSImage(named: NSImageNameAdvanced)!
  }
  
  var toolbarItemLabel: String {
    return "Advanced"
  }


  override func viewDidLoad() {
    super.viewDidLoad()
    // Do view setup here.
  }
    
}
