//
//  MenuController.swift
//  iina
//
//  Created by lhc on 31/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate func sameKeyAction(_ lhs: [String], _ rhs: [String], _ normalizeLastNum: Bool, _ numRange: ClosedRange<Double>?) -> (Bool, Double?) {
  guard lhs.count > 0 && lhs.count == rhs.count else {
    return (false, nil)
  }
  if normalizeLastNum {
    for i in 0..<lhs.count-1 {
      if lhs[i] != rhs[i] {
        return (false, nil)
      }
    }
    guard let ld = Double(lhs.last!), let rd = Double(rhs.last!) else {
      return (false, nil)
    }
    if let range = numRange {
      return (range.contains(ld), ld)
    } else {
      return (ld == rd, ld)
    }
  } else {
    for i in 0..<lhs.count {
      if lhs[i] != rhs[i] {
        return (false, nil)
      }
    }
  }
  return (true, nil)
}

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
  @IBOutlet weak var speedIndicator: NSMenuItem!
  @IBOutlet weak var speedUp: NSMenuItem!
  @IBOutlet weak var speedUpSlightly: NSMenuItem!
  @IBOutlet weak var speedDown: NSMenuItem!
  @IBOutlet weak var speedDownSlightly: NSMenuItem!
  @IBOutlet weak var speedReset: NSMenuItem!
  @IBOutlet weak var screenShot: NSMenuItem!
  @IBOutlet weak var gotoScreenshotFolder: NSMenuItem!
  @IBOutlet weak var advancedScreenShot: NSMenuItem!
  @IBOutlet weak var abLoop: NSMenuItem!
  @IBOutlet weak var fileLoop: NSMenuItem!
  @IBOutlet weak var playlistPanel: NSMenuItem!
  @IBOutlet weak var playlist: NSMenuItem!
  @IBOutlet weak var playlistLoop: NSMenuItem!
  @IBOutlet weak var playlistMenu: NSMenu!
  @IBOutlet weak var nextMedia: NSMenuItem!
  @IBOutlet weak var previousMedia: NSMenuItem!
  @IBOutlet weak var chapterPanel: NSMenuItem!
  @IBOutlet weak var nextChapter: NSMenuItem!
  @IBOutlet weak var previousChapter: NSMenuItem!
  @IBOutlet weak var chapter: NSMenuItem!
  @IBOutlet weak var chapterMenu: NSMenu!
  // Video
  @IBOutlet weak var videoMenu: NSMenu!
  @IBOutlet weak var quickSettingsVideo: NSMenuItem!
  @IBOutlet weak var cycleVideoTracks: NSMenuItem!
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
  @IBOutlet weak var delogo: NSMenuItem!
  @IBOutlet weak var videoFilters: NSMenuItem!
  @IBOutlet weak var savedVideoFiltersMenu: NSMenu!
  //Audio
  @IBOutlet weak var audioMenu: NSMenu!
  @IBOutlet weak var quickSettingsAudio: NSMenuItem!
  @IBOutlet weak var cycleAudioTracks: NSMenuItem!
  @IBOutlet weak var audioTrackMenu: NSMenu!
  @IBOutlet weak var volumeIndicator: NSMenuItem!
  @IBOutlet weak var increaseVolume: NSMenuItem!
  @IBOutlet weak var increaseVolumeSlightly: NSMenuItem!
  @IBOutlet weak var decreaseVolume: NSMenuItem!
  @IBOutlet weak var decreaseVolumeSlightly: NSMenuItem!
  @IBOutlet weak var mute: NSMenuItem!
  @IBOutlet weak var audioDelayIndicator: NSMenuItem!
  @IBOutlet weak var increaseAudioDelay: NSMenuItem!
  @IBOutlet weak var increaseAudioDelaySlightly: NSMenuItem!
  @IBOutlet weak var decreaseAudioDelay: NSMenuItem!
  @IBOutlet weak var decreaseAudioDelaySlightly: NSMenuItem!
  @IBOutlet weak var resetAudioDelay: NSMenuItem!
  @IBOutlet weak var audioFilters: NSMenuItem!
  @IBOutlet weak var audioDeviceMenu: NSMenu!
  @IBOutlet weak var savedAudioFiltersMenu: NSMenu!
  // Subtitle
  @IBOutlet weak var subMenu: NSMenu!
  @IBOutlet weak var quickSettingsSub: NSMenuItem!
  @IBOutlet weak var cycleSubtitles: NSMenuItem!
  @IBOutlet weak var subTrackMenu: NSMenu!
  @IBOutlet weak var secondSubTrackMenu: NSMenu!
  @IBOutlet weak var loadExternalSub: NSMenuItem!
  @IBOutlet weak var increaseTextSize: NSMenuItem!
  @IBOutlet weak var decreaseTextSize: NSMenuItem!
  @IBOutlet weak var resetTextSize: NSMenuItem!
  @IBOutlet weak var subDelayIndicator: NSMenuItem!
  @IBOutlet weak var increaseSubDelay: NSMenuItem!
  @IBOutlet weak var increaseSubDelaySlightly: NSMenuItem!
  @IBOutlet weak var decreaseSubDelay: NSMenuItem!
  @IBOutlet weak var decreaseSubDelaySlightly: NSMenuItem!
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

    [cycleSubtitles, cycleAudioTracks, cycleVideoTracks].forEach { item in
      item?.action = #selector(MainMenuActionHandler.menuCycleTrack(_:))
    }

    // File menu
    
    savePlaylist.action = #selector(MainMenuActionHandler.menuSavePlaylist(_:))
    deleteCurrentFile.action = #selector(MainMenuActionHandler.menuDeleteCurrentFile(_:))

    stringForOpen = open.title
    stringForOpenURL = openURL.title
    stringForOpenAlternative = openAlternative.title
    stringForOpenURLAlternative = openURLAlternative.title

    updateOpenMenuItems()
    UserDefaults.standard.addObserver(self, forKeyPath: Preference.Key.alwaysOpenInNewWindow.rawValue, options: [], context: nil)

    if Preference.bool(for: .enableCmdN) {
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

    // -- speed
    (speedUp.representedObject,
     speedUpSlightly.representedObject,
     speedDown.representedObject,
     speedDownSlightly.representedObject) = (2.0, 1.1, 0.5, 0.9)
    [speedUp, speedDown, speedUpSlightly, speedDownSlightly, speedReset].forEach { item in
      item?.action = #selector(MainMenuActionHandler.menuChangeSpeed(_:))
    }

    // -- screenshot
    screenShot.action = #selector(MainMenuActionHandler.menuSnapshot(_:))
    gotoScreenshotFolder.action = #selector(AppDelegate.menuOpenScreenshotFolder(_:))
    // advancedScreenShot

    // -- list and chapter
    abLoop.action = #selector(MainMenuActionHandler.menuABLoop(_:))
    fileLoop.action = #selector(MainMenuActionHandler.menuFileLoop(_:))
    playlistMenu.delegate = self
    chapterMenu.delegate = self
    playlistLoop.action = #selector(MainMenuActionHandler.menuPlaylistLoop(_:))
    playlistPanel.action = #selector(MainWindowController.menuShowPlaylistPanel(_:))
    chapterPanel.action = #selector(MainWindowController.menuShowChaptersPanel(_:))

    nextMedia.action = #selector(MainMenuActionHandler.menuNextMedia(_:))
    previousMedia.action = #selector(MainMenuActionHandler.menuPreviousMedia(_:))

    nextChapter.action = #selector(MainMenuActionHandler.menuNextChapter(_:))
    previousChapter.action = #selector(MainMenuActionHandler.menuPreviousChapter(_:))

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
    if #available(macOS 10.12, *) {
      pictureInPicture.action = #selector(MainWindowController.menuTogglePIP(_:))
    } else {
      videoMenu.removeItem(pictureInPicture)
    }
    alwaysOnTop.action = #selector(MainWindowController.menuAlwaysOnTop(_:))

    // -- aspect
    var aspectList = AppData.aspects
    // we need to set the represented object separately, since `Constants.String.default` may be localized.
    var aspectListObject = AppData.aspects
    aspectList.insert(Constants.String.default, at: 0)
    aspectListObject.insert("Default", at: 0)
    bind(menu: aspectMenu, withOptions: aspectList, objects: aspectListObject, objectMap: nil, action: #selector(MainMenuActionHandler.menuChangeAspect(_:))) {
      PlayerCore.active.info.unsureAspect == $0.representedObject as? String
    }

    // -- crop
    var cropList = AppData.aspects
    // same as aspectList above.
    var cropListForObject = AppData.aspects
    cropList.insert(Constants.String.none, at: 0)
    cropListForObject.insert("None", at: 0)
    bind(menu: cropMenu, withOptions: cropList, objects: cropListForObject, objectMap: nil, action: #selector(MainMenuActionHandler.menuChangeCrop(_:))) {
      return PlayerCore.active.info.unsureCrop == $0.representedObject as? String
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

    // -- delogo
    delogo.action = #selector(MainWindowController.menuSetDelogo(_:))

    // -- filter
    videoFilters.action = #selector(AppDelegate.showVideoFilterWindow(_:))

    savedVideoFiltersMenu.delegate = self
    updateSavedFilters(forType: MPVProperty.vf,
                       from: Preference.array(for: .savedVideoFilters)?.flatMap(SavedFilter.init(dict:)) ?? [])

    // Audio menu

    audioMenu.delegate = self
    quickSettingsAudio.action = #selector(MainWindowController.menuShowAudioQuickSettings(_:))
    audioTrackMenu.delegate = self

    // - volume
    (increaseVolume.representedObject,
     decreaseVolume.representedObject,
     increaseVolumeSlightly.representedObject,
     decreaseVolumeSlightly.representedObject) = (5, -5, 1, -1)
    [increaseVolume, decreaseVolume, increaseVolumeSlightly, decreaseVolumeSlightly].forEach { item in
      item?.action = #selector(MainMenuActionHandler.menuChangeVolume(_:))
    }
    mute.action = #selector(MainMenuActionHandler.menuToggleMute(_:))

    // - audio delay
    (increaseAudioDelay.representedObject,
     increaseAudioDelaySlightly.representedObject,
     decreaseAudioDelay.representedObject,
     decreaseAudioDelaySlightly.representedObject) = (0.5, 0.1, -0.5, -0.1)
    [increaseAudioDelay, decreaseAudioDelay, increaseAudioDelaySlightly, decreaseAudioDelaySlightly].forEach { item in
      item?.action = #selector(MainMenuActionHandler.menuChangeAudioDelay(_:))
    }
    resetAudioDelay.action = #selector(MainMenuActionHandler.menuResetAudioDelay(_:))

    // - audio device
    audioDeviceMenu.delegate = self

    // - filters
    audioFilters.action = #selector(AppDelegate.showAudioFilterWindow(_:))

    savedAudioFiltersMenu.delegate = self
    updateSavedFilters(forType: MPVProperty.af,
                       from: Preference.array(for: .savedAudioFilters)?.flatMap(SavedFilter.init(dict:)) ?? [])

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
    (increaseSubDelay.representedObject,
     increaseSubDelaySlightly.representedObject,
     decreaseSubDelay.representedObject,
     decreaseSubDelaySlightly.representedObject) = (0.5, 0.1, -0.5, -0.1)
    [increaseSubDelay, decreaseSubDelay, increaseSubDelaySlightly, decreaseSubDelaySlightly].forEach { item in
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

    if #available(macOS 10.12.2, *) {
      customTouchBar.action = #selector(NSApplication.toggleTouchBarCustomizationPalette(_:))
    } else {
      customTouchBar.isHidden = true
    }

    inspector.action = #selector(MainMenuActionHandler.menuShowInspector(_:))
    miniPlayer.action = #selector(MainWindowController.menuSwitchToMiniPlayer(_:))
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath else { return }

    switch keyPath {
    case Preference.Key.alwaysOpenInNewWindow.rawValue:
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
      noTrackMenuItem.state = .on
    }
    menu.addItem(noTrackMenuItem)
    for track in info.trackList(type) {
      menu.addItem(withTitle: track.readableTitle, action: #selector(MainMenuActionHandler.menuChangeTrack(_:)),
                             tag: nil, obj: (track, type), stateOn: track.id == info.trackId(type))
    }
  }

  private func updatePlaybackMenu() {
    let player = PlayerCore.active
    pause.title = player.info.isPaused ? Constants.String.resume : Constants.String.pause
    let isLoop = player.mpv.getFlag(MPVOption.PlaybackControl.loopFile)
    fileLoop.state = isLoop ? .on : .off
    let isPlaylistLoop = player.mpv.getString(MPVOption.PlaybackControl.loopPlaylist)
    playlistLoop.state = (isPlaylistLoop == "inf" || isPlaylistLoop == "force") ? .on : .off
    speedIndicator.title = String(format: NSLocalizedString("menu.speed", comment: "Speed:"), player.info.playSpeed)
  }

  private func updateVideoMenu() {
    let isInFullScreen = PlayerCore.active.mainWindow.isInFullScreen
    let isInPIP = PlayerCore.active.mainWindow.pipStatus == .inPIP
    let isOntop = PlayerCore.active.isInMiniPlayer ? PlayerCore.active.miniPlayer.isOntop : PlayerCore.active.mainWindow.isOntop
    let isDelogo = PlayerCore.active.info.delogoFiter != nil
    alwaysOnTop.state = isOntop ? .on : .off
    deinterlace.state = PlayerCore.active.info.deinterlace ? .on : .off
    fullScreen.title = isInFullScreen ? Constants.String.exitFullScreen : Constants.String.fullScreen
    pictureInPicture?.title = isInPIP ? Constants.String.exitPIP : Constants.String.pip
    delogo.state = isDelogo ? .on : .off
  }

  private func updateAudioMenu() {
    let player = PlayerCore.active
    volumeIndicator.title = String(format: NSLocalizedString("menu.volume", comment: "Volume:"), Int(player.info.volume))
    audioDelayIndicator.title = String(format: NSLocalizedString("menu.audio_delay", comment: "Audio Delay:"), player.info.audioDelay)
  }

  private func updateAudioDevice() {
    let devices = PlayerCore.active.getAudioDevices()
    let currAudioDevice = PlayerCore.active.mpv.getString(MPVProperty.audioDevice)
    audioDeviceMenu.removeAllItems()
    devices.forEach { d in
      let name = d["name"]!
      let desc = d["description"]!
      audioDeviceMenu.addItem(withTitle: "[\(desc)] \(name)", action: #selector(AppDelegate.menuSelectAudioDevice(_:)), tag: nil, obj: name, stateOn: name == currAudioDevice)
    }
  }

  private func updateFlipAndMirror() {
    let info = PlayerCore.active.info
    flip.state = info.flipFilter == nil ? .off : .on
    mirror.state = info.mirrorFilter == nil ? .off : .on
  }

  private func updateSubMenu() {
    let player = PlayerCore.active
    subDelayIndicator.title = String(format: NSLocalizedString("menu.sub_delay", comment: "Subtitle Delay:"), player.info.subDelay)
    
    let encodingCode = player.info.subEncoding ?? "auto"
    for encoding in AppData.encodings {
      if encoding.code == encodingCode {
        encodingMenu.item(withTitle: encoding.title)?.state = .on
      }
    }
  }

  func updateSavedFiltersMenu(type: String) {
    let filters = PlayerCore.active.mpv.getFilters(type)
    let menu: NSMenu! = type == MPVProperty.vf ? savedVideoFiltersMenu : savedAudioFiltersMenu
    for item in menu.items {
      if let string = (item.representedObject as? String) {
        item.state = filters.contains { $0.stringFormat == string } ? .on : .off
      }
    }
  }

  /**
   Bind a menu with a list of available options.

   - parameter menu:            the NSMenu
   - parameter withOptions:     option titles for each menu item, as an array
   - parameter objects:         objects that will be bind to each menu item, as an array
   - parameter objectMap:       alternatively, can pass a map like [title: object]
   - parameter action:          the action for each menu item
   - parameter checkStateBlock: a block to set each menu item's state
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
    if Preference.bool(for: .alwaysOpenInNewWindow) {
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
    } else if menu == savedVideoFiltersMenu {
      updateSavedFiltersMenu(type: MPVProperty.vf)
    } else if menu == savedAudioFiltersMenu {
      updateSavedFiltersMenu(type: MPVProperty.af)
    }
    // check convinently binded menus
    if let checkEnableBlock = menuBindingList[menu] {
      for item in menu.items {
        item.state = checkEnableBlock(item) ? .on : .off
      }
    }
  }

  // MARK: - Others

  func updateSavedFilters(forType type: String, from filters: [SavedFilter]) {
    let isVideo = type == MPVProperty.vf
    let menu: NSMenu! = isVideo ? savedVideoFiltersMenu : savedAudioFiltersMenu
    menu.removeAllItems()
    for filter in filters {
      let menuItem = NSMenuItem()
      menuItem.title = filter.name
      menuItem.action = isVideo ? #selector(MainWindowController.menuToggleVideoFilterString(_:)) : #selector(MainWindowController.menuToggleAudioFilterString(_:))
      menuItem.keyEquivalent = filter.shortcutKey
      menuItem.keyEquivalentModifierMask = filter.shortcutKeyModifiers
      menuItem.representedObject = filter.filterString
      menu.addItem(menuItem)
    }
  }

  func updateKeyEquivalentsFrom(_ keyBindings: [KeyMapping]) {
    let settings: [(NSMenuItem, Bool, [String], Bool, ClosedRange<Double>?, String?)] = [
      (deleteCurrentFile, true, ["delete-current-file"], false, nil, nil),
      (savePlaylist, true, ["save-playlist"], false, nil, nil),
      (quickSettingsVideo, true, ["video-panel"], false, nil, nil),
      (quickSettingsAudio, true, ["audio-panel"], false, nil, nil),
      (quickSettingsSub, true, ["sub-panel"], false, nil, nil),
      (playlistPanel, true, ["playlist-panel"], false, nil, nil),
      (chapterPanel, true, ["chapter-panel"], false, nil, nil),
      (findOnlineSub, true, ["find-online-subs"], false, nil, nil),
      (saveDownloadedSub, true, ["save-downloaded-sub"], false, nil, nil),
      (cycleVideoTracks, false, ["cycle", "video"], false, nil, nil),
      (cycleAudioTracks, false, ["cycle", "audio"], false, nil, nil),
      (cycleSubtitles, false, ["cycle", "sub"], false, nil, nil),
      (nextChapter, false, ["add", "chapter", "1"], false, nil, nil),
      (previousChapter, false, ["add", "chapter", "-1"], false, nil, nil),
      (pause, false, ["cycle", "pause"], false, nil, nil),
      (stop, false, ["stop"], false, nil, nil),
      (forward, false, ["seek", "5"], true, 5.0...10.0, "seek_forward"),
      (backward, false, ["seek", "-5"], true, -10.0...(-5.0), "seek_backward"),
      (nextFrame, false, ["frame-step"], false, nil, nil),
      (previousFrame, false, ["frame-back-step"], false, nil, nil),
      (nextMedia, false, ["playlist-next"], false, nil, nil),
      (previousMedia, false, ["playlist-prev"], false, nil, nil),
      (speedUp, false, ["multiply", "speed", "2.0"], true, nil, "speed_up"),
      (speedUpSlightly, false, ["multiply", "speed", "1.1"], true, 1.01...1.5, "speed_up"),
      (speedDown, false, ["multiply", "speed", "0.5"], true, nil, "speed_down"),
      (speedDownSlightly, false, ["multiply", "speed", "0.9"], true, 0.75...0.99, "speed_down"),
      (speedReset, false, ["set", "speed", "1.0"], true, nil, nil),
      (abLoop, false, ["ab-loop"], false, nil, nil),
      (fileLoop, false, ["cycle-values", "loop", "\"inf\"", "\"no\""], false, nil, nil),
      (screenShot, false, ["screenshot"], false, nil, nil),
      (mute, false, ["cycle", "mute"], false, nil, nil),
      (increaseVolume, false, ["add", "volume", "5"], true, 5.0...10.0, "volume_up"),
      (decreaseVolume, false, ["add", "volume", "-5"], true, -10.0...(-5.0), "volume_down"),
      (increaseVolumeSlightly, false, ["add", "volume", "1"], true, 1.0...2.0, "volume_up"),
      (decreaseVolumeSlightly, false, ["add", "volume", "-1"], true, -2.0...(-1.0), "volume_down"),
      (decreaseAudioDelay, false, ["add", "audio-delay", "-0.5"], true, nil, "audio_delay_down"),
      (decreaseAudioDelaySlightly, false, ["add", "audio-delay", "-0.1"], true, nil, "audio_delay_down"),
      (increaseAudioDelay, false, ["add", "audio-delay", "0.5"], true, nil, "audio_delay_up"),
      (increaseAudioDelaySlightly, false, ["add", "audio-delay", "0.1"], true, nil, "audio_delay_up"),
      (resetAudioDelay, false, ["set", "audio-delay", "0"], true, nil, nil),
      (decreaseSubDelay, false, ["add", "sub-delay", "-0.5"], true, nil, "sub_delay_down"),
      (decreaseSubDelaySlightly, false, ["add", "sub-delay", "-0.1"], true, nil, "sub_delay_down"),
      (increaseSubDelay, false, ["add", "sub-delay", "0.5"], true, nil, "sub_delay_up"),
      (increaseSubDelaySlightly, false, ["add", "sub-delay", "0.1"], true, nil, "sub_delay_up"),
      (resetSubDelay, false, ["set", "sub-delay", "0"], true, nil, nil)
    ]
    settings.forEach { (menuItem, isIINACmd, actions, normalizeLastNum, numRange, l10nKey) in
      var bound = false
      for kb in keyBindings {
        guard kb.isIINACommand == isIINACmd else { continue }
        let (sameAction, value) = sameKeyAction(kb.action, actions, normalizeLastNum, numRange)
        if sameAction, let (kEqv, kMdf) = KeyCodeHelper.macOSKeyEquivalent(from: kb.key) {
          menuItem.keyEquivalent = kEqv
          menuItem.keyEquivalentModifierMask = kMdf
          if let value = value, let l10nKey = l10nKey {
            menuItem.title = String(format: NSLocalizedString("menu." + l10nKey, comment: ""), abs(value))
            menuItem.representedObject = value
          }
          bound = true
          break
        }
      }
      if !bound {
        menuItem.keyEquivalent = ""
        menuItem.keyEquivalentModifierMask = []
      }
    }
  }
}
