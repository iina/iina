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
  .ahead15Sec: (NSImageNameTouchBarSkipAhead15SecondsTemplate, 15, "15sec Ahead"),
  .ahead30Sec: (NSImageNameTouchBarSkipAhead30SecondsTemplate, 30, "30sec Ahead"),
  .back15Sec: (NSImageNameTouchBarSkipBack15SecondsTemplate, -15, "-15sec Ahead"),
  .back30Sec: (NSImageNameTouchBarSkipBack30SecondsTemplate, -30, "-30sec Ahead"),
  .next: (NSImageNameTouchBarSkipAheadTemplate, 0, "Next video"),
  .prev: (NSImageNameTouchBarSkipBackTemplate, 1, "Previous video"),
  .volumeUp: (NSImageNameTouchBarVolumeUpTemplate, 0, "Volume +"),
  .volumeDown: (NSImageNameTouchBarVolumeDownTemplate, 1, "Volume -"),
  .rewind: (NSImageNameTouchBarRewindTemplate, 0, "Rewind"),
  .fastForward: (NSImageNameTouchBarFastForwardTemplate, 1, "Fast forward")
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
      item.customizationLabel = "Play / Pause"
      self.touchBarPlayPauseBtn = item.view as! NSButton
      return item

    case NSTouchBarItemIdentifier.slider:
      let item = NSSliderTouchBarItem(identifier: identifier)
      item.slider.minValue = 0
      item.slider.maxValue = 100
      item.slider.target = self
      item.slider.action = #selector(self.touchBarSliderAction(_:))
      item.customizationLabel = "Seek"
      self.touchBarPlaySlider = item.slider
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
      let label = NSTextField(labelWithString: "0:00")
      label.alignment = .center
      self.touchBarCurrentPosLabel = label
      item.view = label
      item.customizationLabel = "Time Position"
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

  // MARK: - Set TouchBar Time Label

  func setupTouchBarUI() {
    guard let duration = playerCore.info.videoDuration else {
      Utility.fatal("video info not available")
    }

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
