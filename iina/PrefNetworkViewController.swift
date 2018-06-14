//
//  PrefNetworkViewController.swift
//  iina
//
//  Created by lhc on 27/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

@objcMembers
class PrefNetworkViewController: NSViewController {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefNetworkViewController")
  }

  var viewIdentifier: String = "PrefNetworkViewController"

  var toolbarItemImage: NSImage {
    return NSImage(named: NSImage.networkName)!
  }

  var toolbarItemLabel: String {
    view.layoutSubtreeIfNeeded()
    return NSLocalizedString("preference.network", comment: "Network")
  }

  var hasResizableWidth: Bool = false
  var hasResizableHeight: Bool = false

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do view setup here.
  }

}
