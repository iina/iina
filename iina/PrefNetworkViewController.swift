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
    view.layoutSubtreeIfNeeded()
    return NSLocalizedString("preference.network", comment: "Network")
  }

  var hasResizableWidth: Bool = false
  var hasResizableHeight: Bool = false

  @IBOutlet weak var defaultCacheSizeTextField: NSTextField!
  @IBOutlet weak var cacheBufferSizeTextField: NSTextField!
  override func viewDidLoad() {
    super.viewDidLoad()

    defaultCacheSizeTextField.formatter = RestrictedNumberFormatter(min: 0, isDecimal: false)
    cacheBufferSizeTextField.formatter = RestrictedNumberFormatter(min: 0, isDecimal:false)
  }

}
