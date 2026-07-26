//
//  BufferIndicatorView.swift
//  iina
//
//  Created by Yuze Jiang on 2026/05/27.
//  Copyright © 2026 lhc. All rights reserved.
//


class BufferIndicatorView: TranslucentView {
  var progressIndicator: NSProgressIndicator!
  var progressLabel: NSTextField!
  var detailLabel: NSTextField!

  weak var mainWindow: MainWindowController!
  weak var player: PlayerCore!

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow
    self.player = mainWindow.player

    self.progressIndicator = NSProgressIndicator()
    progressIndicator.style = .spinning
    progressIndicator.startAnimation(nil)

    self.progressLabel = NSTextField(labelWithString: "")

    self.detailLabel = NSTextField(labelWithString: "")
    detailLabel.isHidden = true

    super.init(padding: (16, 8))

    let stackView = NSStackView(views: [progressIndicator, progressLabel, detailLabel])
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .vertical
    stackView.alignment = .centerX
    stackView.spacing = 4
    stackView.size(width: 150)

    let container = NSView()
    container.addSubview(stackView)
    stackView.padding(.all(4))
    setContent(container)
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func update() {
    guard mainWindow.loaded else { return }

    if player.info.isNetworkResource {
      isHidden = false
      progressIndicator.startAnimation(nil)
      progressLabel.stringValue = NSLocalizedString("main.opening_stream", comment:"Opening stream…")
      detailLabel.isHidden = true
    } else {
      isHidden = true
    }
  }

  /// Update the state of the throbber indicating buffering or seeking is occurring.
  /// - Important: The mpv
  ///     [cache-buffering-state](https://mpv.io/manual/stable/#command-interface-cache-buffering-state)
  ///     property is only valid when
  ///     [paused-for-cache](https://mpv.io/manual/stable/#command-interface-paused-for-cache) is `true`
  ///     and can not be used to provide an indication of progress when seeking.
  func updateNetworkState() {
    guard player.info.pausedForCache && Preference.bool(for: .showBufferingThrobber)
            || player.info.isSeeking && Preference.bool(for: .showSeekingThrobber) else {
      isHidden = true
      return
    }
    let usedStr = FloatingPointByteCountFormatter.string(fromByteCount: player.info.cacheUsed,
                                                         countStyle: .binary)
    let speedStr = FloatingPointByteCountFormatter.string(fromByteCount: player.info.cacheSpeed)
    if player.info.pausedForCache {
      let bufferingState = player.info.bufferingState
      progressLabel.stringValue = String(format:
        NSLocalizedString("main.buffering_indicator", comment:"Buffering… %d%%"), bufferingState)
    } else {
      progressLabel.stringValue = NSLocalizedString("main.seeking_indicator",
                                                          comment: "Seeking…")
    }
    detailLabel.stringValue = "\(usedStr)B (\(speedStr)B/s)"
    detailLabel.isHidden = false
    isHidden = false
  }

}
