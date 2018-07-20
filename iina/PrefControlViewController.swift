//
//  PrefControlViewController.swift
//  iina
//
//  Created by lhc on 20/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

@objcMembers
class PrefControlViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    get {
      return NSNib.Name("PrefControlViewController")
    }
  }

  var preferenceTabTitle: String {
    get {
      return NSLocalizedString("preference.control", comment: "Control")
    }
  }

  override var sectionViews: [NSView] {
    return [sectionTrackpadView, sectionMouseView]
  }

  @IBOutlet var sectionTrackpadView: NSView!
  @IBOutlet var sectionMouseView: NSView!

  @IBOutlet weak var forceTouchLabel: NSTextField!
  @IBOutlet weak var scrollVerticallyLabel: NSTextField!

  override func viewDidLoad() {
    super.viewDidLoad()

    forceTouchLabel.widthAnchor.constraint(equalTo: scrollVerticallyLabel.widthAnchor, multiplier: 1).isActive = true
  }

}
