//
//  OpenURLAccessoryViewController.swift
//  iina
//
//  Created by lhc on 26/3/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class OpenURLAccessoryViewController: NSViewController {

  @IBOutlet weak var urlField: ShortcutAvailableTextField!

  @IBOutlet weak var safariLinkBtn: NSButton!
  @IBOutlet weak var chromeLinkBtn: NSButton!

  override func viewDidLoad() {
    super.viewDidLoad()

    [safariLinkBtn, chromeLinkBtn].forEach {
      $0!.image = NSImage(named: NSImageNameFollowLinkFreestandingTemplate)
    }
  }
    
}
