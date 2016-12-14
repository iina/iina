//
//  PrefAdvancedViewController.swift
//  mpvx
//
//  Created by lhc on 14/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import MASPreferences

class PrefAdvancedViewController: NSViewController, MASPreferencesViewController {
  
  override var nibName: String? {
    return "PrefAdvancedViewController"
  }
  
  override var identifier: String? {
    get {
      return "advanced"
    }
    set {
      super.identifier = newValue
    }
  }
  
  var toolbarItemImage: NSImage {
    return NSImage(named: NSImageNameAdvanced)!
  }
  
  var toolbarItemLabel: String {
    return "Advanced"
  }
  
  
  @IBOutlet weak var enableSettingsBtn: NSButton!
  @IBOutlet weak var settingsView: NSView!


  override func viewDidLoad() {
    super.viewDidLoad()
    updateControlStatus(self)
  }
  
  // MARK: - IBAction
  
  @IBAction func updateControlStatus(_ sender: AnyObject) {
    let enable = enableSettingsBtn.state == NSOnState
    settingsView.subviews.forEach { view in
      if let control = view as? NSControl {
        control.isEnabled = enable
      }
    }
  }
  
  @IBAction func revealLogDir(_ sender: AnyObject) {
    NSWorkspace.shared().open(Utility.logDirURL)
  }
  
    
}
