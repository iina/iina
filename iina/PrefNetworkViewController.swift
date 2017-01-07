//
//  PrefNetworkViewController.swift
//  iina
//
//  Created by lhc on 27/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class PrefNetworkViewController: NSViewController {

  override var nibName: String? {
    return "PrefNetworkViewController"
  }

  override var identifier: String? {
    get {
      return "network"
    }
    set {
      super.identifier = newValue
    }
  }

  var toolbarItemImage: NSImage {
    return NSImage(named: NSImageNameNetwork)!
  }

  var toolbarItemLabel: String {
    return "Network"
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do view setup here.
  }

}
