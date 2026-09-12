//
//  MediaLoadingView.swift
//  iina
//
//  Created by Antigravity on 2026/09/12.
//  Copyright © 2026 lhc. All rights reserved.
//

import Cocoa

class MediaLoadingView: NSView {

  enum Style {
    case regular
    case compact
  }

  private let style: Style
  private let stackView: NSStackView
  let progressIndicator: NSProgressIndicator
  let loadingLabel: NSTextField

  init(style: Style = .regular) {
    self.style = style
    self.progressIndicator = NSProgressIndicator()
    self.loadingLabel = NSTextField(labelWithString: NSLocalizedString("main.loading", comment: "Loading…"))
    self.stackView = NSStackView()

    super.init(frame: .zero)

    setupView()
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupView() {
    wantsLayer = true
    translatesAutoresizingMaskIntoConstraints = false
    isHidden = true

    // Dark gray background matching QuickTime Player (#222222)
    layer?.backgroundColor = NSColor(srgbRed: 34.0 / 255.0, green: 34.0 / 255.0, blue: 34.0 / 255.0, alpha: 1.0).cgColor

    progressIndicator.style = .spinning
    progressIndicator.isDisplayedWhenStopped = false
    progressIndicator.translatesAutoresizingMaskIntoConstraints = false

    loadingLabel.alignment = .center
    loadingLabel.lineBreakMode = .byTruncatingTail
    loadingLabel.translatesAutoresizingMaskIntoConstraints = false

    switch style {
    case .regular:
      progressIndicator.controlSize = .regular
      loadingLabel.font = .systemFont(ofSize: 15, weight: .semibold)
      loadingLabel.textColor = NSColor(white: 0.92, alpha: 1.0)
      stackView.spacing = 10
    case .compact:
      progressIndicator.controlSize = .small
      loadingLabel.font = .systemFont(ofSize: 12, weight: .medium)
      loadingLabel.textColor = NSColor(white: 0.92, alpha: 1.0)
      stackView.spacing = 6
    }

    stackView.orientation = .vertical
    stackView.alignment = .centerX
    stackView.distribution = .fill
    stackView.translatesAutoresizingMaskIntoConstraints = false

    stackView.addArrangedSubview(progressIndicator)
    stackView.addArrangedSubview(loadingLabel)

    addSubview(stackView)

    NSLayoutConstraint.activate([
      stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
      stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
      stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
      stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
    ])
  }

  func show(message: String? = nil) {
    loadingLabel.stringValue = message ?? NSLocalizedString("main.loading", comment: "Loading…")
    progressIndicator.startAnimation(nil)
    isHidden = false
  }

  func hide() {
    progressIndicator.stopAnimation(nil)
    isHidden = true
  }
}
