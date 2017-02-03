//
//  KeyRecordViewController.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class KeyRecordViewController: NSViewController, KeyRecordViewDelegate, NSRuleEditorDelegate {

  @IBOutlet weak var keyRecordView: KeyRecordView!
  @IBOutlet weak var keyLabel: NSTextField!
  @IBOutlet weak var actionTextField: NSTextField!
  @IBOutlet weak var ruleEditor: NSRuleEditor!

  private lazy var criterions: [Criterion] = KeyBindingDataLoader.load()

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

    ruleEditor.nestingMode = .single
    ruleEditor.canRemoveAllRows = false
    ruleEditor.delegate = self
    ruleEditor.addRow(self)
  }

  func recordedKeyDown(with event: NSEvent) {
    keyLabel.stringValue = Utility.mpvKeyCode(from: event)
  }

  // MARK: - NSRuleEditorDelegate

  func ruleEditor(_ editor: NSRuleEditor, child index: Int, forCriterion criterion: Any?, with rowType: NSRuleEditorRowType) -> Any {
    if criterion == nil {
      return criterions[index]
    } else {
      return (criterion as! Criterion).child(at: index)
    }
  }

  func ruleEditor(_ editor: NSRuleEditor, numberOfChildrenForCriterion criterion: Any?, with rowType: NSRuleEditorRowType) -> Int {
    if criterion == nil {
      return criterions.count
    } else {
      return (criterion as! Criterion).childrenCount()
    }
  }

  func ruleEditor(_ editor: NSRuleEditor, displayValueForCriterion criterion: Any, inRow row: Int) -> Any {
    return (criterion as! Criterion).displayValue()
  }

}

