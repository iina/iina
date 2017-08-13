//
//  MenuController.swift
//  iina
//
//  Created by lhc on 31/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class MenuController: NSObject, NSMenuDelegate {

  /** For convinent bindings. see `bind(...)` below. [menu: check state block] */
  private var menuBindingList: [NSMenu: (NSMenuItem) -> Bool] = [:]

  private var stringForOpen: String!
  private var stringForOpenAlternative: String!
  private var stringForOpenURL: String!
  private var stringForOpenURLAlternative: String!

  // File
  @IBOutlet weak var file: NSMenuItem!
  @IBOutlet weak var open: NSMenuItem!
  @IBOutlet weak var openAlternative: NSMenuItem!
  @IBOutlet weak var openURL: NSMenuItem!
  @IBOutlet weak var openURLAlternative: NSMenuItem!
  @IBOutlet weak var savePlaylist: NSMenuItem!
  @IBOutlet weak var deleteCurrentFile: NSMenuItem!
  @IBOutlet weak var newWindow: NSMenuItem!
  @IBOutlet weak var newWindowSeparator: NSMenuItem!
  // Playback
  @IBOutlet weak var playbackMenu: NSMenu!
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
  @IBOutlet weak var fileLoop: NSMenuItem!
  @IBOutlet weak var playlistPanel: NSMenuItem!
  @IBOutlet weak var playlist: NSMenuItem!
  @IBOutlet weak var playlistLoop: NSMenuItem!
  @IBOutlet weak var playlistMenu: NSMenu!
  @IBOutlet weak var chapterPanel: NSMenuItem!
  @IBOutlet weak var chapter: NSMenuItem!
  @IBOutlet weak var chapterMenu: NSMenu!
  // Video
  @IBOutlet weak var videoMenu: NSMenu!
  @IBOutlet weak var quickSettingsVideo: NSMenuItem!
  @IBOutlet weak var videoTrack: NSMenuItem!
  @IBOutlet weak var videoTrackMenu: NSMenu!
  @IBOutlet weak var halfSize: NSMenuItem!
  @IBOutlet weak var normalSize: NSMenuItem!
  @IBOutlet weak var normalSizeRetina: NSMenuItem!
  @IBOutlet weak var doubleSize: NSMenuItem!
  @IBOutlet weak var biggerSize: NSMenuItem!
  @IBOutlet weak var smallerSize: NSMenuItem!
  @IBOutlet weak var fitToScreen: NSMenuItem!
  @IBOutlet weak var fullScreen: NSMenuItem!
  @IBOutlet weak var pictureInPicture: NSMenuItem!
  @IBOutlet weak var alwaysOnTop: NSMenuItem!
  @IBOutlet weak var aspectMenu: NSMenu!
  @IBOutlet weak var cropMenu: NSMenu!
  @IBOutlet weak var rotationMenu: NSMenu!
  @IBOutlet weak var flipMenu: NSMenu!
  @IBOutlet weak var mirror: NSMenuItem!
  @IBOutlet weak var flip: NSMenuItem!
  @IBOutlet weak var deinterlace: NSMenuItem!
  @IBOutlet weak var videoFilters: NSMenuItem!
  //Audio
  @IBOutlet weak var audioMenu: NSMenu!
  @IBOutlet weak var quickSettingsAudio: NSMenuItem!
  @IBOutlet weak var audioTrackMenu: NSMenu!
  @IBOutlet weak var volumeIndicator: NSMenuItem!
  @IBOutlet weak var increaseVolume: NSMenuItem!
  @IBOutlet weak var increaseVolumeSlightly: NSMenuItem!
  @IBOutlet weak var decreaseVolume: NSMenuItem!
  @IBOutlet weak var decreaseVolumeSlightly: NSMenuItem!
  @IBOutlet weak var mute: NSMenuItem!
  @IBOutlet weak var audioDelayIndicator: NSMenuItem!
  @IBOutlet weak var increaseAudioDelay: NSMenuItem!
  @IBOutlet weak var decreaseAudioDelay: NSMenuItem!
  @IBOutlet weak var resetAudioDelay: NSMenuItem!
  @IBOutlet weak var audioFilters: NSMenuItem!
  @IBOutlet weak var audioDeviceMenu: NSMenu!
  // Subtitle
  @IBOutlet weak var subMenu: NSMenu!
  @IBOutlet weak var quickSettingsSub: NSMenuItem!
  @IBOutlet weak var subTrackMenu: NSMenu!
  @IBOutlet weak var secondSubTrackMenu: NSMenu!
  @IBOutlet weak var loadExternalSub: NSMenuItem!
  @IBOutlet weak var increaseTextSize: NSMenuItem!
  @IBOutlet weak var decreaseTextSize: NSMenuItem!
  @IBOutlet weak var resetTextSize: NSMenuItem!
  @IBOutlet weak var subDelayIndicator: NSMenuItem!
  @IBOutlet weak var increaseSubDelay: NSMenuItem!
  @IBOutlet weak var decreaseSubDelay: NSMenuItem!
  @IBOutlet weak var resetSubDelay: NSMenuItem!
  @IBOutlet weak var encodingMenu: NSMenu!
  @IBOutlet weak var subFont: NSMenuItem!
  @IBOutlet weak var findOnlineSub: NSMenuItem!
  @IBOutlet weak var saveDownloadedSub: NSMenuItem!
  // Window
  @IBOutlet weak var customTouchBar: NSMenuItem!
  @IBOutlet weak var inspector: NSMenuItem!
  @IBOutlet weak var miniPlayer: NSMenuItem!


  // MARK: - Construct Menus

  func bindMenuItems() {

    // File menu
    
    savePlaylist.action = #selector(MainMenuActionHandler.menuSavePlaylist(_:))
    deleteCurrentFile.action = #selector(MainMenuActionHandler.menuDeleteCurrentFile(_:))

    stringForOpen = open.title
    stringForOpenURL = openURL.title
    stringForOpenAlternative = openAlternative.title
    stringForOpenURLAlternative = openURLAlternative.title

    updateOpenMenuItems()
    UserDefaults.standard.addObserver(self, forKeyPath: Preference.Key.alwaysOpenInNewWindow, options: [], context: nil)

    if UserDefaults.standard.bool(forKey: Preference.Key.enableCmdN) {
      newWindowSeparator.isHidden = false
      newWindow.isHidden = false
    }
    
    // Playback menu

    playbackMenu.delegate = self

    pause.action = #selector(MainMenuActionHandler.menuTogglePause(_:))
    stop.action = #selector(MainMenuActionHandler.menuStop(_:))

    // -- seeking
    forward.action = #selector(MainMenuActionHandler.menuStep(_:))
    nextFrame.action = #selector(MainMenuActionHandler.menuStepFrame(_:))
    backward.action = #selector(MainMenuActionHandler.menuStep(_:))
    previousFrame.action = #selector(MainMenuActionHandler.menuStepFrame(_:))
    jumpToBegin.action = #selector(MainMenuActionHandler.menuJumpToBegin(_:))
    jumpTo.action = #selector(MainMenuActionHandler.menuJumpTo(_:))

    // -- screenshot
    screenShot.action = #selector(MainMenuActionHandler.menuSnapshot(_:))
    gotoScreenshotFolder.action = #selector(AppDelegate.menuOpenScreenshotFolder(_:))
//    advancedScreenShot

    // -- list and chapter
    abLoop.action = #selector(MainMenuActionHandler.menuABLoop(_:))
    fileLoop.action = #selector(MainMenuActionHandler.menuFileLoop(_:))
    playlistMenu.delegate = self
    chapterMenu.delegate = self
    playlistLoop.action = #selector(MainMenuActionHandler.menuPlaylistLoop(_:))
    playlistPanel.action = #selector(MainWindowController.menuShowPlaylistPanel(_:))
    chapterPanel.action = #selector(MainWindowController.menuShowChaptersPanel(_:))

    // Video menu

    videoMenu.delegate = self

    quickSettingsVideo.action = #selector(MainWindowController.menuShowVideoQuickSettings(_:))
    videoTrackMenu.delegate = self

    // -- window size
    (halfSize.tag, normalSize.tag, normalSizeRetina.tag, doubleSize.tag, fitToScreen.tag, biggerSize.tag, smallerSize.tag) = (0, 1, -1, 2, 3, 11, 10)
    for item in [halfSize, normalSize, normalSizeRetina, doubleSize, fitToScreen, biggerSize, smallerSize] {
      item?.action = #selector(MainWindowController.menuChangeWindowSize(_:))
    }

    // -- screen
    fullScreen.action = #selector(MainWindowController.menuToggleFullScreen(_:))
    if #available(OSX 10.12, *) {
      pictureInPicture.action = #selector(MainWindowController.menuTogglePIP(_:))
    } else {
      videoMenu.removeItem(pictureInPicture)
    }
    alwaysOnTop.action = #selector(MainWindowController.menuAlwaysOnTop(_:))

    // -- aspect
    var aspectList = AppData.aspects
    aspectList.insert(Constants.String.default, at: 0)
    bind(menu: aspectMenu, withOptions: aspectList, objects: nil, objectMap: nil, action: #selector(MainMenuActionHandler.menuChangeAspect(_:))) {
      PlayerCore.active.info.unsureAspect == $0.representedObject as? String
    }

    // -- crop
    var cropList = AppData.aspects
    cropList.insert(Constants.String.none, at: 0)
    bind(menu: cropMenu, withOptions: cropList, objects: nil, objectMap: nil, action: #selector(MainMenuActionHandler.menuChangeCrop(_:))) {
      PlayerCore.active.info.unsureCrop == $0.representedObject as? String
    }

    // -- rotation
    let rotationTitles = AppData.rotations.map { "\($0)\(Constants.String.degree)" }
    bind(menu: rotationMenu, withOptions: rotationTitles, objects: AppData.rotations, objectMap: nil, action: #selector(MainMenuActionHandler.menuChangeRotation(_:))) {
      PlayerCore.active.info.rotation == $0.representedObject as? Int
    }

    // -- flip and mirror
    flipMenu.delegate = self
    flip.action = #selector(MainMenuActionHandler.menuToggleFlip(_:))
    mirror.action = #selector(MainMenuActionHandler.menuToggleMirror(_:))

    // -- deinterlace
    deinterlace.action = #selector(MainMenuActionHandler.menuToggleDeinterlace(_:))

    // -- filter
    videoFilters.action = #selector(AppDelegate.showVideoFilterWindow(_:))

    // Audio menu

    audioMenu.delegate = self
    quickSettingsAudio.action = #selector(MainWindowController.menuShowAudioQuickSettings(_:))
    audioTrackMenu.delegate = self

    // - volume
    (increaseVolume.representedObject, decreaseVolume.representedObject, increaseVolumeSlightly.representedObject, decreaseVolumeSlightly.representedObject) = (5, -5, 1, -1)
    for item in [increaseVolume, decreaseVolume, increaseVolumeSlightly, decreaseVolumeSlightly] {
      item?.action = #selector(MainMenuActionHandler.menuChangeVolume(_:))
    }
    mute.action = #selector(MainMenuActionHandler.menuToggleMute(_:))

    // - audio delay
    (increaseAudioDelay.representedObject, decreaseAudioDelay.representedObject) = (0.5, -0.5)
    for item in [increaseAudioDelay, decreaseAudioDelay] {
      item?.action = #selector(MainMenuActionHandler.menuChangeAudioDelay(_:))
    }
    resetAudioDelay.action = #selector(MainMenuActionHandler.menuResetAudioDelay(_:))

    // - audio device
    audioDeviceMenu.delegate = self

    // - filters
    audioFilters.action = #selector(AppDelegate.showAudioFilterWindow(_:))

    // Subtitle

    subMenu.delegate = self
    quickSettingsSub.action = #selector(MainWindowController.menuShowSubQuickSettings(_:))
    loadExternalSub.action = #selector(MainMenuActionHandler.menuLoadExternalSub(_:))
    subTrackMenu.delegate = self
    secondSubTrackMenu.delegate = self

    findOnlineSub.action = #selector(MainMenuActionHandler.menuFindOnlineSub(_:))
    saveDownloadedSub.action = #selector(MainMenuActionHandler.saveDownloadedSub(_:))

    // - text size
    [increaseTextSize, decreaseTextSize, resetTextSize].forEach {
      $0.action = #selector(MainMenuActionHandler.menuChangeSubScale(_:))
    }

    // - delay
    (increaseSubDelay.representedObject, decreaseSubDelay.representedObject) = (0.5, -0.5)
    for item in [increaseSubDelay, decreaseSubDelay] {
      item?.action = #selector(MainMenuActionHandler.menuChangeSubDelay(_:))
    }
    resetSubDelay.action = #selector(MainMenuActionHandler.menuResetSubDelay(_:))

    // encoding
    let encodingTitles = AppData.encodings.map { $0.title }
    let encodingObjects = AppData.encodings.map { $0.code }
    bind(menu: encodingMenu, withOptions: encodingTitles, objects: encodingObjects, objectMap: nil, action: #selector(MainMenuActionHandler.menuSetSubEncoding(_:))) {
      PlayerCore.active.info.subEncoding == $0.representedObject as? String
    }
    subFont.action = #selector(MainMenuActionHandler.menuSubFont(_:))
    // Separate Auto from other encoding types
    encodingMenu.insertItem(NSMenuItem.separator(), at: 1)

    // Window

    if #available(OSX 10.12.2, *) {
      customTouchBar.action = #selector(NSApplication.toggleTouchBarCustomizationPalette(_:))
    } else {
      customTouchBar.isHidden = true
    }

    inspector.action = #selector(MainMenuActionHandler.menuShowInspector(_:))
    miniPlayer.action = #selector(MainMenuActionHandler.menuSwitchToMiniPlayer(_:))
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath else { return }

    switch keyPath {
    case Preference.Key.alwaysOpenInNewWindow:
      updateOpenMenuItems()
    default:
      return
    }

  }

  // MARK: - Update Menus

  private func updatePlaylist() {
    playlistMenu.removeAllItems()
    for (index, item) in PlayerCore.active.info.playlist.enumerated() {
      playlistMenu.addItem(withTitle: item.filenameForDisplay, action: #selector(MainMenuActionHandler.menuPlaylistItem(_:)),
                           tag: index, obj: nil, stateOn: item.isCurrent)
    }
  }

  private func updateChapterList() {
    chapterMenu.removeAllItems()
    let info = PlayerCore.active.info
    for (index, chapter) in info.chapters.enumerated() {
      let menuTitle = "\(chapter.time.stringRepresentation) - \(chapter.title)"
      let nextChapterTime = info.chapters.at(index+1)?.time ?? Constants.Time.infinite
      let isPlaying = info.videoPosition?.between(chapter.time, nextChapterTime) ?? false
      chapterMenu.addItem(withTitle: menuTitle, action: #selector(MainMenuActionHandler.menuChapterSwitch(_:)),
                          tag: index, obj: nil, stateOn: isPlaying)
    }
  }

  private func updateTracks(forMenu menu: NSMenu, type: MPVTrack.TrackType) {
    let info = PlayerCore.active.info
    menu.removeAllItems()
    let noTrackMenuItem = NSMenuItem(title: Constants.String.trackNone, action: #selector(MainMenuActionHandler.menuChangeTrack(_:)), keyEquivalent: "")
    noTrackMenuItem.representedObject = MPVTrack.emptyTrack(for: type)
    if info.trackId(type) == 0 {  // no track
      noTrackMenuItem.state = NSOnState
    }
    menu.addItem(noTrackMenuItem)
    for track in info.trackList(type) {
      menu.addItem(withTitle: track.readableTitle, action: #selector(MainMenuActionHandler.menuChangeTrack(_:)),
                             tag: nil, obj: (track, type), stateOn: track.id == info.trackId(type))
    }
  }

  private func updatePlaybackMenu() {
    pause.title = PlayerCore.active.info.isPaused ? Constants.String.resume : Constants.String.pause
    let isLoop = PlayerCore.active.mpvController.getFlag(MPVOption.PlaybackControl.loopFile)
    fileLoop.state = isLoop ? NSOnState : NSOffState
    let isPlaylistLoop = PlayerCore.active.mpvController.getString(MPVOption.PlaybackControl.loopPlaylist)
    playlistLoop.state = (isPlaylistLoop == "inf" || isPlaylistLoop == "force") ? NSOnState : NSOffState
  }

  private func updateVideoMenu() {
    let isInFullScreen = PlayerCore.active.mainWindow.isInFullScreen
    let isInPIP = PlayerCore.active.mainWindow.isInPIP
    let isOntop = PlayerCore.active.isInMiniPlayer ? PlayerCore.active.miniPlayer.isOntop : PlayerCore.active.mainWindow.isOntop
    alwaysOnTop.state = isOntop ? NSOnState : NSOffState
    deinterlace.state = PlayerCore.active.info.deinterlace ? NSOnState : NSOffState
    fullScreen.title = isInFullScreen ? Constants.String.exitFullScreen : Constants.String.fullScreen
    pictureInPicture?.title = isInPIP ? Constants.String.exitPIP : Constants.String.pip
  }

  private func updateAudioMenu() {
    let player = PlayerCore.active
    volumeIndicator.title = String(format: NSLocalizedString("menu.volume", comment: "Volume:"), Int(player.info.volume))
    audioDelayIndicator.title = String(format: NSLocalizedString("menu.audio_delay", comment: "Audio Delay:"), player.info.audioDelay)
  }

  private func updateAudioDevice() {
    let devices = PlayerCore.active.getAudioDevices()
    let currAudioDevice = PlayerCore.active.mpvController.getString(MPVProperty.audioDevice)
    audioDeviceMenu.removeAllItems()
    devices.forEach { d in
      let name = d["name"]!
      let desc = d["description"]!
      audioDeviceMenu.addItem(withTitle: "[\(desc)] \(name)", action: #selector(AppDelegate.menuSelectAudioDevice(_:)), tag: nil, obj: name, stateOn: name == currAudioDevice)
    }
  }

  private func updateFlipAndMirror() {
    let info = PlayerCore.active.info
    flip.state = info.flipFilter == nil ? NSOffState : NSOnState
    mirror.state = info.mirrorFilter == nil ? NSOffState : NSOnState
  }

  private func updateSubMenu() {
    let player = PlayerCore.active
    subDelayIndicator.title = String(format: NSLocalizedString("menu.sub_delay", comment: "Subtitle Delay:"), player.info.subDelay)
    
    let encodingCode = player.info.subEncoding ?? "auto"
    for encoding in AppData.encodings {
      if encoding.code == encodingCode {
        encodingMenu.item(withTitle: encoding.title)?.state = NSOnState
      }
    }
  }

  /**
   Bind a menu with a list of available options.
   @param menu         the NSMenu
   @param withOptions  option titles for each menu item, as an array
   @param objects      objects that will be bind to each menu item, as an array
   @param objectMap    alternatively, can pass a map like [title: object]
   @action             the action for each menu item
   @checkStateBlock    a block to set each menu item's state
   */
  private func bind(menu: NSMenu,
                    withOptions titles: [String]?, objects: [Any?]?,
                    objectMap: [String: Any?]?,
                    action: Selector?, checkStateBlock block: @escaping (NSMenuItem) -> Bool) {
    // if use title
    if let titles = titles {
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
    }
    // if use map
    if let objectMap = objectMap {
      for (title, obj) in objectMap {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.representedObject = obj
        menu.addItem(menuItem)
      }
    }
    // add to list
    menu.delegate = self
    menuBindingList.updateValue(block, forKey: menu)
  }

  private func updateOpenMenuItems() {
    if UserDefaults.standard.bool(forKey: Preference.Key.alwaysOpenInNewWindow) {
      open.title = stringForOpenAlternative
      openAlternative.title = stringForOpen
      openURL.title = stringForOpenURLAlternative
      openURLAlternative.title = stringForOpenURL
    } else {
      open.title = stringForOpen
      openAlternative.title = stringForOpenAlternative
      openURL.title = stringForOpenURL
      openURLAlternative.title = stringForOpenURLAlternative
    }
  }

  // MARK: - Menu delegate

  func menuWillOpen(_ menu: NSMenu) {
    if menu == playlistMenu {
      updatePlaylist()
    } else if menu == chapterMenu {
      updateChapterList()
    } else if menu == playbackMenu {
      updatePlaybackMenu()
    } else if menu == videoMenu {
      updateVideoMenu()
    } else if menu == videoTrackMenu {
      updateTracks(forMenu: menu, type: .video)
    } else if menu == flipMenu {
      updateFlipAndMirror()
    } else if menu == audioMenu {
      updateAudioMenu()
    } else if menu == audioTrackMenu {
      updateTracks(forMenu: menu, type: .audio)
    } else if menu == audioDeviceMenu {
      updateAudioDevice()
    } else if menu == subMenu {
      updateSubMenu()
    } else if menu == subTrackMenu {
      updateTracks(forMenu: menu, type: .sub)
    } else if menu == secondSubTrackMenu {
      updateTracks(forMenu: menu, type: .secondSub)
    }
    // check convinently binded menus
    if let checkEnableBlock = menuBindingList[menu] {
      for item in menu.items {
        item.state = checkEnableBlock(item) ? NSOnState : NSOffState
      }
    }
  }

}
