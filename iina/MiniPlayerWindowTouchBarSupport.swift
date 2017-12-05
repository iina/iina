//
//  MiniPlayerWindowTouchBarSupport.swift
//  iina
//
//  Created by @doukasd on 20/10/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

// MARK: TouchBar Support

@available(OSX 10.12.2, *)
fileprivate extension NSTouchBar.CustomizationIdentifier {
  static let miniPlayerBar = NSTouchBar.CustomizationIdentifier("\(Bundle.main.bundleIdentifier!).miniPlayerTouchBar")
}

@available(OSX 10.12.2, *)
fileprivate extension NSTouchBarItem.Identifier {
  static let playPause = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.playPause")
  static let volumeUp = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.voUp")
  static let volumeDown = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.voDn")
  static let time = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.time")
  static let next = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.next")
  static let prev = NSTouchBarItem.Identifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.prev")
}

// Image name, tag, custom label
@available(macOS 10.12.2, *)
fileprivate let touchBarItemBinding: [NSTouchBarItem.Identifier: (NSImage.Name, Int, String)] = [
  .next: (.touchBarSkipAheadTemplate, 0, NSLocalizedString("touchbar.next_track", comment: "Next Track")),
  .prev: (.touchBarSkipBackTemplate, 1, NSLocalizedString("touchbar.prev_track", comment: "Previous Track")),
  .volumeUp: (.touchBarVolumeUpTemplate, 0, NSLocalizedString("touchbar.increase_volume", comment: "Volume +")),
  .volumeDown: (.touchBarVolumeDownTemplate, 1, NSLocalizedString("touchbar.decrease_volume", comment: "Volume -")),
]

@available(macOS 10.12.2, *)
extension MiniPlayerWindowController: NSTouchBarDelegate {
  
  override func makeTouchBar() -> NSTouchBar? {
    let touchBar = NSTouchBar()
    touchBar.delegate = self
    touchBar.customizationIdentifier = .miniPlayerBar
    touchBar.defaultItemIdentifiers = [.flexibleSpace, .time, .playPause, .prev, .next, .flexibleSpace]
    touchBar.customizationAllowedItemIdentifiers = [.playPause, .volumeUp, .volumeDown, .time, .next, .prev, .fixedSpaceLarge, .flexibleSpace]
    return touchBar
  }
  
  func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
    
    switch identifier {
      
    case .playPause:
      let item = NSCustomTouchBarItem(identifier: identifier)
      item.view = NSButton(image: NSImage(named: .touchBarPauseTemplate)!, target: self, action: #selector(self.touchBarPlayBtnAction(_:)))
      item.customizationLabel = NSLocalizedString("touchbar.play_pause", comment: "Play / Pause")
      self.touchBarPlayPauseBtn = item.view as? NSButton
      return item
      
    case .volumeUp,
         .volumeDown:
      guard let data = touchBarItemBinding[identifier] else { return nil }
      return buttonTouchBarItem(withIdentifier: identifier, imageName: data.0, tag: data.1, customLabel: data.2, action: #selector(self.touchBarVolumeAction(_:)))
      
    case .time:
      let item = NSCustomTouchBarItem(identifier: identifier)
      let label = DurationDisplayTextField(labelWithString: "00:00")
      label.alignment = .center
      label.mode = Preference.bool(for: .showRemainingTime) ? .remaining : .current
      self.touchBarCurrentPosLabel = label
      item.view = label
      item.customizationLabel = NSLocalizedString("touchbar.time", comment: "Time Position")
      return item
      
    case .next,
         .prev:
      guard let data = touchBarItemBinding[identifier] else { return nil }
      return buttonTouchBarItem(withIdentifier: identifier, imageName: data.0, tag: data.1, customLabel: data.2, action: #selector(self.touchBarSkipAction(_:)))
      
    default:
      return nil
    }
  }
  
  // update the play/pause button image
  func updateTouchBarPlayBtn() {
    if player.info.isPaused {
      touchBarPlayPauseBtn?.image = NSImage(named: .touchBarPauseTemplate)
    } else {
      touchBarPlayPauseBtn?.image = NSImage(named: .touchBarPlayTemplate)
    }
  }
  
  // action for Pause/Play button
  @objc func touchBarPlayBtnAction(_ sender: NSButton) {
    player.togglePause(nil)
    updateTouchBarPlayBtn()
  }
  
  // action for Volume Up/Down buttons
  @objc func touchBarVolumeAction(_ sender: NSButton) {
    let currVolume = player.info.volume
    player.setVolume(currVolume + (sender.tag == 0 ? 5 : -5))
  }
  
  // action for Next/Prev Track buttons
  @objc func touchBarSkipAction(_ sender: NSButton) {
    player.navigateInPlaylist(nextOrPrev: sender.tag == 0)
  }
  
  private func buttonTouchBarItem(withIdentifier identifier: NSTouchBarItem.Identifier, imageName: NSImage.Name, tag: Int, customLabel: String, action: Selector) -> NSCustomTouchBarItem {
    let item = NSCustomTouchBarItem(identifier: identifier)
    let button = NSButton(image: NSImage(named: imageName)!, target: self, action: action)
    button.tag = tag
    item.view = button
    item.customizationLabel = customLabel
    return item
  }
  
}
