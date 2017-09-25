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

  private var pendingKey: String?
  private var pendingAction: String?

  var keyCode: String {
    get {
      return keyLabel.stringValue
    }
    set {
      if let f = keyLabel {
        f.stringValue = newValue
      } else {
        pendingKey = newValue
      }
    }
  }

  var action: String {
    get {
      return actionTextField.stringValue
    }
    set {
      if let f = actionTextField {
        f.stringValue = newValue
      } else {
        pendingAction = newValue
      }
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    keyRecordView.delegate = self

    ruleEditor.nestingMode = .single
    ruleEditor.canRemoveAllRows = false
    ruleEditor.delegate = self
    ruleEditor.addRow(self)

    if let pk = pendingKey {
      keyLabel.stringValue = pk
      pendingKey = nil
    }
    if let pa = pendingAction {
      actionTextField.stringValue = pa
      pendingAction = nil
    }

    NotificationCenter.default.addObserver(forName: Constants.Noti.keyBindingInputChanged, object: nil, queue: .main) { _ in
      self.updateCommandField()
    }
  }

  func recordedKeyDown(with event: NSEvent) {
    keyLabel.stringValue = Utility.mpvKeyCode(from: event)
  }

  // MARK: - NSRuleEditorDelegate

  func ruleEditor(_ editor: NSRuleEditor, child index: Int, forCriterion criterion: Any?, with rowType: NSRuleEditor.RowType) -> Any {
    if criterion == nil {
      return criterions[index]
    } else {
      return (criterion as! Criterion).child(at: index)
    }
  }

  func ruleEditor(_ editor: NSRuleEditor, numberOfChildrenForCriterion criterion: Any?, with rowType: NSRuleEditor.RowType) -> Int {
    if criterion == nil {
      return criterions.count
    } else {
      return (criterion as! Criterion).childrenCount()
    }
  }

  func ruleEditor(_ editor: NSRuleEditor, displayValueForCriterion criterion: Any, inRow row: Int) -> Any {
    return (criterion as! Criterion).displayValue()
  }

  func ruleEditorRowsDidChange(_ notification: Notification) {
    updateCommandField()
  }

  // MARK: IBAction

  @IBAction func ChooseMediaKeyAction(_ sender: NSPopUpButton) {
    switch sender.selectedTag() {
    case 0:
      keyLabel.stringValue = "PLAY"
    case 1:
      keyLabel.stringValue = "PREV"
    case 2:
      keyLabel.stringValue = "NEXT"
    default:
      break
    }
  }

  // MARK: - Other

  private func updateCommandField() {
    guard let criterions = ruleEditor.criteria(forRow: 0) as? [Criterion] else { return }
    actionTextField.stringValue = KeyBindingTranslator.string(fromCriteria: criterions)
  }

}

