//
//  AdditionalInfoView.swift
//  iina
//
//  Created by Hechen Li on 2026-05-27.
//  Copyright © 2026 lhc. All rights reserved.
//

class AdditionalInfoView: TranslucentView {
  var stackView: NSStackView!
  var timeLabel: NSTextField!
  var title: NSTextField!
  var batteryView: NSView!
  var batteryLabel: NSTextField!

  weak var mainWindow: MainWindowController!

  private var accessoryView: NSView?

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow

    let container = NSView()

    self.title = NSTextField(labelWithString: "")
    title.translatesAutoresizingMaskIntoConstraints = false
    title.font = .systemFont(ofSize: 18)

    self.stackView = NSStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .horizontal
    stackView.alignment = .centerY
    stackView.spacing = 4

    self.timeLabel = NSTextField(labelWithString: "")
    timeLabel.font = .monospacedSystemFont(ofSize: 18, weight: .bold)
    timeLabel.textColor = .secondaryLabelColor
    timeLabel.translatesAutoresizingMaskIntoConstraints = false

    let separator = NSBox()
    separator.translatesAutoresizingMaskIntoConstraints = false
    separator.boxType = .separator
    separator.size(width: 2, height: 16)

    let batteryImage = NSImageView(image: .battery)
    batteryImage.translatesAutoresizingMaskIntoConstraints = false

    self.batteryLabel = NSTextField(labelWithString: "")
    batteryLabel.translatesAutoresizingMaskIntoConstraints = false
    batteryLabel.font = .boldSystemFont(ofSize: 13)
    batteryLabel.textColor = .secondaryLabelColor

    self.batteryView = NSView()
    batteryView.translatesAutoresizingMaskIntoConstraints = false
    batteryView.addSubview(batteryImage)
    batteryView.addSubview(batteryLabel)
    batteryImage.padding(.all(0))
    batteryLabel.center()

    super.init(liquidGlassCornerRadius: 16, vevCornerRadius: 10, padding: (16, 8))

    if let clockImage = NSImage.findSFSymbol(["clock"])?
      .withSymbolConfiguration(.init(pointSize: 18, weight: .bold)) {
      let timeImage = NSImageView(image: clockImage)
      timeImage.translatesAutoresizingMaskIntoConstraints = false
      timeImage.size(width: 24, height: 24)
      stackView.addArrangedSubview(timeImage)
    }
    stackView.addArrangedSubview(timeLabel)
    stackView.addArrangedSubview(separator)
    stackView.addArrangedSubview(batteryView)

    container.addSubview(title)
    container.addSubview(stackView)
    title.padding(.top, .horizontal).spacing(.bottom(8), to: stackView)
    stackView.padding(.bottom, .trailing, .leading(greaterThan: 0))
    setContent(container)
  }
  
  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func update() {
    timeLabel.stringValue = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
    title.stringValue = window?.representedURL?.lastPathComponent ?? window?.title ?? ""
    if let capacity = PowerSource.getList().filter({ $0.type == "InternalBattery" }).first?.currentCapacity {
      batteryLabel.stringValue = "\(capacity)%"
      stackView.setVisibilityPriority(.mustHold, for: batteryView)
    } else {
      stackView.setVisibilityPriority(.notVisible, for: batteryView)
    }
  }
}
