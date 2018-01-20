//
//  MainWindowTouchBarSupport.swift
//  iina
//
//  Created by lhc on 16/5/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

// MARK: - Touch bar

@available(OSX 10.12.2, *)
fileprivate extension NSTouchBar.CustomizationIdentifier {

  static let windowBar = NSTouchBar.CustomizationIdentifier("\(Bundle.main.bundleIdentifier!).windowTouchBar")

}

@available(OSX 10.12.2, *)
fileprivate extension NSTouchBarItem.Identifier {

  static let playPause = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.playPause")
  static let slider = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.slider")
  static let volumeUp = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.voUp")
  static let volumeDown = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.voDn")
  static let rewind = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.rewind")
  static let fastForward = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.forward")
  static let time = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.time")
  static let remainingTime = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.remainingTime")
  static let ahead15Sec = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.ahead15Sec")
  static let back15Sec = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.back15Sec")
  static let ahead30Sec = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.ahead30Sec")
  static let back30Sec = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.back30Sec")
  static let next = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.next")
  static let prev = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.prev")

}

// Image name, tag, custom label
@available(macOS 10.12.2, *)
fileprivate let touchBarItemBinding: [NSTouchBarItem.Identifier: (NSImage.Name, Int, String)] = [
  .ahead15Sec: (.touchBarSkipAhead15SecondsTemplate, 15, NSLocalizedString("touchbar.ahead_15", comment: "15sec Ahead")),
  .ahead30Sec: (.touchBarSkipAhead30SecondsTemplate, 30, NSLocalizedString("touchbar.ahead_30", comment: "30sec Ahead")),
  .back15Sec: (.touchBarSkipBack15SecondsTemplate, -15, NSLocalizedString("touchbar.back_15", comment: "-15sec Ahead")),
  .back30Sec: (.touchBarSkipBack30SecondsTemplate, -30, NSLocalizedString("touchbar.back_30", comment: "-30sec Ahead")),
  .next: (.touchBarSkipAheadTemplate, 0, NSLocalizedString("touchbar.next_video", comment: "Next Video")),
  .prev: (.touchBarSkipBackTemplate, 1, NSLocalizedString("touchbar.prev_video", comment: "Previous Video")),
  .volumeUp: (.touchBarVolumeUpTemplate, 0, NSLocalizedString("touchbar.increase_volume", comment: "Volume +")),
  .volumeDown: (.touchBarVolumeDownTemplate, 1, NSLocalizedString("touchbar.decrease_volume", comment: "Volume -")),
  .rewind: (.touchBarRewindTemplate, 0, NSLocalizedString("touchbar.rewind", comment: "Rewind")),
  .fastForward: (.touchBarFastForwardTemplate, 1, NSLocalizedString("touchbar.fast_forward", comment: "Fast Forward"))
]

@available(macOS 10.12.2, *)
class TouchBarSupport: NSObject, NSTouchBarDelegate {

  private var player: PlayerCore

  lazy var touchBar: NSTouchBar = {
    let touchBar = NSTouchBar()
    touchBar.delegate = self
    touchBar.customizationIdentifier = .windowBar
    touchBar.defaultItemIdentifiers = [.playPause, .time, .slider, .remainingTime]
    touchBar.customizationAllowedItemIdentifiers = [.playPause, .slider, .volumeUp, .volumeDown, .rewind, .fastForward, .time, .remainingTime, .ahead15Sec, .ahead30Sec, .back15Sec, .back30Sec, .next, .prev, .fixedSpaceLarge]
    return touchBar
  }()

  weak var touchBarPlaySlider: TouchBarPlaySlider?
  weak var touchBarPlayPauseBtn: NSButton?
  weak var touchBarCurrentPosLabel: DurationDisplayTextField?
  weak var touchBarRemainingPosLabel: DurationDisplayTextField?
  var touchBarPosLabelWidthLayout: NSLayoutConstraint?
  /** The current/remaining time label in Touch Bar. */
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
      item.view = NSButton(image: NSImage(named: .touchBarPauseTemplate)!, target: self, action: #selector(self.touchBarPlayBtnAction(_:)))
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
      label.mode = .current
      self.touchBarCurrentPosLabel = label
      item.view = label
      item.customizationLabel = NSLocalizedString("touchbar.time", comment: "Time Position")
      return item
    
    case .remainingTime:
      let item = NSCustomTouchBarItem(identifier: identifier)
      let label = DurationDisplayTextField(labelWithString: "00:00")
      label.alignment = .center
      label.mode = .remaining
      self.touchBarRemainingPosLabel = label
      item.view = label
      item.customizationLabel = NSLocalizedString("touchbar.remainingTime", comment: "Remaining Time Position")
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

    default:
      return nil
    }
  }

  func updateTouchBarPlayBtn() {
    if player.info.isPaused {
      touchBarPlayPauseBtn?.image = NSImage(named: .touchBarPlayTemplate)
    } else {
      touchBarPlayPauseBtn?.image = NSImage(named: .touchBarPauseTemplate)
    }
  }

  @objc func touchBarPlayBtnAction(_ sender: NSButton) {
    player.togglePause(nil)
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
    if let widthConstant = sizingTouchBarTextField.cell?.cellSize.width, touchBarCurrentPosLabel != nil || touchBarRemainingPosLabel != nil {
      if let posConstraint = touchBarPosLabelWidthLayout {
        posConstraint.constant = widthConstant + pad
        touchBarCurrentPosLabel?.setNeedsDisplay()
        touchBarRemainingPosLabel?.setNeedsDisplay()
      } else {
        if let posLabel = touchBarCurrentPosLabel {
          let posConstraint = NSLayoutConstraint(item: posLabel, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: widthConstant + pad)
          posLabel.addConstraint(posConstraint)
          touchBarPosLabelWidthLayout = posConstraint
        }
        if let posLabel = touchBarRemainingPosLabel {
          let posConstraint = NSLayoutConstraint(item: posLabel, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: widthConstant + pad)
          posLabel.addConstraint(posConstraint)
          touchBarPosLabelWidthLayout = posConstraint
        }
      }
    }

  }
}

@available(macOS 10.12.2, *)
extension MainWindowController {

  override func makeTouchBar() -> NSTouchBar? {
    return player.touchBarSupport.touchBar
  }

}

@available(macOS 10.12.2, *)
extension MiniPlayerWindowController {

  override func makeTouchBar() -> NSTouchBar? {
    return player.touchBarSupport.touchBar
  }

}

// MARK: - Slider

class TouchBarPlaySlider: NSSlider {

  var isTouching = false

  var playerCore: PlayerCore {
    return (self.window?.windowController as? MainWindowController)?.player ?? .active
  }

  override func touchesBegan(with event: NSEvent) {
    isTouching = true
    playerCore.togglePause(true)
    super.touchesBegan(with: event)
  }

  override func touchesEnded(with event: NSEvent) {
    isTouching = false
    playerCore.togglePause(false)
    super.touchesEnded(with: event)
  }

  func setDoubleValueSafely(_ value: Double) {
    guard !isTouching else { return }
    doubleValue = value
  }

}


class TouchBarPlaySliderCell: NSSliderCell {

  private let solidColor = NSColor.labelColor.withAlphaComponent(0.4)
  private let knobWidthWithImage: CGFloat = 60

  var isTouching: Bool {
    return (self.controlView as! TouchBarPlaySlider).isTouching
  }

  var playerCore: PlayerCore {
    return (self.controlView as! TouchBarPlaySlider).playerCore
  }

  override var knobThickness: CGFloat {
    return 4
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
    guard !info.isIdle else { return }
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
    guard !info.isIdle else { return }
    let barRect = self.barRect(flipped: flipped)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: barRect, xRadius: 2.5, yRadius: 2.5).setClip()
    let step: CGFloat = 3
    let end = barRect.width
    var i: CGFloat = 0
    solidColor.setFill()
    while (i < end + step) {
      let percent = Double(i / end)
      let dest = NSRect(x: barRect.origin.x + i, y: barRect.origin.y, width: 2, height: barRect.height)
      if let dur = info.videoDuration?.second,
        let image = info.getThumbnail(forSecond: percent * dur)?.image,
        info.thumbnailsProgress >= percent {
        let orig = NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
        image.draw(in: dest, from: orig, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
      } else {
        NSBezierPath(rect: dest).fill()
      }
      i += step
    }
    NSGraphicsContext.restoreGraphicsState()
  }

}
