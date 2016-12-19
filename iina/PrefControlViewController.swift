//
//  PrefControlViewController.swift
//  iina
//
//  Created by lhc on 20/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class PrefControlViewController: NSViewController {

  override var nibName: String? {
    get {
      return "PrefControlViewController"
    }
  }
  
  override var identifier: String? {
    get {
      return "control"
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
      return "Control"
    }
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    // Do view setup here.
  }
    
}
