//
//  MainWindowTouchBarSupport.swift
//  iina
//
//  Created by lhc on 16/5/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

// MARK: - Touch bar

fileprivate extension NSTouchBarCustomizationIdentifier {

  static let windowBar = NSTouchBarCustomizationIdentifier("\(Bundle.main.bundleIdentifier!).windowTouchBar")

}

fileprivate extension NSTouchBarItemIdentifier {

  static let playPause = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.playPause")
  static let slider = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.slider")
  static let volumeUp = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.voUp")
  static let volumeDown = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.voDn")
  static let rewind = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.rewind")
  static let fastForward = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.forward")
  static let time = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.time")
  static let ahead15Sec = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.ahead15Sec")
  static let back15Sec = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.back15Sec")
  static let ahead30Sec = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.ahead30Sec")
  static let back30Sec = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.back30Sec")
  static let next = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.next")
  static let prev = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.prev")

}

// Image name, tag, custom label
@available(OSX 10.12.2, *)
fileprivate let touchBarItemBinding: [NSTouchBarItemIdentifier: (String, Int, String)] = [
  .ahead15Sec: (NSImageNameTouchBarSkipAhead15SecondsTemplate, 15, NSLocalizedString("touchbar.ahead_15", comment: "15sec Ahead")),
  .ahead30Sec: (NSImageNameTouchBarSkipAhead30SecondsTemplate, 30, NSLocalizedString("touchbar.ahead_30", comment: "30sec Ahead")),
  .back15Sec: (NSImageNameTouchBarSkipBack15SecondsTemplate, -15, NSLocalizedString("touchbar.back_15", comment: "-15sec Ahead")),
  .back30Sec: (NSImageNameTouchBarSkipBack30SecondsTemplate, -30, NSLocalizedString("touchbar.back_30", comment: "-30sec Ahead")),
  .next: (NSImageNameTouchBarSkipAheadTemplate, 0, NSLocalizedString("touchbar.next_video", comment: "Next Video")),
  .prev: (NSImageNameTouchBarSkipBackTemplate, 1, NSLocalizedString("touchbar.prev_video", comment: "Previous Video")),
  .volumeUp: (NSImageNameTouchBarVolumeUpTemplate, 0, NSLocalizedString("touchbar.increase_volume", comment: "Volume +")),
  .volumeDown: (NSImageNameTouchBarVolumeDownTemplate, 1, NSLocalizedString("touchbar.decrease_volume", comment: "Volume -")),
  .rewind: (NSImageNameTouchBarRewindTemplate, 0, NSLocalizedString("touchbar.rewind", comment: "Rewind")),
  .fastForward: (NSImageNameTouchBarFastForwardTemplate, 1, NSLocalizedString("touchbar.fast_forward", comment: "Fast Forward"))
]

@available(OSX 10.12.2, *)
extension MainWindowController: NSTouchBarDelegate {

  override func makeTouchBar() -> NSTouchBar? {
    let touchBar = NSTouchBar()
    touchBar.delegate = self
    touchBar.customizationIdentifier = .windowBar
    touchBar.defaultItemIdentifiers = [.playPause, .slider, .time]
    touchBar.customizationAllowedItemIdentifiers = [.playPause, .slider, .volumeUp, .volumeDown, .rewind, .fastForward, .time, .ahead15Sec, .ahead30Sec, .back15Sec, .back30Sec, .next, .prev, .fixedSpaceLarge]
    return touchBar
  }

  func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItemIdentifier) -> NSTouchBarItem? {

    switch identifier {

    case NSTouchBarItemIdentifier.playPause:
      let item = NSCustomTouchBarItem(identifier: identifier)
      item.view = NSButton(image: NSImage(named: NSImageNameTouchBarPauseTemplate)!, target: self, action: #selector(self.touchBarPlayBtnAction(_:)))
      item.customizationLabel = NSLocalizedString("touchbar.play_pause", comment: "Play / Pause")
      self.touchBarPlayPauseBtn = item.view as? NSButton
      return item

    case NSTouchBarItemIdentifier.slider:
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

    case NSTouchBarItemIdentifier.volumeUp,
         NSTouchBarItemIdentifier.volumeDown:
      guard let data = touchBarItemBinding[identifier] else { return nil }
      return buttonTouchBarItem(withIdentifier: identifier, imageName: data.0, tag: data.1, customLabel: data.2, action: #selector(self.touchBarVolumeAction(_:)))

    case NSTouchBarItemIdentifier.rewind,
         NSTouchBarItemIdentifier.fastForward:
      guard let data = touchBarItemBinding[identifier] else { return nil }
      return buttonTouchBarItem(withIdentifier: identifier, imageName: data.0, tag: data.1, customLabel: data.2, action: #selector(self.touchBarRewindAction(_:)))

    case NSTouchBarItemIdentifier.time:
      let item = NSCustomTouchBarItem(identifier: identifier)
      let label = DurationDisplayTextField(labelWithString: "00:00")
      label.alignment = .center
      label.mode = ud.bool(forKey: Preference.Key.showRemainingTime) ? .remaining : .current
      self.touchBarCurrentPosLabel = label
      item.view = label
      item.customizationLabel = NSLocalizedString("touchbar.time", comment: "Time Position")
      return item

    case NSTouchBarItemIdentifier.ahead15Sec,
         NSTouchBarItemIdentifier.back15Sec,
         NSTouchBarItemIdentifier.ahead30Sec,
         NSTouchBarItemIdentifier.back30Sec:
      guard let data = touchBarItemBinding[identifier] else { return nil }
      return buttonTouchBarItem(withIdentifier: identifier, imageName: data.0, tag: data.1, customLabel: data.2, action: #selector(self.touchBarSeekAction(_:)))

    case NSTouchBarItemIdentifier.next,
         NSTouchBarItemIdentifier.prev:
      guard let data = touchBarItemBinding[identifier] else { return nil }
      return buttonTouchBarItem(withIdentifier: identifier, imageName: data.0, tag: data.1, customLabel: data.2, action: #selector(self.touchBarSkipAction(_:)))

    default:
      return nil
    }
  }

  func updateTouchBarPlayBtn() {
    if playerCore.info.isPaused {
      touchBarPlayPauseBtn?.image = NSImage(named: NSImageNameTouchBarPlayTemplate)
    } else {
      touchBarPlayPauseBtn?.image = NSImage(named: NSImageNameTouchBarPauseTemplate)
    }
  }

  func touchBarPlayBtnAction(_ sender: NSButton) {
    playerCore.togglePause(nil)
  }

  func touchBarVolumeAction(_ sender: NSButton) {
    let currVolume = playerCore.info.volume
    playerCore.setVolume(currVolume + (sender.tag == 0 ? 5 : -5))
  }

  func touchBarRewindAction(_ sender: NSButton) {
    arrowButtonAction(left: sender.tag == 0)
  }

  func touchBarSeekAction(_ sender: NSButton) {
    let sec = sender.tag
    playerCore.seek(relativeSecond: Double(sec), option: .relative)
  }

  func touchBarSkipAction(_ sender: NSButton) {
    playerCore.navigateInPlaylist(nextOrPrev: sender.tag == 0)
  }

  func touchBarSliderAction(_ sender: NSSlider) {
    let percentage = 100 * sender.doubleValue / sender.maxValue
    playerCore.seek(percent: percentage)
  }

  private func buttonTouchBarItem(withIdentifier identifier: NSTouchBarItemIdentifier, imageName: String, tag: Int, customLabel: String, action: Selector) -> NSCustomTouchBarItem {
    let item = NSCustomTouchBarItem(identifier: identifier)
    let button = NSButton(image: NSImage(named: imageName)!, target: self, action: action)
    button.tag = tag
    item.view = button
    item.customizationLabel = customLabel
    return item
  }

  // Set TouchBar Time Label

  func setupTouchBarUI() {
    let duration: VideoTime = playerCore.info.videoDuration ?? .zero
    let pad: CGFloat = 16.0
    sizingTouchBarTextField.stringValue = duration.stringRepresentation
    if let widthConstant = sizingTouchBarTextField.cell?.cellSize.width, let posLabel = touchBarCurrentPosLabel {
      if let posConstraint = touchBarPosLabelWidthLayout {
        posConstraint.constant = widthConstant + pad
        posLabel.setNeedsDisplay()
      } else {
        let posConstraint = NSLayoutConstraint(item: posLabel, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: widthConstant + pad)
        posLabel.addConstraint(posConstraint)
        touchBarPosLabelWidthLayout = posConstraint
      }
    }
    
  }
}

// MARK: - Slider

class TouchBarPlaySlider: NSSlider {

  var isTouching = false

  var playerCore: PlayerCore {
    return (self.window?.windowController as? MainWindowController)?.playerCore ?? .active
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
      if let thumbImage = info.thumbnails.first?.image {
        let imageKnobWidth = thumbImage.size.aspect * superKnob.height
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
    if isTouching, let dur = info.videoDuration?.second, let tb = info.getThumbnail(forSecond: (doubleValue / 100) * dur) {
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(roundedRect: knobRect, xRadius: 3, yRadius: 3).setClip()
      tb.image?.draw(in: knobRect)
      NSColor.white.setStroke()
      let border = NSBezierPath(roundedRect: knobRect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
      border.lineWidth = 1
      border.stroke()
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
        let orig = NSRect(x: image.size.width / 2, y: 0, width: 2 * (image.size.height / barRect.height), height: barRect.height)
        image.draw(in: dest, from: orig, operation: .copy, fraction: 1)
      } else {
        NSBezierPath(rect: dest).fill()
      }
      i += step
    }
    NSGraphicsContext.restoreGraphicsState()
  }

}
