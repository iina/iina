//
//  MenuController.swift
//  mpvx
//
//  Created by lhc on 31/8/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class MenuController: NSObject, NSMenuDelegate {
  
  /** For convinent bindings. see `bind(...)` below. [menu: check state block] */
  private var menuBindingList: [NSMenu: (NSMenuItem) -> Bool] = [:]
  
  // File
  @IBOutlet weak var file: NSMenuItem!
  @IBOutlet weak var open: NSMenuItem!
  // Playback
  @IBOutlet weak var playback: NSMenuItem!
  @IBOutlet weak var pause: NSMenuItem!
  @IBOutlet weak var stop: NSMenuItem!
  @IBOutlet weak var forward: NSMenuItem!
  @IBOutlet weak var nextFrame: NSMenuItem!
  @IBOutlet weak var backward: NSMenuItem!
  @IBOutlet weak var previousFrame: NSMenuItem!
  @IBOutlet weak var jumpToBegin: NSMenuItem!
  @IBOutlet weak var jumpTo: NSMenuItem!
  @IBOutlet weak var screenShot: NSMenuItem!
  @IBOutlet weak var gotoScreenshotFolder: NSMenuItem!
  @IBOutlet weak var advancedScreenShot: NSMenuItem!
  @IBOutlet weak var abLoop: NSMenuItem!
  @IBOutlet weak var playlist: NSMenuItem!
  @IBOutlet weak var playlistMenu: NSMenu!
  @IBOutlet weak var chapter: NSMenuItem!
  @IBOutlet weak var chapterMenu: NSMenu!
  // Video
  @IBOutlet weak var quickSettingsVideo: NSMenuItem!
  @IBOutlet weak var videoTrack: NSMenuItem!
  @IBOutlet weak var videoTrackMenu: NSMenu!
  @IBOutlet weak var halfSize: NSMenuItem!
  @IBOutlet weak var normalSize: NSMenuItem!
  @IBOutlet weak var normalSizeRetina: NSMenuItem!
  @IBOutlet weak var doubleSize: NSMenuItem!
  @IBOutlet weak var fitToScreen: NSMenuItem!
  @IBOutlet weak var fullScreen: NSMenuItem!
  @IBOutlet weak var alwaysOnTop: NSMenuItem!
  @IBOutlet weak var aspectMenu: NSMenu!
  @IBOutlet weak var cropMenu: NSMenu!
  @IBOutlet weak var rotationMenu: NSMenu!
  @IBOutlet weak var flipMenu: NSMenu!
  @IBOutlet weak var mirror: NSMenuItem!
  @IBOutlet weak var flip: NSMenuItem!
  //Audio
  @IBOutlet weak var quickSettingsAudio: NSMenuItem!
  @IBOutlet weak var audioTrackMenu: NSMenu!
  @IBOutlet weak var increaseVolume: NSMenuItem!
  @IBOutlet weak var increaseVolumeSlightly: NSMenuItem!
  @IBOutlet weak var decreaseVolume: NSMenuItem!
  @IBOutlet weak var decreaseVolumeSlightly: NSMenuItem!
  @IBOutlet weak var mute: NSMenuItem!
  @IBOutlet weak var increaseAudioDelay: NSMenuItem!
  @IBOutlet weak var decreaseAudioDelay: NSMenuItem!
  @IBOutlet weak var resetAudioDelay: NSMenuItem!
  
  
  
  func bindMenuItems() {
    // Playback menu
    pause.action = #selector(MainWindowController.menuTogglePause(_:))
    stop.action = #selector(MainWindowController.menuStop(_:))
    // -- seeking
    forward.action = #selector(MainWindowController.menuStep(_:))
    nextFrame.action = #selector(MainWindowController.menuStepFrame(_:))
    backward.action = #selector(MainWindowController.menuStep(_:))
    previousFrame.action = #selector(MainWindowController.menuStepFrame(_:))
    jumpToBegin.action = #selector(MainWindowController.menuJumpToBegin(_:))
    jumpTo.action = #selector(MainWindowController.menuJumpTo(_:))
    // -- screenshot
    screenShot.action = #selector(MainWindowController.menuSnapshot(_:))
    gotoScreenshotFolder.action = #selector(AppDelegate.menuOpenScreenshotFolder(_:))
//    advancedScreenShot
    // -- list and chapter
    abLoop.action = #selector(MainWindowController.menuABLoop(_:))
    playlistMenu.delegate = self
    chapterMenu.delegate = self
    
    // Video menu
    quickSettingsVideo.action = #selector(MainWindowController.menuShowVideoQuickSettings(_:))
    // -- window size
    videoTrackMenu.delegate = self
    (halfSize.tag, normalSize.tag, normalSizeRetina.tag, doubleSize.tag, fitToScreen.tag) = (0, 1, -1, 2, 3)
    for item in [halfSize, normalSize, normalSizeRetina, doubleSize, fitToScreen] {
      item?.action = #selector(MainWindowController.menuChangeWindowSize(_:))
    }
    // -- screen
    fullScreen.action = #selector(MainWindowController.menuToggleFullScreen(_:))
//    alwaysOnTop
    // -- aspect
    var aspectList = AppData.aspects
    aspectList.insert("Default", at: 0)
    bind(menu: aspectMenu, withOptions: aspectList, objects: nil, action: #selector(MainWindowController.menuChangeAspect(_:))) {
      menuItem -> Bool in
      return PlayerCore.shared.info.unsureAspect == menuItem.representedObject as? String
    }
    // -- crop
    var cropList = AppData.aspects
    cropList.insert("None", at: 0)
    bind(menu: cropMenu, withOptions: cropList, objects: nil, action: #selector(MainWindowController.menuChangeCrop(_:))) {
      menuItem -> Bool in
      return PlayerCore.shared.info.unsureCrop == menuItem.representedObject as? String
    }
    // -- rotation
    let rotationTitles = AppData.rotations.map { "\($0)\(Constants.String.degree)" }
    bind(menu: rotationMenu, withOptions: rotationTitles, objects: AppData.rotations, action: #selector(MainWindowController.menuChangeRotation(_:))) {
      menuItem -> Bool in
      return PlayerCore.shared.info.rotation == menuItem.representedObject as? Int
    }
    // -- flip and mirror
    flipMenu.delegate = self
    flip.action = #selector(MainWindowController.menuToggleFlip(_:))
    mirror.action = #selector(MainWindowController.menuToggleMirror(_:))
    
    // Audio menu
    quickSettingsAudio.action = #selector(MainWindowController.menuShowAudioQuickSettings(_:))
    // - volume
    (increaseVolume.representedObject, decreaseVolume.representedObject, increaseVolumeSlightly.representedObject, decreaseVolumeSlightly.representedObject) = (5, -5, 1, -1)
    for item in [increaseVolume, decreaseVolume, increaseVolumeSlightly, decreaseVolumeSlightly] {
      item?.action = #selector(MainWindowController.menuChangeVolume(_:))
    }
    mute.action = #selector(MainWindowController.menuToggleMute(_:))
  }
  
  func updatePlaylist() {
    playlistMenu.removeAllItems()
    playlistMenu.addItem(withTitle: "Show/Hide Playlist Panel", action: #selector(MainWindowController.menuShowPlaylistPanel(_:)), keyEquivalent: "")
    playlistMenu.addItem(NSMenuItem.separator())
    for (index, item) in PlayerCore.shared.info.playlist.enumerated() {
      playlistMenu.addItem(withTitle: item.filenameForDisplay, action: #selector(MainWindowController.menuPlaylistItem(_:)),
                           tag: index, obj: nil, stateOn: item.isCurrent)
    }
  }
  
  func updateChapterList() {
    chapterMenu.removeAllItems()
    chapterMenu.addItem(withTitle: "Show/Hide Chapter Panel", action: #selector(MainWindowController.menuShowChaptersPanel(_:)), keyEquivalent: "")
    chapterMenu.addItem(NSMenuItem.separator())
    let info = PlayerCore.shared.info
    for (index, chapter) in info.chapters.enumerated() {
      let menuTitle = "\(chapter.time.stringRepresentation) - \(chapter.title)"
      let nextChapterTime = info.chapters.at(index+1)?.time ?? Constants.Time.infinite
      let isPlaying = info.videoPosition?.between(chapter.time, nextChapterTime) ?? false
      chapterMenu.addItem(withTitle: menuTitle, action: #selector(MainWindowController.menuChapterSwitch(_:)),
                          tag: index, obj: nil, stateOn: isPlaying)
    }
  }
  
  func updateVideoTracks() {
    let info = PlayerCore.shared.info
    videoTrackMenu.removeAllItems()
    let noTrackMenuItem = NSMenuItem(title: Constants.String.none, action: #selector(MainWindowController.menuChangeTrack(_:)), keyEquivalent: "")
    noTrackMenuItem.representedObject = MPVTrack.noneVideoTrack
    if info.vid == 0 {  // no track
      noTrackMenuItem.state = NSOnState
    }
    videoTrackMenu.addItem(noTrackMenuItem)
    for track in info.videoTracks {
      videoTrackMenu.addItem(withTitle: track.readableTitle, action: #selector(MainWindowController.menuChangeTrack(_:)),
                             tag: nil, obj: track, stateOn: track.id == info.vid)
    }
  }
  
  func updateFlipAndMirror() {
    let info = PlayerCore.shared.info
    flip.state = info.flipFilter == nil ? NSOffState : NSOnState
    mirror.state = info.mirrorFilter == nil ? NSOffState : NSOnState
  }
  
  /** Bind a menu with a list of available options. */
  private func bind(menu: NSMenu, withOptions titles: [String], objects: [Any]?, action: Selector?, checkStateBlock block: @escaping (NSMenuItem) -> Bool) {
    // options and objects must be same
    guard objects == nil || titles.count == objects?.count else {
      Utility.log("different object count when binding menu")
      return
    }
    // add menu items
    for (index, title) in titles.enumerated() {
      let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
      if let object = objects?[index] {
        menuItem.representedObject = object
      } else {
        menuItem.representedObject = title
      }
      menu.addItem(menuItem)
    }
    // add to list
    menu.delegate = self
    menuBindingList.updateValue(block, forKey: menu)
  }
  
  // MARK: - Menu delegate
  
  func menuWillOpen(_ menu: NSMenu) {
    if menu == playlistMenu {
      updatePlaylist()
    } else if menu == chapterMenu {
      updateChapterList()
    } else if menu == videoTrackMenu {
      updateVideoTracks()
    } else if menu == flipMenu {
      updateFlipAndMirror()
    }
    // check convinently binded menus
    if let checkEnableBlock = menuBindingList[menu] {
      for item in menu.items {
        item.state = checkEnableBlock(item) ? NSOnState : NSOffState
      }
    }
  }
  
}
