//
//  KeyRecordViewController.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class KeyRecordViewController: NSViewController, KeyRecordViewDelegate {

  @IBOutlet weak var keyRecordView: KeyRecordView!
  @IBOutlet weak var keyLabel: NSTextField!
  @IBOutlet weak var actionTextField: NSTextField!

  var keyCode: String {
    get {
      return keyLabel.stringValue
    }
  }

  var action: String {
    get {
      return actionTextField.stringValue
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    keyRecordView.delegate = self
  }

  func recordedKeyDown(with event: NSEvent) {
    keyLabel.stringValue = Utility.mpvKeyCode(from: event)
  }

}
