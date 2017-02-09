//
//  PrefSubViewController.swift
//  iina
//
//  Created by lhc on 27/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class PrefSubViewController: NSViewController {

  override var nibName: String? {
    return "PrefSubViewController"
  }

  override var identifier: String? {
    get {
      return "sub"
    }
    set {
      super.identifier = newValue
    }
  }

  var toolbarItemImage: NSImage {
    return NSImage(named: NSImageNameFontPanel)!
  }

  var toolbarItemLabel: String {
    view.layoutSubtreeIfNeeded()
    return NSLocalizedString("preference.subtitle", comment: "Subtitles")
  }

  var hasResizableWidth: Bool = false
  var hasResizableHeight: Bool = false

  @IBOutlet weak var scrollView: NSScrollView!


  override func viewDidLoad() {
    super.viewDidLoad()

    scrollView.addConstraint(NSLayoutConstraint(item: scrollView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: 420))
  }

  @IBAction func chooseSubFontAction(_ sender: AnyObject) {
    Utility.quickFontPickerWindow { font in
      UserDefaults.standard.set(font ?? "sans-serif", forKey: Preference.Key.subTextFont)
      UserDefaults.standard.synchronize()
    }
  }


}
