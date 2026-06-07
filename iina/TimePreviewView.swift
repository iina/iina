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

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow

    self.textField = NSTextField(labelWithString: "")
    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.usesSingleLineMode = false
    textField.alignment = .center

    super.init(liquidGlassCornerRadius: 16, vevCornerRadius: 8, padding: (4, 4))

    let container = NSView()
    container.addSubview(textField)
    textField.padding(.all)
    setContent(container)
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
