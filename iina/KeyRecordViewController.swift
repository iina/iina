//
//  KeyRecordViewController.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate let ui = UIHelper(scope: "keymapping")

class KeyRecordViewController: NSViewController, KeyRecordViewDelegate, NSRuleEditorDelegate, NSTextFieldDelegate {

  let keyRecordView = KeyRecordView()
  let keyLabel = NSTextField(labelWithString: "")
  let actionTextField = NSTextField()
  let ruleEditor = NSRuleEditor(frame: NSRect(x: 0, y: 0, width: 478, height: 22))

  private lazy var criterions: [Criterion] = KeyBindingDataLoader.load()

  @objc dynamic var ready = false

  var keyCode: String {
    get {
      return keyLabel.stringValue
    }
    set {
      keyLabel.stringValue = newValue
    }
  }

  var action: String {
    get {
      return actionTextField.stringValue
    }
    set {
      actionTextField.stringValue = newValue
    }
  }

  override func loadView() {
    // Used as an NSAlert accessory view, which is laid out by frame
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 155))
    self.view = view

    keyRecordView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(keyRecordView)
    keyRecordView.padding(.top, .horizontal).size(height: 46)

    keyLabel.translatesAutoresizingMaskIntoConstraints = false
    keyLabel.alignment = .center
    keyLabel.lineBreakMode = .byClipping
    keyLabel.font = NSFont(name: "Menlo-Regular", size: 22)
    keyRecordView.addSubview(keyLabel)
    keyLabel.padding(.top(8), .horizontal, .bottom(7))

    let selectActionLabel = ui.label("select_action", isSmall: true, canCompress: false)
    view.addSubview(selectActionLabel)
    selectActionLabel.padding(.leading, .trailing(greaterThan: 0)).spacing(.top(12), to: keyRecordView)

    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 24))
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.borderType = .bezelBorder
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = false
    scrollView.horizontalScrollElasticity = .none
    scrollView.verticalScrollElasticity = .none
    scrollView.contentView.drawsBackground = false
    ruleEditor.rowHeight = 24
    ruleEditor.autoresizingMask = [.width, .height]
    scrollView.documentView = ruleEditor
    view.addSubview(scrollView)
    scrollView.padding(.horizontal).spacing(.top(4), to: selectActionLabel).size(height: 24)

    let enterCommandLabel = ui.label("enter_command", isSmall: true, canCompress: false)
    view.addSubview(enterCommandLabel)
    enterCommandLabel.padding(.leading, .trailing(greaterThan: 0)).spacing(.top(8), to: scrollView)

    actionTextField.translatesAutoresizingMaskIntoConstraints = false
    actionTextField.focusRingType = .none
    actionTextField.usesSingleLineMode = true
    actionTextField.cell?.allowsUndo = false
    view.addSubview(actionTextField)
    actionTextField.padding(.horizontal, .bottom(7)).spacing(.top(4), to: enterCommandLabel).size(height: 22)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    keyRecordView.delegate = self

    ruleEditor.nestingMode = .single
    ruleEditor.canRemoveAllRows = false
    ruleEditor.delegate = self
    ruleEditor.addRow(self)

    keyLabel.delegate = self
    actionTextField.delegate = self

    NotificationCenter.default.addObserver(forName: .iinaKeyBindingInputChanged, object: nil, queue: .main) { [unowned self] _ in
      self.updateCommandField()
    }
  }

  func keyRecordView(_ view: KeyRecordView, recordedKeyDownWith event: NSEvent) {
    keyLabel.stringValue = KeyCodeHelper.mpvKeyCode(from: event)
    NotificationCenter.default.post(.init(name: NSControl.textDidChangeNotification, object: keyLabel))
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
    NotificationCenter.default.post(.init(name: NSControl.textDidChangeNotification, object: keyLabel))
  }

  // MARK: - Other

  private func updateCommandField() {
    guard let criterions = ruleEditor.criteria(forRow: 0) as? [Criterion] else { return }
    actionTextField.stringValue = KeyBindingTranslator.string(fromCriteria: criterions)
    NotificationCenter.default.post(.init(name: NSControl.textDidChangeNotification, object: actionTextField))
  }

  func controlTextDidChange(_ obj: Notification) {
    ready = !keyCode.isEmpty && !action.isEmpty
  }
}

