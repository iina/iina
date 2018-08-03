//
//  PrefNetworkViewController.swift
//  iina
//
//  Created by lhc on 27/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

@objcMembers
class PrefNetworkViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefNetworkViewController")
  }

  var viewIdentifier: String = "PrefNetworkViewController"

  var toolbarItemImage: NSImage {
    return NSImage(named: .network)!
  }

  var preferenceTabTitle: String {
    view.layoutSubtreeIfNeeded()
    return NSLocalizedString("preference.network", comment: "Network")
  }

  override var sectionViews: [NSView] {
    return [sectionCacheView, sectionNetworkView, sectionYTDLView]
  }

  @IBOutlet var sectionCacheView: NSView!
  @IBOutlet var sectionNetworkView: NSView!
  @IBOutlet var sectionYTDLView: NSView!

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do view setup here.
  }

}
