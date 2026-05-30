//
//  OSDView.swift
//  iina
//
//  Created by Hechen Li on 2026-05-27.
//  Copyright © 2026 lhc. All rights reserved.
//

import Mustache

class OSDView: TranslucentView {
  var stackView: NSStackView
  var label: NSTextField
  var secondaryLabel: NSTextField
  var progressBar: FixedProgressBar

  weak var mainWindow: MainWindowController!

  private var accessoryView: NSView?

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow

    self.stackView = NSStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .vertical
    stackView.alignment = .leading
    stackView.spacing = 0

    self.label = NSTextField(labelWithString: "")
    label.lineBreakMode = .byTruncatingMiddle
    label.translatesAutoresizingMaskIntoConstraints = false
    label.setContentCompressionResistancePriority(.init(499), for: .horizontal)

    self.secondaryLabel = NSTextField(labelWithString: "")
    secondaryLabel.lineBreakMode = .byTruncatingMiddle
    secondaryLabel.translatesAutoresizingMaskIntoConstraints = false
    secondaryLabel.textColor = .secondaryLabelColor
    secondaryLabel.setContentCompressionResistancePriority(.init(499), for: .horizontal)

    self.progressBar = FixedProgressBar()
    progressBar.translatesAutoresizingMaskIntoConstraints = false
    progressBar.heightAnchor.constraint(equalToConstant: 12).isActive = true
    progressBar.setContentHuggingPriority(.defaultHigh, for: .horizontal)

    super.init(liquidGlassCornerRadius: 16, vevCornerRadius: 10, padding: (16, 8))

    stackView.addArrangedSubview(label)
    stackView.addArrangedSubview(secondaryLabel)
    stackView.addArrangedSubview(progressBar)
    setContent(stackView)
  }
  
  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func updateViews(fromMessage message: OSDMessage, player: PlayerCore) {
    let textSize = Preference.float(for: .osdTextSize)
    label.font = NSFont.monospacedDigitSystemFont(
      ofSize: CGFloat(textSize), weight: .regular)
    secondaryLabel.font = NSFont.monospacedDigitSystemFont(
      ofSize: CGFloat(textSize * 0.5).clamped(to: 11...25), weight: .regular)

    let (osdString, osdType) = message.message()
    label.stringValue = osdString

    // Most OSD messages are displayed based on the configured language direction.
    progressBar.userInterfaceLayoutDirection = stackView.userInterfaceLayoutDirection
    secondaryLabel.baseWritingDirection = .natural
    label.baseWritingDirection = .natural

    [secondaryLabel, progressBar].forEach {
      stackView.setVisibilityPriority(.notVisible, for: $0)
    }

    switch osdType {
    case .normal:
      break
    case .withPosition(let value):
      // OSD messages displaying the playback position must always be displayed left to right.
      progressBar.userInterfaceLayoutDirection = .leftToRight
      label.baseWritingDirection = .leftToRight
      fallthrough
    case .withProgress(let value):
      stackView.setVisibilityPriority(.mustHold, for: progressBar)
      progressBar.doubleValue = value
    case .withLeftToRightText(let text):
      // OSD messages displaying the playback position must always be displayed left to right.
      secondaryLabel.baseWritingDirection = .leftToRight
      fallthrough
    case .withText(let text):
      // data for mustache rendering
      let osdData: [String: String] = [
        "duration": player.info.videoDuration?.stringRepresentation ?? Constants.String.videoTimePlaceholder,
        "position": player.info.videoPosition?.stringRepresentation ?? Constants.String.videoTimePlaceholder,
        "currChapter": (player.mpv.getInt(MPVProperty.chapter) + 1).description,
        "chapterCount": player.info.chapters.count.description
      ]
      stackView.setVisibilityPriority(.mustHold, for: secondaryLabel)
      secondaryLabel.stringValue = try! (try! Template(string: text)).render(osdData)
    }
  }


  func addAccessoryView(_ view: NSView) {
    removeAccessoryView()
    stackView.addArrangedSubview(view)
    view.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
    accessoryView = view
  }

  func removeAccessoryView() {
    guard let accessoryView else { return }
    if stackView.subviews.contains(accessoryView) {
      stackView.removeArrangedSubview(accessoryView)
      accessoryView.removeFromSuperview()
    }
  }
}
