//
//  PrefCodecViewController.swift
//  iina
//
//  Created by lhc on 27/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class PrefCodecViewController: NSViewController {

  override var nibName: String? {
    return "PrefCodecViewController"
  }

  override var identifier: String? {
    get {
      return "codec"
    }
    set {
      super.identifier = newValue
    }
  }

  var toolbarItemImage: NSImage {
    return NSImage(named: "toolbar_codec")!
  }

  var toolbarItemLabel: String {
    return "Codec"
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do view setup here.
  }

}
