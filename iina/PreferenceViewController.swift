//
//  PreferenceViewController.swift
//  iina
//
//  Created by Collider LI on 8/7/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class PreferenceViewController: NSViewController {

  @IBOutlet weak var stackView: NSStackView!

  var sectionViews: [NSView] {
    return []
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    for (index, section) in sectionViews.enumerated() {
      stackView.addView(section, in: .top)
      if index != sectionViews.count - 1 {
        stackView.addView(NSBox.horizontalLine(), in: .top)
      }
    }
  }

}
