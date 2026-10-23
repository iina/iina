//
//  TimePreviewView.swift
//  iina
//
//  Created by Yuze Jiang on 2026/05/28.
//  Copyright © 2026 lhc. All rights reserved.
//

class TimePreviewView: TranslucentView {
  weak var mainWindow: MainWindowController!

  var textField: NSTextField!
  private var bubbleWidth: NSLayoutConstraint!

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow

    self.textField = NSTextField(labelWithString: "")
    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.usesSingleLineMode = true
    textField.lineBreakMode = .byTruncatingTail
    textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    textField.alignment = .center

    super.init(liquidGlassCornerRadius: 16, vevCornerRadius: 8, padding: (4, 4))

    let container = NSView()
    container.addSubview(textField)
    textField.padding(.all)
    setContent(container)
    bubbleWidth = widthAnchor.constraint(equalToConstant: 8)
    bubbleWidth.isActive = true
  }

  func setText(_ text: String, maximumWidth: CGFloat? = nil) {
    textField.stringValue = text
    let naturalWidth = ceil(textField.intrinsicContentSize.width) + 8
    bubbleWidth.constant = max(8, min(naturalWidth, maximumWidth ?? naturalWidth))
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
