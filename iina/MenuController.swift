//
//  MenuController.swift
//  iina
//
//  Created by lhc on 31/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate func sameKeyAction(_ lhs: [String], _ rhs: [String], _ normalizeLastNum: Bool, _ numRange: ClosedRange<Double>?) -> (Bool, Double?, Any?) {
  var lhs = lhs
  var extraData: Any? = nil
  if lhs.first == "seek", rhs.first == "seek", lhs.count > 2, let last = lhs.last {
    // This is a seek command that includes flags. Adjust the command before checking for a match.
    if lhs.count == 4 {
      // The original mpv seek command required that the keyframes and exact flags be passed as a
      // 3rd parameter. This is considered deprecated but still supported by mpv. Convert this to
      // the current command format by combining the flags using a "+" separator.
      lhs[2] = "\(lhs[2])+\(lhs[3])"
      lhs = [String](lhs.dropLast())
    }
    var splitArray = last.split(whereSeparator: { $0 == "+" })
    if let index = splitArray.firstIndex(of: "relative") {
      // The mpv seek command seeks relative to current position by default. Because of that the
      // seek command used by menu items does not specify this flag. Ignore it when checking for a
      // match.
      splitArray.remove(at: index)
    }
    if let index = splitArray.firstIndex(of: "exact") {
      // Alter the behavior of the menu item by passing this flag on the side as extra data.
      splitArray.remove(at: index)
      extraData = Preference.SeekOption.exact
    }
    // NOTE at this time PlayerCore does not support specifying the keyframes flag, so it can't
    // be specified on the side as extra data as is done for exact. Although the mpv seek command
    // normally defaults to seeking by keyframes, that default can be changed by the hr-seek option.
    // When hr-seek has been set to enable exact seeks by default the keyframes flag will override
    // that default.
    if splitArray.isEmpty {
      // All flags were recognized as ones we do not need to consider when checking for a match.
      lhs = [String](lhs.dropLast())
    }
  }
  guard lhs.count > 0 && lhs.count == rhs.count else {
    return (false, nil, nil)
  }
  if normalizeLastNum {
    for i in 0..<lhs.count-1 {
      if lhs[i] != rhs[i] {
        return (false, nil, nil)
      }
    }
    guard let ld = Double(lhs.last!), let rd = Double(rhs.last!) else {
      return (false, nil, nil)
    }
    if let range = numRange {
      return (range.contains(ld), ld, extraData)
    } else {
      return (ld == rd, ld, extraData)
    }
  } else {
    for i in 0..<lhs.count {
      if lhs[i] != rhs[i] {
        return (false, nil, nil)
      }
    }
  }
  return (true, nil, nil)
}

class MenuController: NSObject, NSMenuDelegate {

  /** For convenient bindings. see `bind(...)` below. [menu: check state block] */
  private var menuBindingList: [NSMenu: (NSMenuItem) -> Bool] = [:]

  private var stringForOpen: String!
  private var stringForOpenAlternative: String!
  private var stringForOpenURL: String!
  private var stringForOpenURLAlternative: String!

  // File
  @IBOutlet weak var fileMenu: NSMenu!
  @IBOutlet weak var open: NSMenuItem!
  @IBOutlet weak var openAlternative: NSMenuItem!
  @IBOutlet weak var openURL: NSMenuItem!
  @IBOutlet weak var openURLAlternative: NSMenuItem!
  @IBOutlet weak var savePlaylist: NSMenuItem!
  @IBOutlet weak var showCurrentFileInFinder: NSMenuItem!
  @IBOutlet weak var deleteCurrentFile: NSMenuItem!
  @IBOutlet weak var newWindow: NSMenuItem!
  @IBOutlet weak var newWindowSeparator: NSMenuItem!
  @IBOutlet weak var otherKeyBindingsMenu: NSMenu!
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
  @IBOutlet weak var screenshot: NSMenuItem!
  @IBOutlet weak var gotoScreenshotFolder: NSMenuItem!
  @IBOutlet weak var advancedScreenshot: NSMenuItem!
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
  @IBOutlet weak var loadExternalAudio: NSMenuItem!
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
  @IBOutlet weak var hideSubtitles: NSMenuItem!
  @IBOutlet weak var hideSecondSubtitles: NSMenuItem!
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
  @IBOutlet weak var onlineSubSourceMenu: NSMenu!
  @IBOutlet weak var saveDownloadedSub: NSMenuItem!
  // Plugin
  @IBOutlet weak var pluginMenu: NSMenu!
  @IBOutlet weak var pluginMenuItem: NSMenuItem!
  // Window
  @IBOutlet weak var customTouchBar: NSMenuItem!
  @IBOutlet weak var inspector: NSMenuItem!
  @IBOutlet weak var miniPlayer: NSMenuItem!

  /// If `true` then all menu items are disabled.
  private var isDisabled = false

  // MARK: - Construct Menus

  func bindMenuItems() {

    [cycleSubtitles, cycleAudioTracks, cycleVideoTracks].forEach { item in
      item?.action = #selector(MainMenuActionHandler.menuCycleTrack(_:))
    }

    // File menu

    fileMenu.delegate = self

    stringForOpen = open.title
    stringForOpenURL = openURL.title
    stringForOpenAlternative = openAlternative.title
    stringForOpenURLAlternative = openURLAlternative.title

    savePlaylist.action = #selector(MainMenuActionHandler.menuSavePlaylist(_:))
    showCurrentFileInFinder.action = #selector(MainMenuActionHandler.menuShowCurrentFileInFinder(_:))
    deleteCurrentFile.action = #selector(MainMenuActionHandler.menuDeleteCurrentFile(_:))

    if Preference.bool(for: .enableCmdN) {
      newWindowSeparator.isHidden = false
      newWindow.isHidden = false
    }

    otherKeyBindingsMenu.delegate = self

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
    [speedUp, speedDown, speedUpSlightly, speedDownSlightly, speedReset].forEach { item in
      item?.action = #selector(MainMenuActionHandler.menuChangeSpeed(_:))
    }

    // -- screenshot
    screenshot.action = #selector(MainMenuActionHandler.menuSnapshot(_:))
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
    pictureInPicture.action = #selector(MainWindowController.menuTogglePIP(_:))
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
    // Allow custom crop size.
    cropList.append(Constants.String.custom)
    cropListForObject.append("Custom")
    bind(menu: cropMenu, withOptions: cropList, objects: cropListForObject, objectMap: nil, action: #selector(MainMenuActionHandler.menuChangeCrop(_:))) {
      return PlayerCore.active.info.unsureCrop == $0.representedObject as? String
    }
    // Separate "Custom..." from other crop sizes.
    cropMenu.insertItem(NSMenuItem.separator(), at: 1 + AppData.aspects.count)

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
                       from: Preference.array(for: .savedVideoFilters)?.compactMap(SavedFilter.init(dict:)) ?? [])

    // Audio menu

    audioMenu.delegate = self
    quickSettingsAudio.action = #selector(MainWindowController.menuShowAudioQuickSettings(_:))
    audioTrackMenu.delegate = self
    loadExternalAudio.action = #selector(MainMenuActionHandler.menuLoadExternalAudio(_:))

    // - volume
    [increaseVolume, decreaseVolume, increaseVolumeSlightly, decreaseVolumeSlightly].forEach { item in
      item?.action = #selector(MainMenuActionHandler.menuChangeVolume(_:))
    }
    mute.action = #selector(MainMenuActionHandler.menuToggleMute(_:))

    // - audio delay
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
                       from: Preference.array(for: .savedAudioFilters)?.compactMap(SavedFilter.init(dict:)) ?? [])

    // Subtitle

    subMenu.delegate = self
    quickSettingsSub.action = #selector(MainWindowController.menuShowSubQuickSettings(_:))
    loadExternalSub.action = #selector(MainMenuActionHandler.menuLoadExternalSub(_:))
    subTrackMenu.delegate = self
    hideSubtitles.action = #selector(MainMenuActionHandler.menuToggleSubVisibility(_:))
    hideSecondSubtitles.action = #selector(MainMenuActionHandler.menuToggleSecondSubVisibility(_:))
    secondSubTrackMenu.delegate = self

    findOnlineSub.action = #selector(MainMenuActionHandler.menuFindOnlineSub(_:))
    saveDownloadedSub.action = #selector(MainMenuActionHandler.saveDownloadedSub(_:))

    onlineSubSourceMenu.delegate = self

    // - text size
    [increaseTextSize, decreaseTextSize, resetTextSize].forEach {
      $0.action = #selector(MainMenuActionHandler.menuChangeSubScale(_:))
    }

    // - delay
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

    // Plugin

    if IINA_ENABLE_PLUGIN_SYSTEM {
      pluginMenu.delegate = self
    } else {
      pluginMenuItem.isHidden = true
    }

    // Window

    customTouchBar.action = #selector(NSApplication.toggleTouchBarCustomizationPalette(_:))

    inspector.action = #selector(MainMenuActionHandler.menuShowInspector(_:))
    miniPlayer.action = #selector(MainWindowController.menuSwitchToMiniPlayer(_:))
  }

  // MARK: - Update Menus

  func updateOtherKeyBindings(replacingAllWith newItems: [NSMenuItem]) {
    otherKeyBindingsMenu.removeAllItems()
    for item in newItems {
      otherKeyBindingsMenu.addItem(item)
    }
  }

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
    let chapters = info.chapters
    let padder = { (time: String) -> String in
      let standard = (chapters.last?.time.stringRepresentation ?? "").reversed()
      return String((time.reversed() + standard[standard.index(standard.startIndex, offsetBy: time.count)...].map {
        $0 == ":" ? ":" : "0"
      }).reversed())
    }
    for (index, chapter) in chapters.enumerated() {
      let menuTitle = "\(padder(chapter.time.stringRepresentation)) – \(chapter.title)"
      let nextChapterTime = chapters[at: index+1]?.time ?? Constants.Time.infinite
      let isPlaying = info.videoPosition?.between(chapter.time, nextChapterTime) ?? false
      let menuItem = NSMenuItem(title: menuTitle, action: #selector(MainMenuActionHandler.menuChapterSwitch(_:)), keyEquivalent: "")
      menuItem.tag = index
      menuItem.state = isPlaying ? .on : .off
      menuItem.attributedTitle = NSAttributedString(string: menuTitle, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)])
      chapterMenu.addItem(menuItem)
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
    let isDisplayingPlaylist = player.mainWindow.sideBarStatus == .playlist &&
          player.mainWindow.playlistView.currentTab == .playlist
    playlistPanel?.title = isDisplayingPlaylist ? Constants.String.hidePlaylistPanel : Constants.String.playlistPanel
    let isDisplayingChapters = player.mainWindow.sideBarStatus == .playlist &&
          player.mainWindow.playlistView.currentTab == .chapters
    chapterPanel?.title = isDisplayingChapters ? Constants.String.hideChaptersPanel : Constants.String.chaptersPanel
    pause.title = player.info.state == .paused ? Constants.String.resume : Constants.String.pause
    abLoop.state = player.isABLoopActive ? .on : .off
    let loopMode = player.getLoopMode()
    fileLoop.state = loopMode == .file ? .on : .off
    playlistLoop.state = loopMode == .playlist ? .on : .off
    let speed = player.info.playSpeed.string
    speedIndicator.title = String(format: NSLocalizedString("menu.speed", comment: "Speed:"), speed)
  }

  private func updateVideoMenu() {
    let player = PlayerCore.active
    let isDisplayingSettings = player.mainWindow.sideBarStatus == .settings &&
          player.mainWindow.quickSettingView.currentTab == .video
    quickSettingsVideo?.title = isDisplayingSettings ? Constants.String.hideVideoPanel :
        Constants.String.videoPanel
    let isInFullScreen = player.mainWindow.fsState.isFullscreen
    let isInPIP = player.mainWindow.pipStatus == .inPIP
    let isOntop = player.isInMiniPlayer ? player.miniPlayer.isOntop : player.mainWindow.isOntop
    let isDelogo = player.info.delogoFilter != nil
    alwaysOnTop.state = isOntop ? .on : .off
    deinterlace.state = player.info.deinterlace ? .on : .off
    fullScreen.title = isInFullScreen ? Constants.String.exitFullScreen : Constants.String.fullScreen
    pictureInPicture?.title = isInPIP ? Constants.String.exitPIP : Constants.String.pip
    miniPlayer.title = player.isInMiniPlayer ? Constants.String.exitMiniPlayer : Constants.String.miniPlayer
    delogo.state = isDelogo ? .on : .off
  }

  private func updateAudioMenu() {
    let player = PlayerCore.active
    let isDisplayingSettings = player.mainWindow.sideBarStatus == .settings &&
          player.mainWindow.quickSettingView.currentTab == .audio
    quickSettingsAudio?.title = isDisplayingSettings ? Constants.String.hideAudioPanel :
        Constants.String.audioPanel
    let volFmtString: String
    if player.info.isMuted {
      volFmtString = NSLocalizedString("menu.volume_muted", comment: "Volume: (Muted)")
      mute.state = .on
    } else {
      volFmtString = NSLocalizedString("menu.volume", comment: "Volume:")
      mute.state = .off
    }
    volumeIndicator.title = String(format: volFmtString, Int(player.info.volume))
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
    let isDisplayingSettings = player.mainWindow.sideBarStatus == .settings &&
          player.mainWindow.quickSettingView.currentTab == .sub
    quickSettingsSub?.title = isDisplayingSettings ? Constants.String.hideSubtitlesPanel :
        Constants.String.subtitlesPanel
    hideSubtitles.title = player.info.isSubVisible ? Constants.String.hideSubtitles :
        Constants.String.showSubtitles
    hideSecondSubtitles.title = player.info.isSecondSubVisible ? Constants.String.hideSecondSubtitles :
        Constants.String.showSecondSubtitles
    subDelayIndicator.title = String(format: NSLocalizedString("menu.sub_delay", comment: "Subtitle Delay:"), player.info.subDelay)

    let encodingCode = player.info.subEncoding ?? "auto"
    for encoding in AppData.encodings {
      if encoding.code == encodingCode {
        encodingMenu.item(withTitle: encoding.title)?.state = .on
      }
    }

    let providerID = Preference.string(for: .onlineSubProvider) ?? OnlineSubtitle.Providers.openSub.id
    let providerName = OnlineSubtitle.Providers.nameForID(providerID)
    findOnlineSub.title = String(format: Constants.String.findOnlineSubtitles, providerName)
  }

  private func updateOnlineSubSourceMenu() {
    OnlineSubtitle.populateMenu(onlineSubSourceMenu,
                                action: #selector(MainMenuActionHandler.menuFindOnlineSub(_:)))
  }

  func updateSavedFiltersMenu(type: String) {
    let filters = PlayerCore.active.mpv.getFilters(type)
    let menu: NSMenu! = type == MPVProperty.vf ? savedVideoFiltersMenu : savedAudioFiltersMenu
    for item in menu.items {
      if let string = (item.representedObject as? String), let asObject = MPVFilter(rawString: string) {
        // Filters that support multiple parameters have more than one valid string representation.
        // Must compare filters using their object representation.
        item.state = filters.contains { $0 == asObject } ? .on : .off
      }
    }
  }

  func updatePluginMenu() {
    pluginMenu.removeAllItems()
    pluginMenu.addItem(withTitle: "Manage Plugins…")
    pluginMenu.addItem(.separator())

    let developerTool = NSMenuItem()
    developerTool.title = "Developer Tool"
    developerTool.submenu = NSMenu()

    var errorList: [(String, String)] = []
    for (index, instance) in PlayerCore.active.plugins.enumerated() {
      var counter = 0
      var rootMenu: NSMenu! = pluginMenu
      let menuItems = (instance.plugin.globalInstance?.menuItems ?? []) + instance.menuItems
      if menuItems.isEmpty { continue }
      
      if index != 0 {
        pluginMenu.addItem(.separator())
      }
      pluginMenu.addItem(withTitle: instance.plugin.name, enabled: false)
      
      for item in menuItems {
        if counter == 5 {
          Logger.log("Please avoid adding too much first-level menu items. IINA will only display the first 5 of them.",
                     level: .warning, subsystem: instance.subsystem)
          let moreItem = NSMenuItem()
          moreItem.title = "More…"
          rootMenu = NSMenu()
          moreItem.submenu = rootMenu
          pluginMenu.addItem(moreItem)
        }
        add(menuItemDef: item, to: rootMenu, for: instance, errorList: &errorList)
        counter += 1
      }

      if #available(macOS 12.0, *) {
        let devToolItem = NSMenuItem()
        devToolItem.title = instance.plugin.name
        developerTool.submenu?.addItem(
          menuItem(forPluginInstance: instance, tag: JavasctiptDevTool.JSMenuItemInstance))
        if let globalInst = instance.plugin.globalInstance {
          developerTool.submenu?.addItem(
            menuItem(forPluginInstance: globalInst, tag: JavasctiptDevTool.JSMenuItemInstance))
        }
      }
    }

    if errorList.count > 0 {
      pluginMenu.insertItem(
        NSMenuItem(title: "⚠︎ Conflicting key shortcuts…", action: nil, keyEquivalent: ""),
        at: 0)
    }

    pluginMenu.addItem(.separator())
    if #available(macOS 12.0, *) {
      pluginMenu.addItem(developerTool)
    }
    pluginMenu.addItem(withTitle: "Reload all plugins", action: #selector(MainMenuActionHandler.reloadAllPlugins(_:)), keyEquivalent: "")
  }

  @discardableResult
  private func add(menuItemDef item: JavascriptPluginMenuItem,
                   to menu: NSMenu,
                   for plugin: JavascriptPluginInstance,
                   errorList: inout [(String, String)]) -> NSMenuItem {
    if (item.isSeparator) {
      let item = NSMenuItem.separator()
      menu.addItem(item)
      return item
    }

    let menuItem: NSMenuItem
    if item.action == nil {
      menuItem = menu.addItem(withTitle: item.title, action: nil, target: plugin, obj: item)
    } else {
      menuItem = menu.addItem(withTitle: item.title,
                              action: #selector(plugin.menuItemAction(_:)),
                              target: plugin,
                              obj: item)
    }

    menuItem.isEnabled = item.enabled
    menuItem.state = item.selected ? .on : .off
    if let key = item.keyBinding {
      if PlayerCore.keyBindings[key] != nil {
        errorList.append((plugin.plugin.name, key))
      } else if let (kEqv, kMdf) = KeyCodeHelper.macOSKeyEquivalent(from: key) {
        menuItem.keyEquivalent = kEqv
        menuItem.keyEquivalentModifierMask = kMdf
      }
    }
    if !item.items.isEmpty {
      menuItem.submenu = NSMenu()
      for submenuItem in item.items {
        add(menuItemDef: submenuItem, to: menuItem.submenu!, for: plugin, errorList: &errorList)
      }
    }
    item.nsMenuItem = menuItem
    return menuItem
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
        Logger.log("different object count when binding menu", level: .error)
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
    if PlayerCore.playing.count == 0 {
      open.title = stringForOpen
      openAlternative.title = stringForOpen
      openURL.title = stringForOpenURL
      openURLAlternative.title = stringForOpenURL
    } else {
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
  }

  // MARK: - Menu delegate

  func menuWillOpen(_ menu: NSMenu) {
    // If all menu items are disabled do not update the menus.
    guard !isDisabled else { return }
    switch menu {
    case fileMenu:
      updateOpenMenuItems()
    case playlistMenu:
      updatePlaylist()
    case chapterMenu:
      updateChapterList()
    case playbackMenu:
      updatePlaybackMenu()
    case videoMenu:
      updateVideoMenu()
    case videoTrackMenu:
      updateTracks(forMenu: menu, type: .video)
    case flipMenu:
      updateFlipAndMirror()
    case audioMenu:
      updateAudioMenu()
    case audioTrackMenu:
      updateTracks(forMenu: menu, type: .audio)
    case audioDeviceMenu:
      updateAudioDevice()
    case subMenu:
      updateSubMenu()
    case subTrackMenu:
      updateTracks(forMenu: menu, type: .sub)
    case secondSubTrackMenu:
      updateTracks(forMenu: menu, type: .secondSub)
    case onlineSubSourceMenu:
      updateOnlineSubSourceMenu()
    case savedVideoFiltersMenu:
      updateSavedFiltersMenu(type: MPVProperty.vf)
    case savedAudioFiltersMenu:
      updateSavedFiltersMenu(type: MPVProperty.af)
    case pluginMenu:
      updatePluginMenu()
    default: break
    }
    // check conveniently bound menus
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
      menuItem.action = isVideo ? #selector(MainMenuActionHandler.menuToggleVideoFilterString(_:)) : #selector(MainMenuActionHandler.menuToggleAudioFilterString(_:))
      menuItem.keyEquivalent = filter.shortcutKey
      menuItem.keyEquivalentModifierMask = filter.shortcutKeyModifiers
      menuItem.representedObject = filter.filterString
      menu.addItem(menuItem)
    }
  }

  func updateKeyEquivalentsFrom(_ keyBindings: [KeyMapping]) {
    let settings: [(NSMenuItem, Bool, [String], Bool, ClosedRange<Double>?, String?)] = [
      (showCurrentFileInFinder, true, [IINACommand.showCurrentFileInFinder.rawValue], false, nil, nil),
      (deleteCurrentFile, true, [IINACommand.deleteCurrentFile.rawValue], false, nil, nil),
      (savePlaylist, true, [IINACommand.saveCurrentPlaylist.rawValue], false, nil, nil),
      (quickSettingsVideo, true, [IINACommand.videoPanel.rawValue], false, nil, nil),
      (quickSettingsAudio, true, [IINACommand.audioPanel.rawValue], false, nil, nil),
      (quickSettingsSub, true, [IINACommand.subPanel.rawValue], false, nil, nil),
      (playlistPanel, true, [IINACommand.playlistPanel.rawValue], false, nil, nil),
      (chapterPanel, true, [IINACommand.chapterPanel.rawValue], false, nil, nil),
      (findOnlineSub, true, [IINACommand.findOnlineSubs.rawValue], false, nil, nil),
      (saveDownloadedSub, true, [IINACommand.saveDownloadedSub.rawValue], false, nil, nil),
      (flip, true, [IINACommand.flip.rawValue], false, nil, nil),
      (mirror, true, [IINACommand.mirror.rawValue], false, nil, nil),
      (biggerSize, true, [IINACommand.biggerWindow.rawValue], false, nil, nil),
      (smallerSize, true, [IINACommand.smallerWindow.rawValue], false, nil, nil),
      (fitToScreen, true, [IINACommand.fitToScreen.rawValue], false, nil, nil),
      (miniPlayer, true, [IINACommand.toggleMusicMode.rawValue], false, nil, nil),
      (pictureInPicture, true, [IINACommand.togglePIP.rawValue], false, nil, nil),
      (cycleVideoTracks, false, ["cycle", "video"], false, nil, nil),
      (cycleAudioTracks, false, ["cycle", "audio"], false, nil, nil),
      (cycleSubtitles, false, ["cycle", "sub"], false, nil, nil),
      (nextChapter, false, ["add", "chapter", "1"], false, nil, nil),
      (previousChapter, false, ["add", "chapter", "-1"], false, nil, nil),
      (pause, false, ["cycle", "pause"], false, nil, nil),
      (stop, false, ["stop"], false, nil, nil),
      (forward, false, ["seek", "5"], true, 5.0...60.0, "seek_forward"),
      (backward, false, ["seek", "-5"], true, -60.0...(-5.0), "seek_backward"),
      (nextFrame, false, ["frame-step"], false, nil, nil),
      (previousFrame, false, ["frame-back-step"], false, nil, nil),
      (nextMedia, false, ["playlist-next"], false, nil, nil),
      (previousMedia, false, ["playlist-prev"], false, nil, nil),
      (speedUp, false, ["multiply", "speed", "2.0"], true, 1.5...3.0, "speed_up"),
      (speedUpSlightly, false, ["multiply", "speed", "1.1"], true, 1.01...1.49, "speed_up"),
      (speedDown, false, ["multiply", "speed", "0.5"], true, 0...0.7, "speed_down"),
      (speedDownSlightly, false, ["multiply", "speed", "0.9"], true, 0.71...0.99, "speed_down"),
      (speedReset, false, ["set", "speed", "1.0"], true, nil, nil),
      (abLoop, false, ["ab-loop"], false, nil, nil),
      (fileLoop, false, ["cycle-values", "loop", "\"inf\"", "\"no\""], false, nil, nil),
      (screenshot, false, ["screenshot"], false, nil, nil),
      (halfSize, false, ["set", "window-scale", "0.5"], true, nil, nil),
      (normalSize, false, ["set", "window-scale", "1"], true, nil, nil),
      (doubleSize, false, ["set", "window-scale", "2"], true, nil, nil),
      (fullScreen, false, ["cycle", "fullscreen"], false, nil, nil),
      (alwaysOnTop, false, ["cycle", "ontop"], false, nil, nil),
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
      (hideSubtitles, false, ["cycle", "sub-visibility"], false, nil, nil),
      (hideSecondSubtitles, false, ["cycle", "secondary-sub-visibility"], false, nil, nil),
      (decreaseSubDelay, false, ["add", "sub-delay", "-0.5"], true, nil, "sub_delay_down"),
      (decreaseSubDelaySlightly, false, ["add", "sub-delay", "-0.1"], true, nil, "sub_delay_down"),
      (increaseSubDelay, false, ["add", "sub-delay", "0.5"], true, nil, "sub_delay_up"),
      (increaseSubDelaySlightly, false, ["add", "sub-delay", "0.1"], true, nil, "sub_delay_up"),
      (resetSubDelay, false, ["set", "sub-delay", "0"], true, nil, nil),
      (increaseTextSize, false, ["multiply", "sub-scale", "1.1"], true, 1.01...1.49, nil),
      (decreaseTextSize, false, ["multiply", "sub-scale", "0.9"], true, 0.71...0.99, nil),
      (resetTextSize, false, ["set", "sub-scale", "1"], true, nil, nil),
      (alwaysOnTop, false, ["cycle", "ontop"], false, nil, nil),
      (fullScreen, false, ["cycle", "fullscreen"], false, nil, nil),
    ]

    var otherActionsMenuItems: [NSMenuItem] = []

    /// Loop over all the list of menu items which can be matched with one or more `KeyMapping`s
    settings.forEach { (menuItem, isIINACmd, actions, normalizeLastNum, numRange, l10nKey) in
      /// Loop over all key bindings. Examine each binding's action and see if it is equivalent to `menuItem`'s action
      var didBindMenuItem = false
      for kb in keyBindings {
        guard kb.isIINACommand == isIINACmd else { continue }
        let (sameAction, value, extraData) = sameKeyAction(kb.action, actions, normalizeLastNum, numRange)
        if sameAction, let (kEqv, kMdf) = KeyCodeHelper.macOSKeyEquivalent(from: kb.normalizedMpvKey) {
          /// If we got here, `KeyMapping`'s action qualifies for being bound to `menuItem`.
          let kbMenuItem: NSMenuItem

          if didBindMenuItem {
            /// This `KeyMapping` matches a menu item whose key equivalent was set from a different `KeyMapping`.
            /// There can only be one key equivalent per menu item, so we will create a duplicate menu item and put it in a hidden menu.
            kbMenuItem = NSMenuItem(title: menuItem.title, action: menuItem.action, keyEquivalent: "")
            kbMenuItem.tag = menuItem.tag
            otherActionsMenuItems.append(kbMenuItem)
          } else {
            /// This `KeyMapping` was the first match found for this menu item.
            kbMenuItem = menuItem
            didBindMenuItem = true
          }
          updateMenuItem(kbMenuItem, kEqv: kEqv, kMdf: kMdf, l10nKey: l10nKey, value: value, extraData: extraData)
        }
      }

      if !didBindMenuItem {
        // Need to regenerate `title` and `representedObject` from their default values.
        // This is needed for the case where the menu item previously matched to a key binding, but now there is no match.
        // Obviously this is a little kludgey, but it avoids having to do a big refactor and/or writing a bunch of new code.
        let (_, value, extraData) = sameKeyAction(actions, actions, normalizeLastNum, numRange)
        updateMenuItem(menuItem, kEqv: "", kMdf: [], l10nKey: l10nKey, value: value, extraData: extraData)
      }
    }

    updateOtherKeyBindings(replacingAllWith: otherActionsMenuItems)
  }

  /// Updates the key equivalent of the given menu item.
  /// May also update its title and representedObject, for items which can change based on some param value(s).
  private func updateMenuItem(_ menuItem: NSMenuItem, kEqv: String, kMdf: NSEvent.ModifierFlags, l10nKey: String?, value: Double?, extraData: Any?) {
    menuItem.keyEquivalent = kEqv
    menuItem.keyEquivalentModifierMask = kMdf

    if let value = value, let l10nKey = l10nKey {
      let valObj: CVarArg
      switch l10nKey {
      case "speed_up",
        "speed_down":
        // Title format expects arg type: String
        valObj = abs(value).string
      default:
        // Title format expects numeric arg
        valObj = abs(value)
      }
      menuItem.title = String(format: NSLocalizedString("menu." + l10nKey, comment: ""), valObj)
      if let extraData = extraData {
        menuItem.representedObject = (value, extraData)
      } else {
        menuItem.representedObject = value
      }
    } else {
      // Clear any previous value
      menuItem.representedObject = nil
    }
  }

  /// Disable all menu items.
  ///
  /// This method is used during application termination to stop any further input from the user.
  func disableAllMenus() {
    isDisabled = true
    disableAllMenuItems(NSApp.mainMenu!)
  }

  /// Disable all menu items in the given menu and any submenus.
  ///
  /// This method recursively descends through the entire tree of menu items disabling all items.
  /// - Parameter menu: Menu to disable
  private func disableAllMenuItems(_ menu: NSMenu) {
    for item in menu.items {
      if item.hasSubmenu {
        disableAllMenuItems(item.submenu!)
      }
      item.isEnabled = false
    }
  }
}
