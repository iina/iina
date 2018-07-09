//
//  PrefUtilsViewController.swift
//  iina
//
//  Created by Collider LI on 9/7/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class PrefUtilsViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefUtilsViewController")
  }

  var preferenceTabTitle: String {
    return NSLocalizedString("preference.utilities", comment: "Utilities")
  }

  override var sectionViews: [NSView] {
    return [sectionDefaultAppView, sectionClearCacheView, sectionBrowserExtView]
  }

  @IBOutlet var sectionDefaultAppView: NSView!
  @IBOutlet var sectionClearCacheView: NSView!
  @IBOutlet var sectionBrowserExtView: NSView!

  override func viewDidLoad() {
      super.viewDidLoad()
      // Do view setup here.
  }

}
