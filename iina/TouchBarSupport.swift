//
//  MainWindowTouchBarSupport.swift
//  iina
//
//  Created by lhc on 16/5/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

// MARK: - Touch bar

fileprivate extension NSTouchBar.CustomizationIdentifier {

  static let windowBar = NSTouchBar.CustomizationIdentifier("\(Bundle.main.bundleIdentifier!).windowTouchBar")

}

fileprivate extension NSTouchBarItem.Identifier {

  static let playPause = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.playPause")
  static let slider = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.slider")
  static let volumeUp = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.voUp")
  static let volumeDown = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.voDn")
  static let rewind = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.rewind")
  static let fastForward = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.forward")
  static let time = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.time")
  static let remainingTimeOrTotalDuration = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.remainingTimeOrTotalDuration")
  static let ahead15Sec = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.ahead15Sec")
  static let back15Sec = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.back15Sec")
  static let ahead30Sec = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.ahead30Sec")
  static let back30Sec = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.back30Sec")
  static let next = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.next")
  static let prev = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.prev")
  static let exitFullScr = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.exitFullScr")
  static let togglePIP = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.togglePIP")
}

// Image name, tag, custom label
fileprivate let touchBarItemBinding: [NSTouchBarItem.Identifier: (NSImage.Name, Int, String)] = [
  .ahead15Sec: (NSImage.touchBarSkipAhead15SecondsTemplateName, 15, NSLocalizedString("touchbar.ahead_15", comment: "15sec Ahead")),
  .ahead30Sec: (NSImage.touchBarSkipAhead30SecondsTemplateName, 30, NSLocalizedString("touchbar.ahead_30", comment: "30sec Ahead")),
  .back15Sec: (NSImage.touchBarSkipBack15SecondsTemplateName, -15, NSLocalizedString("touchbar.back_15", comment: "-15sec Ahead")),
  .back30Sec: (NSImage.touchBarSkipBack30SecondsTemplateName, -30, NSLocalizedString("touchbar.back_30", comment: "-30sec Ahead")),
  .next: (NSImage.touchBarSkipAheadTemplateName, 0, NSLocalizedString("touchbar.next_video", comment: "Next Video")),
  .prev: (NSImage.touchBarSkipBackTemplateName, 1, NSLocalizedString("touchbar.prev_video", comment: "Previous Video")),
  .volumeUp: (NSImage.touchBarVolumeUpTemplateName, 0, NSLocalizedString("touchbar.increase_volume", comment: "Volume +")),
  .volumeDown: (NSImage.touchBarVolumeDownTemplateName, 1, NSLocalizedString("touchbar.decrease_volume", comment: "Volume -")),
  .rewind: (NSImage.touchBarRewindTemplateName, 0, NSLocalizedString("touchbar.rewind", comment: "Rewind")),
  .fastForward: (NSImage.touchBarFastForwardTemplateName, 1, NSLocalizedString("touchbar.fast_forward", comment: "Fast Forward"))
]

class TouchBarSupport: NSObject, NSTouchBarDelegate {

  private var player: PlayerCore

  lazy var touchBar: NSTouchBar = {
    let touchBar = NSTouchBar()
    touchBar.delegate = self
    touchBar.customizationIdentifier = .windowBar
    touchBar.defaultItemIdentifiers = [.playPause, .time, .slider, .remainingTimeOrTotalDuration]
    touchBar.customizationAllowedItemIdentifiers = [.playPause, .slider, .volumeUp, .volumeDown, .rewind, .fastForward, .time, .remainingTimeOrTotalDuration, .ahead15Sec, .ahead30Sec, .back15Sec, .back30Sec, .next, .prev, .togglePIP, .fixedSpaceLarge]
    return touchBar
  }()

  weak var touchBarPlaySlider: TouchBarPlaySlider?
  weak var touchBarPlayPauseBtn: NSButton?
  var touchBarPosLabels: [DurationDisplayTextField] = []
  var touchBarPosLabelWidthLayout: NSLayoutConstraint?
  /** The current / remaining time/total time label in Touch Bar. */
  lazy var sizingTouchBarTextField: NSTextField = {
    return NSTextField()
  }()

  init(playerCore: PlayerCore) {
    self.player = playerCore
  }

  func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {

    switch identifier {

    case .playPause:
      let item = NSCustomTouchBarItem(identifier: identifier)
      item.view = NSButton(image: NSImage(named: NSImage.touchBarPauseTemplateName)!, target: self, action: #selector(self.touchBarPlayBtnAction(_:)))
      item.customizationLabel = NSLocalizedString("touchbar.play_pause", comment: "Play / Pause")
      self.touchBarPlayPauseBtn = item.view as? NSButton
      return item

    case .slider:
      let item = NSSliderTouchBarItem(identifier: identifier)
      item.slider = TouchBarPlaySlider()
      item.slider.cell = TouchBarPlaySliderCell()
      item.slider.minValue = 0
      item.slider.maxValue = 100
      item.slider.target = self
      item.slider.action = #selector(self.touchBarSliderAction(_:))
      item.customizationLabel = NSLocalizedString("touchbar.seek", comment: "Seek")
      self.touchBarPlaySlider = item.slider as? TouchBarPlaySlider
      return item

    case .volumeUp,
         .volumeDown:
      guard let data = touchBarItemBinding[identifier] else { return nil }
      return buttonTouchBarItem(withIdentifier: identifier, imageName: data.0, tag: data.1, customLabel: data.2, action: #selector(self.touchBarVolumeAction(_:)))

    case .rewind,
         .fastForward:
      guard let data = touchBarItemBinding[identifier] else { return nil }
      return buttonTouchBarItem(withIdentifier: identifier, imageName: data.0, tag: data.1, customLabel: data.2, action: #selector(self.touchBarRewindAction(_:)))

    case .time:
      let item = NSCustomTouchBarItem(identifier: identifier)
      let label = DurationDisplayTextField(labelWithString: "00:00")
      label.alignment = .center
      label.font = .monospacedDigitSystemFont(ofSize: 0, weight: .regular)
      label.mode = .current
      self.touchBarPosLabels.append(label)
      item.view = label
      item.customizationLabel = NSLocalizedString("touchbar.time", comment: "Time Position")
      return item

    case .remainingTimeOrTotalDuration:
      let item = NSCustomTouchBarItem(identifier: identifier)
      let label = DurationDisplayTextField(labelWithString: "00:00")
      label.alignment = .center
      label.font = .monospacedDigitSystemFont(ofSize: 0, weight: .regular)
      label.mode = Preference.bool(for: .touchbarShowRemainingTime) ? .remaining : .duration
      // The baseWritingDirection must be changed from natural (the default) to leftToRight or the
      // minus sign will be drawn on the right side of the time string when displaying time
      // remaining in a right-to-left language.
      label.baseWritingDirection = .leftToRight
      self.touchBarPosLabels.append(label)
      item.view = label
      item.customizationLabel = NSLocalizedString("touchbar.remainingTimeOrTotalDuration", comment: "Show Remaining Time or Total Duration")
      return item

    case .ahead15Sec,
         .back15Sec,
         .ahead30Sec,
         .back30Sec:
      guard let data = touchBarItemBinding[identifier] else { return nil }
      return buttonTouchBarItem(withIdentifier: identifier, imageName: data.0, tag: data.1, customLabel: data.2, action: #selector(self.touchBarSeekAction(_:)))

    case .next,
         .prev:
      guard let data = touchBarItemBinding[identifier] else { return nil }
      return buttonTouchBarItem(withIdentifier: identifier, imageName: data.0, tag: data.1, customLabel: data.2, action: #selector(self.touchBarSkipAction(_:)))

    case .exitFullScr:
      let item = NSCustomTouchBarItem(identifier: identifier)
      item.view = NSButton(image: NSImage(named: NSImage.touchBarExitFullScreenTemplateName)!, target: self, action: #selector(self.touchBarExitFullScrAction(_:)))
      return item

    case .togglePIP:
      let item = NSCustomTouchBarItem(identifier: identifier)
      // FIXME: we might need a better icon for this
      item.view = NSButton(image: Bundle.main.image(forResource: "pip")!, target: self, action: #selector(self.touchBarTogglePIP(_:)))
      item.customizationLabel = NSLocalizedString("touchbar.toggle_pip", comment: "Toggle PIP")
      return item

    default:
      return nil
    }
  }

  func updateTouchBarPlayBtn() {
    if player.info.state == .paused {
      touchBarPlayPauseBtn?.image = NSImage(named: NSImage.touchBarPlayTemplateName)
    } else {
      touchBarPlayPauseBtn?.image = NSImage(named: NSImage.touchBarPauseTemplateName)
    }
  }

  @objc func touchBarPlayBtnAction(_ sender: NSButton) {
    player.togglePause()
  }

  @objc func touchBarVolumeAction(_ sender: NSButton) {
    let currVolume = player.info.volume
    player.setVolume(currVolume + (sender.tag == 0 ? 5 : -5))
  }

  @objc func touchBarRewindAction(_ sender: NSButton) {
    player.mainWindow.arrowButtonAction(left: sender.tag == 0)
  }

  @objc func touchBarSeekAction(_ sender: NSButton) {
    let sec = sender.tag
    player.seek(relativeSecond: Double(sec), option: .relative)
  }

  @objc func touchBarSkipAction(_ sender: NSButton) {
    player.navigateInPlaylist(nextMedia: sender.tag == 0)
  }

  @objc func touchBarSliderAction(_ sender: NSSlider) {
    let percentage = 100 * sender.doubleValue / sender.maxValue
    player.seek(percent: percentage, forceExact: true)
  }

  @objc func touchBarExitFullScrAction(_ sender: NSButton) {
    player.mainWindow.toggleWindowFullScreen()
  }

  @objc func touchBarTogglePIP(_ sender: NSButton) {
    player.mainWindow.menuTogglePIP(.dummy)
  }

  private func buttonTouchBarItem(withIdentifier identifier: NSTouchBarItem.Identifier, imageName: NSImage.Name, tag: Int, customLabel: String, action: Selector) -> NSCustomTouchBarItem {
    let item = NSCustomTouchBarItem(identifier: identifier)
    let button = NSButton(image: NSImage(named: imageName)!, target: self, action: action)
    button.tag = tag
    item.view = button
    item.customizationLabel = customLabel
    return item
  }

  func setupTouchBarUI() {
    let duration: VideoTime = player.info.videoDuration ?? .zero
    let pad: CGFloat = 16.0
    sizingTouchBarTextField.stringValue = duration.stringRepresentation
    if let widthConstant = sizingTouchBarTextField.cell?.cellSize.width, !touchBarPosLabels.isEmpty {
      if let posConstraint = touchBarPosLabelWidthLayout {
        posConstraint.constant = widthConstant + pad
        touchBarPosLabels.forEach { $0.needsDisplay = true }
      } else {
        for posLabel in touchBarPosLabels {
          let posConstraint = NSLayoutConstraint(item: posLabel, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: widthConstant + pad)
          posLabel.addConstraint(posConstraint)
          touchBarPosLabelWidthLayout = posConstraint
        }
      }
    }
  }

  func toggleTouchBarEsc(enteringFullScr: Bool) {
    if enteringFullScr, PlayerCore.keyBindings["ESC"]?.readableAction == "set fullscreen no" {
      touchBar.escapeKeyReplacementItemIdentifier = .exitFullScr
    } else {
      touchBar.escapeKeyReplacementItemIdentifier = nil
    }
  }
}

extension MainWindowController {

  override func makeTouchBar() -> NSTouchBar? {
    return player.makeTouchBar()
  }
}

extension MiniPlayerWindowController {

  override func makeTouchBar() -> NSTouchBar? {
    return player.makeTouchBar()
  }
}

// MARK: - Slider

class TouchBarPlaySlider: NSSlider {

  var isTouching = false
  var wasPlayingBeforeTouching = false

  var playerCore: PlayerCore {
    return (self.window?.windowController as? MainWindowController)?.player ?? .active
  }

  override func touchesBegan(with event: NSEvent) {
    isTouching = true
    wasPlayingBeforeTouching = playerCore.info.state == .playing
    playerCore.pause()
    super.touchesBegan(with: event)
  }

  override func touchesEnded(with event: NSEvent) {
    isTouching = false
    if (wasPlayingBeforeTouching) {
      playerCore.resume()
    }
    super.touchesEnded(with: event)
  }

  func resetCachedThumbnails() {
    (cell as! TouchBarPlaySliderCell).cachedThumbnailProgress = -1
  }

  func setDoubleValueSafely(_ value: Double) {
    guard !isTouching else { return }
    doubleValue = value
  }

}


class TouchBarPlaySliderCell: NSSliderCell {

  var cachedThumbnailProgress: Double = -1

  private let solidColor = NSColor.labelColor.withAlphaComponent(0.4)
  private let knobWidthWithImage: CGFloat = 60

  private var backgroundImage: NSImage?

  var isTouching: Bool {
    return (self.controlView as! TouchBarPlaySlider).isTouching
  }

  var playerCore: PlayerCore {
    return (self.controlView as! TouchBarPlaySlider).playerCore
  }

  override var knobThickness: CGFloat {
    return 4
  }

  /// Initializes and returns a newly allocated `TouchBarPlaySliderCell` object.
  /// - Important: As per Apple's [Internationalization and Localization Guide](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPInternational/SupportingRight-To-LeftLanguages/SupportingRight-To-LeftLanguages.html)
  ///     video controllers and timeline indicators should not flip in a right-to-left language.
  override init() {
    super.init()
    userInterfaceLayoutDirection = .leftToRight
  }

  required init(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func barRect(flipped: Bool) -> NSRect {
    self.controlView?.superview?.layer?.backgroundColor = .black
    let rect = super.barRect(flipped: flipped)
    return NSRect(x: rect.origin.x,
                  y: 2,
                  width: rect.width,
                  height: self.controlView!.frame.height - 4)
  }

  override func knobRect(flipped: Bool) -> NSRect {
    let info = playerCore.info
    let superKnob = super.knobRect(flipped: flipped)
    if isTouching {
      if info.thumbnails.count > 0 {
        let imageKnobWidth = knobWidthWithImage
        let barWidth = barRect(flipped: flipped).width

        return NSRect(x: superKnob.origin.x * (barWidth - (imageKnobWidth - superKnob.width)) / barWidth,
                      y: superKnob.origin.y,
                      width: imageKnobWidth,
                      height: superKnob.height)
      } else {
        return superKnob
      }
    } else {
      let remainingKnobWidth = superKnob.width - knobThickness
      return NSRect(x: superKnob.origin.x + remainingKnobWidth * CGFloat(doubleValue/100),
                    y: superKnob.origin.y,
                    width: knobThickness,
                    height: superKnob.height)
    }
  }

  override func drawKnob(_ knobRect: NSRect) {
    let info = playerCore.info
    guard info.state.active else { return }
    if isTouching, let dur = info.videoDuration?.second, let tb = info.getThumbnail(forSecond: (doubleValue / 100) * dur), let image = tb.image {
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(roundedRect: knobRect, xRadius: 3, yRadius: 3).setClip()
      let origSize = image.size.crop(withAspect: Aspect(size: knobRect.size))
      let origRect = NSRect(x: (image.size.width - origSize.width) / 2,
                            y: (image.size.height - origSize.height) / 2,
                            width: origSize.width,
                            height: origSize.height)
      image.draw(in: knobRect, from: origRect, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
      NSColor.white.setStroke()
      let outerBorder = NSBezierPath(roundedRect: knobRect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
      outerBorder.lineWidth = 1
      outerBorder.stroke()
      NSColor.black.setStroke()
      let innerBorder = NSBezierPath(roundedRect: knobRect.insetBy(dx: 2, dy: 2), xRadius: 2, yRadius: 2)
      innerBorder.lineWidth = 1
      innerBorder.stroke()
      NSGraphicsContext.restoreGraphicsState()
    } else {
      NSColor.labelColor.setFill()
      let path = NSBezierPath(roundedRect: knobRect, xRadius: 2, yRadius: 2)
      path.fill()
    }
  }

  override func drawBar(inside rect: NSRect, flipped: Bool) {
    let info = playerCore.info
    guard info.state.active else { return }
    let barRect = self.barRect(flipped: flipped)
    if let image = backgroundImage, info.thumbnailsProgress == cachedThumbnailProgress {
      // draw cached background image
      image.draw(in: barRect)
    } else {
      // draw the background image
      let imageRect = NSRect(origin: .zero, size: barRect.size)
      let image = NSImage(size: barRect.size)
      image.lockFocus()
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(roundedRect: imageRect, xRadius: 2.5, yRadius: 2.5).setClip()
      let step: CGFloat = 3
      let end = imageRect.width
      var i: CGFloat = 0
      solidColor.setFill()
      while (i < end + step) {
        let percent = Double(i / end)
        let dest = NSRect(x: i, y: 0, width: 2, height: imageRect.height)
        if let dur = info.videoDuration?.second,
          let image = info.getThumbnail(forSecond: percent * dur)?.image,
          info.thumbnailsProgress >= percent {
          let orig = NSRect(origin: .zero, size: image.size)
          image.draw(in: dest, from: orig, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        } else {
          NSBezierPath(rect: dest).fill()
        }
        i += step
      }
      NSGraphicsContext.restoreGraphicsState()
      image.unlockFocus()
      backgroundImage = image
      cachedThumbnailProgress = info.thumbnailsProgress
      image.draw(in: barRect)
    }
  }

}
