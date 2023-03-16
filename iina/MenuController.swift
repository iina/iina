//
//  MenuController.swift
//  iina
//
//  Created by lhc on 31/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate func sameKeyAction(_ lhs: [String], _ rhs: [String], _ normalizeLastNum: Bool, _ numRange: ClosedRange<Double>?) -> (Bool, Double?) {
  var lhs = lhs
  if lhs.first == "seek" && (lhs.last == "exact" || lhs.last == "keyframe") {
    lhs = [String](lhs.dropLast())
  }
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

  /** For convenient bindings. see `bind(...)` below. [menu: check state block] */
  private var menuBindingList: [NSMenu: (NSMenuItem) -> Bool] = [:]

  // If too many menu items are added to the Plugin menu (may be hidden)
  private var pluginErrorNotice = NSMenuItem(title: "⚠︎ Conflicting key shortcuts…", action: nil, keyEquivalent: "")

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
      item?.action = #selector(PlayerWindowController.menuCycleTrack(_:))
    }

    // File menu

    fileMenu.delegate = self

    stringForOpen = open.title
    stringForOpenURL = openURL.title
    stringForOpenAlternative = openAlternative.title
    stringForOpenURLAlternative = openURLAlternative.title

    savePlaylist.action = #selector(PlayerWindowController.menuSavePlaylist(_:))
    deleteCurrentFile.action = #selector(PlayerWindowController.menuDeleteCurrentFile(_:))

    if Preference.bool(for: .enableCmdN) {
      newWindowSeparator.isHidden = false
      newWindow.isHidden = false
    }

    // Playback menu

    playbackMenu.delegate = self

    pause.action = #selector(PlayerWindowController.menuTogglePause(_:))
    stop.action = #selector(PlayerWindowController.menuStop(_:))

    // -- seeking
    forward.action = #selector(PlayerWindowController.menuStep(_:))
    nextFrame.action = #selector(PlayerWindowController.menuStepFrame(_:))
    backward.action = #selector(PlayerWindowController.menuStep(_:))
    previousFrame.action = #selector(PlayerWindowController.menuStepFrame(_:))
    jumpToBegin.action = #selector(PlayerWindowController.menuJumpToBegin(_:))
    jumpTo.action = #selector(PlayerWindowController.menuJumpTo(_:))

    // -- speed
    (speedUp.representedObject,
     speedUpSlightly.representedObject,
     speedDown.representedObject,
     speedDownSlightly.representedObject) = (2.0, 1.1, 0.5, 0.9)
    [speedUp, speedDown, speedUpSlightly, speedDownSlightly, speedReset].forEach { item in
      item?.action = #selector(PlayerWindowController.menuChangeSpeed(_:))
    }

    // -- screenshot
    screenshot.action = #selector(PlayerWindowController.menuSnapshot(_:))
    gotoScreenshotFolder.action = #selector(AppDelegate.menuOpenScreenshotFolder(_:))
    // advancedScreenShot

    // -- list and chapter
    abLoop.action = #selector(PlayerWindowController.menuABLoop(_:))
    fileLoop.action = #selector(PlayerWindowController.menuFileLoop(_:))
    playlistMenu.delegate = self
    chapterMenu.delegate = self
    playlistLoop.action = #selector(PlayerWindowController.menuPlaylistLoop(_:))
    playlistPanel.action = #selector(MainWindowController.menuShowPlaylistPanel(_:))
    chapterPanel.action = #selector(MainWindowController.menuShowChaptersPanel(_:))

    nextMedia.action = #selector(PlayerWindowController.menuNextMedia(_:))
    previousMedia.action = #selector(PlayerWindowController.menuPreviousMedia(_:))

    nextChapter.action = #selector(PlayerWindowController.menuNextChapter(_:))
    previousChapter.action = #selector(PlayerWindowController.menuPreviousChapter(_:))

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
    bind(menu: aspectMenu, withOptions: aspectList, objects: aspectListObject, objectMap: nil, action: #selector(PlayerWindowController.menuChangeAspect(_:))) {
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
    bind(menu: cropMenu, withOptions: cropList, objects: cropListForObject, objectMap: nil, action: #selector(PlayerWindowController.menuChangeCrop(_:))) {
      return PlayerCore.active.info.unsureCrop == $0.representedObject as? String
    }
    // Separate "Custom..." from other crop sizes.
    cropMenu.insertItem(NSMenuItem.separator(), at: 1 + AppData.aspects.count)

    // -- rotation
    let rotationTitles = AppData.rotations.map { "\($0)\(Constants.String.degree)" }
    bind(menu: rotationMenu, withOptions: rotationTitles, objects: AppData.rotations, objectMap: nil, action: #selector(PlayerWindowController.menuChangeRotation(_:))) {
      PlayerCore.active.info.rotation == $0.representedObject as? Int
    }

    // -- flip and mirror
    flipMenu.delegate = self
    flip.action = #selector(PlayerWindowController.menuToggleFlip(_:))
    mirror.action = #selector(PlayerWindowController.menuToggleMirror(_:))

    // -- deinterlace
    deinterlace.action = #selector(PlayerWindowController.menuToggleDeinterlace(_:))

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

    // - volume
    (increaseVolume.representedObject,
     decreaseVolume.representedObject,
     increaseVolumeSlightly.representedObject,
     decreaseVolumeSlightly.representedObject) = (5, -5, 1, -1)
    [increaseVolume, decreaseVolume, increaseVolumeSlightly, decreaseVolumeSlightly].forEach { item in
      item?.action = #selector(PlayerWindowController.menuChangeVolume(_:))
    }
    mute.action = #selector(PlayerWindowController.menuToggleMute(_:))

    // - audio delay
    (increaseAudioDelay.representedObject,
     increaseAudioDelaySlightly.representedObject,
     decreaseAudioDelay.representedObject,
     decreaseAudioDelaySlightly.representedObject) = (0.5, 0.1, -0.5, -0.1)
    [increaseAudioDelay, decreaseAudioDelay, increaseAudioDelaySlightly, decreaseAudioDelaySlightly].forEach { item in
      item?.action = #selector(PlayerWindowController.menuChangeAudioDelay(_:))
    }
    resetAudioDelay.action = #selector(PlayerWindowController.menuResetAudioDelay(_:))

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
    loadExternalSub.action = #selector(PlayerWindowController.menuLoadExternalSub(_:))
    subTrackMenu.delegate = self
    secondSubTrackMenu.delegate = self

    findOnlineSub.action = #selector(PlayerWindowController.menuFindOnlineSub(_:))
    saveDownloadedSub.action = #selector(PlayerWindowController.saveDownloadedSub(_:))

    onlineSubSourceMenu.delegate = self

    // - text size
    [increaseTextSize, decreaseTextSize, resetTextSize].forEach {
      $0.action = #selector(PlayerWindowController.menuChangeSubScale(_:))
    }

    // - delay
    (increaseSubDelay.representedObject,
     increaseSubDelaySlightly.representedObject,
     decreaseSubDelay.representedObject,
     decreaseSubDelaySlightly.representedObject) = (0.5, 0.1, -0.5, -0.1)
    [increaseSubDelay, decreaseSubDelay, increaseSubDelaySlightly, decreaseSubDelaySlightly].forEach { item in
      item?.action = #selector(PlayerWindowController.menuChangeSubDelay(_:))
    }
    resetSubDelay.action = #selector(PlayerWindowController.menuResetSubDelay(_:))

    // encoding
    let encodingTitles = AppData.encodings.map { $0.title }
    let encodingObjects = AppData.encodings.map { $0.code }
    bind(menu: encodingMenu, withOptions: encodingTitles, objects: encodingObjects, objectMap: nil, action: #selector(PlayerWindowController.menuSetSubEncoding(_:))) {
      PlayerCore.active.info.subEncoding == $0.representedObject as? String
    }
    subFont.action = #selector(PlayerWindowController.menuSubFont(_:))
    // Separate Auto from other encoding types
    encodingMenu.insertItem(NSMenuItem.separator(), at: 1)

    // Plugin

    if IINA_ENABLE_PLUGIN_SYSTEM {
      pluginMenu.delegate = self
    } else {
      pluginMenuItem.isHidden = true
    }

    // Window

    if #available(macOS 10.12.2, *) {
      customTouchBar.action = #selector(NSApplication.toggleTouchBarCustomizationPalette(_:))
    } else {
      customTouchBar.isHidden = true
    }

    inspector.action = #selector(PlayerWindowController.menuShowInspector(_:))
    miniPlayer.action = #selector(MainWindowController.menuSwitchToMiniPlayer(_:))
  }

  // MARK: - Update Menus

  private func updatePlaylist() {
    playlistMenu.removeAllItems()
    for (index, item) in PlayerCore.active.info.playlist.enumerated() {
      playlistMenu.addItem(withTitle: item.filenameForDisplay, action: #selector(PlayerWindowController.menuPlaylistItem(_:)),
                           tag: index, obj: nil, stateOn: item.isCurrent)
    }
  }

  private func updateChapterList() {
    chapterMenu.removeAllItems()
    let info = PlayerCore.active.info
    let padder = { (time: String) -> String in
      let standard = (info.chapters.last?.time.stringRepresentation ?? "").reversed()
      return String((time.reversed() + standard[standard.index(standard.startIndex, offsetBy: time.count)...].map {
        $0 == ":" ? ":" : "0"
      }).reversed())
    }
    for (index, chapter) in info.chapters.enumerated() {
      let menuTitle = "\(padder(chapter.time.stringRepresentation)) – \(chapter.title)"
      let nextChapterTime = info.chapters[at: index+1]?.time ?? Constants.Time.infinite
      let isPlaying = info.videoPosition?.between(chapter.time, nextChapterTime) ?? false
      let menuItem = NSMenuItem(title: menuTitle, action: #selector(PlayerWindowController.menuChapterSwitch(_:)), keyEquivalent: "")
      menuItem.tag = index
      menuItem.state = isPlaying ? .on : .off
      menuItem.attributedTitle = NSAttributedString(string: menuTitle, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)])
      chapterMenu.addItem(menuItem)
    }
  }

  private func updateTracks(forMenu menu: NSMenu, type: MPVTrack.TrackType) {
    let info = PlayerCore.active.info
    menu.removeAllItems()
    let noTrackMenuItem = NSMenuItem(title: Constants.String.trackNone, action: #selector(PlayerWindowController.menuChangeTrack(_:)), keyEquivalent: "")
    noTrackMenuItem.representedObject = MPVTrack.emptyTrack(for: type)
    if info.trackId(type) == 0 {  // no track
      noTrackMenuItem.state = .on
    }
    menu.addItem(noTrackMenuItem)
    for track in info.trackList(type) {
      menu.addItem(withTitle: track.readableTitle, action: #selector(PlayerWindowController.menuChangeTrack(_:)),
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
    pause.title = player.info.isPaused ? Constants.String.resume : Constants.String.pause
    let isLoop = player.mpv.getString(MPVOption.PlaybackControl.loopFile) == "inf"
    fileLoop.state = isLoop ? .on : .off
    let isPlaylistLoop = player.mpv.getString(MPVOption.PlaybackControl.loopPlaylist)
    playlistLoop.state = (isPlaylistLoop == "inf" || isPlaylistLoop == "force") ? .on : .off
    speedIndicator.title = String(format: NSLocalizedString("menu.speed", comment: "Speed:"), player.info.playSpeed)
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
    delogo.state = isDelogo ? .on : .off
  }

  private func updateAudioMenu() {
    let player = PlayerCore.active
    let isDisplayingSettings = player.mainWindow.sideBarStatus == .settings &&
          player.mainWindow.quickSettingView.currentTab == .audio
    quickSettingsAudio?.title = isDisplayingSettings ? Constants.String.hideAudioPanel :
        Constants.String.audioPanel
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
    let isDisplayingSettings = player.mainWindow.sideBarStatus == .settings &&
          player.mainWindow.quickSettingView.currentTab == .sub
    quickSettingsSub?.title = isDisplayingSettings ? Constants.String.hideSubtitlesPanel :
        Constants.String.subtitlesPanel
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
                                action: #selector(MainWindowController.menuFindOnlineSub(_:)))
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
    Logger.log("Updating Plugin menu")
    pluginMenu.removeAllItems()
    pluginMenu.addItem(pluginErrorNotice)
    pluginErrorNotice.isHidden = true

    var keyMappings: [MenuItemMapping] = []

    pluginMenu.addItem(withTitle: "Manage Plugins…")
    pluginMenu.addItem(.separator())

    for (index, plugin) in PlayerCore.active.plugins.enumerated() {
      var counter = 0
      var rootMenu: NSMenu! = pluginMenu
      let menuItems = (plugin.plugin.globalInstance?.menuItems ?? []) + plugin.menuItems
      if menuItems.isEmpty { continue }
      
      if index != 0 {
        pluginMenu.addItem(.separator())
      }
      pluginMenu.addItem(withTitle: plugin.plugin.name, enabled: false)
      
      for item in menuItems {
        if counter == 5 {
          Logger.log("Please avoid adding too many first-level menu items. IINA will only display the first 5 of them.",
                     level: .warning, subsystem: plugin.subsystem)
          let moreItem = NSMenuItem()
          moreItem.title = "More…"
          rootMenu = NSMenu()
          moreItem.submenu = rootMenu
          pluginMenu.addItem(moreItem)
        }
        add(menuItemDef: item, to: rootMenu, for: plugin, keyMappings: &keyMappings)
        counter += 1
      }
    }

    Logger.log("Found \(keyMappings.count) key equivalents in Plugin menu items", level: .verbose)

    // This will kick off a series of updates set any key equivalents and update them as needed
    AppInputConfig.replaceMappings(forSharedSectionName: SharedInputSection.PLUGINS_SECTION_NAME, with: keyMappings, onlyIfDifferent: true)
  }

  @discardableResult
  private func add(menuItemDef item: JavascriptPluginMenuItem,
                   to menu: NSMenu,
                   for plugin: JavascriptPluginInstance,
                   keyMappings: inout [MenuItemMapping]) -> NSMenuItem {
    if (item.isSeparator) {
      let item = NSMenuItem.separator()
      menu.addItem(item)
      return item
    }

    Logger.log("Adding Plugin menu item: \"\(item.title)\", key=\"\(item.keyBinding ?? "")\"", level: .verbose)

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
    if let rawKey = item.keyBinding {
      // Store the item with its pair - the PlayerInputConfig will set the binding & deal with conflicts
      let actionString = "\(plugin.plugin.name) → \(menuItem.title)"
      keyMappings.append(MenuItemMapping(rawKey: rawKey, sourceName: plugin.plugin.name, menuItem: menuItem, actionDescription: actionString))
    }
    if !item.items.isEmpty {
      menuItem.submenu = NSMenu()
      for submenuItem in item.items {
        add(menuItemDef: submenuItem, to: menuItem.submenu!, for: plugin, keyMappings: &keyMappings)
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
    Logger.log("Updating menu: \(menu.title.quoted)", level: .verbose)

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
    var keyMappings: [KeyMapping] = []

    let sectionName: String
    let filterTypeString: String
    if isVideo {
      sectionName = SharedInputSection.VIDEO_FILTERS_SECTION_NAME
      filterTypeString = "Toggle video filter"
    } else {
      sectionName = SharedInputSection.AUDIO_FILTERS_SECTION_NAME
      filterTypeString = "Toggle audio filter"
    }

    let menu: NSMenu! = isVideo ? savedVideoFiltersMenu : savedAudioFiltersMenu
    menu.removeAllItems()
    for filter in filters {
      let menuItem = NSMenuItem()
      menuItem.title = filter.name
      menuItem.action = isVideo ? #selector(PlayerWindowController.menuToggleVideoFilterString(_:)) : #selector(PlayerWindowController.menuToggleAudioFilterString(_:))
      menuItem.keyEquivalent = ""
      menuItem.representedObject = filter.filterString
      menu.addItem(menuItem)

      if AppInputConfig.logBindingsRebuild {
        let readableKey = KeyCodeHelper.readableString(fromKey: filter.shortcutKey, modifiers: filter.shortcutKeyModifiers)
        Logger.log("Updating menuItem for \(isVideo ? "VF" : "AF") \(filter.name.quoted) with keyEquiv: \(readableKey.quoted)")
      }

      let rawKey = KeyCodeHelper.macOSToMpv(key: filter.shortcutKey, modifiers: filter.shortcutKeyModifiers)
      if !rawKey.isEmpty {
        let description = "\(filterTypeString): \(filter.name.quoted)"
        keyMappings.append(MenuItemMapping(rawKey: rawKey, sourceName: filter.name, menuItem: menuItem, actionDescription: description))
      }
    }

    AppInputConfig.replaceMappings(forSharedSectionName: sectionName, with: keyMappings)
  }

  // MARK: Set key equivalents

  func updateKeyEquivalents(from candidateBindings: [InputBinding]) {
    // Two general groups to be processed:
    // - Save filters & Plugin menu bindings have already had their values & enablement determined: just need to update their menu items.
    // - MPV bindings need some additional checks to see if they can be associated with menu items.
    var mpvBindings: [InputBinding] = []

    var pluginKeyConflicts: [InputBinding] = []

    for binding in candidateBindings {
      switch binding.origin {
        case .iinaPlugin:
          // include disabled bindings: need to set their menu item key equivs to nil
          updateKeyEquivalent(from: binding)
          if !binding.isEnabled {
            pluginKeyConflicts.append(binding)
          }
        case .savedFilter:
          // include disabled bindings: need to set their menu item key equivs to nil
          updateKeyEquivalent(from: binding)
        case .confFile:
          if binding.isEnabled { // don't care about disabled bindings here
            mpvBindings.append(binding)
          }
        default:
          break
      }
    }
    // Show Plugin menu error notice if there are binding conflicts:
    pluginErrorNotice.isHidden = (pluginKeyConflicts.count == 0)

    matchKeyEquivalents(with: mpvBindings)
  }

  private func updateKeyEquivalent(from binding: InputBinding) {
      guard let menuItem = binding.menuItem else { return }

      if binding.isEnabled {
        let mpvKey = binding.keyMapping.normalizedMpvKey
        if let (kEqv, kMdf) = KeyCodeHelper.macOSKeyEquivalent(from: mpvKey) {
          menuItem.keyEquivalent = kEqv
          menuItem.keyEquivalentModifierMask = kMdf
          binding.displayMessage = "This key binding will activate the menu item: \(menuItem.menuPathDescription)"
          if AppInputConfig.logBindingsRebuild {
            Logger.log("Set menu keyEquiv: \(mpvKey.quoted) → \(menuItem.menuPathDescription)", level: .verbose)
          }
        } else {
          Logger.log("Failed to get MacOS menu item key equivalent for \(mpvKey.quoted)", level: .error)
        }
      } else {
        // Conflict! Key binding already reserved
        menuItem.keyEquivalent = ""
        menuItem.keyEquivalentModifierMask = []
        if AppInputConfig.logBindingsRebuild {
          Logger.log("Unset menu keyEquiv: \(menuItem.title.quoted)", level: .verbose)
        }
      }
  }

  private func matchKeyEquivalents(with mpvBindings: [InputBinding]) {
    var settings: [(NSMenuItem, Bool, [String], Bool, ClosedRange<Double>?, String?)] = [
      (deleteCurrentFile, true, ["delete-current-file"], false, nil, nil),
      (savePlaylist, true, ["save-playlist"], false, nil, nil),
      (quickSettingsVideo, true, ["video-panel"], false, nil, nil),
      (quickSettingsAudio, true, ["audio-panel"], false, nil, nil),
      (quickSettingsSub, true, ["sub-panel"], false, nil, nil),
      (playlistPanel, true, ["playlist-panel"], false, nil, nil),
      (chapterPanel, true, ["chapter-panel"], false, nil, nil),
      (findOnlineSub, true, ["find-online-subs"], false, nil, nil),
      (saveDownloadedSub, true, ["save-downloaded-sub"], false, nil, nil),
      (biggerSize, true, ["bigger-window"], false, nil, nil),
      (smallerSize, true, ["smaller-window"], false, nil, nil),
      (fitToScreen, true, ["fit-to-screen"], false, nil, nil),
      (miniPlayer, true, ["toggle-music-mode"], false, nil, nil),
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
      (decreaseSubDelay, false, ["add", "sub-delay", "-0.5"], true, nil, "sub_delay_down"),
      (decreaseSubDelaySlightly, false, ["add", "sub-delay", "-0.1"], true, nil, "sub_delay_down"),
      (increaseSubDelay, false, ["add", "sub-delay", "0.5"], true, nil, "sub_delay_up"),
      (increaseSubDelaySlightly, false, ["add", "sub-delay", "0.1"], true, nil, "sub_delay_up"),
      (resetSubDelay, false, ["set", "sub-delay", "0"], true, nil, nil),
      (increaseTextSize, false, ["multiply", "sub-scale", "1.1"], true, 1.01...1.49, nil),
      (decreaseTextSize, false, ["multiply", "sub-scale", "0.9"], true, 0.71...0.99, nil),
      (resetTextSize, false, ["set", "sub-scale", "1"], true, nil, nil),
      (alwaysOnTop, false, ["cycle", "ontop"], false, nil, nil),
      (fullScreen, false, ["cycle", "fullscreen"], false, nil, nil)
    ]

    if #available(macOS 10.12, *) {
      settings.append((pictureInPicture, true, ["toggle-pip"], false, nil, nil))
    }

    settings.forEach { (menuItem, isIINACmd, actions, normalizeLastNum, numRange, l10nKey) in
      var bound = false
      for binding in mpvBindings {
        guard binding.isEnabled else { continue }
        let kb = binding.keyMapping
        guard kb.isIINACommand == isIINACmd else { continue }
        let (sameAction, value) = sameKeyAction(kb.action, actions, normalizeLastNum, numRange)
        if sameAction, let (kEqv, kMdf) = KeyCodeHelper.macOSKeyEquivalent(from: kb.normalizedMpvKey) {
          menuItem.keyEquivalent = kEqv
          menuItem.keyEquivalentModifierMask = kMdf
          if let value = value, let l10nKey = l10nKey {
            menuItem.title = String(format: NSLocalizedString("menu." + l10nKey, comment: ""), abs(value))
            menuItem.representedObject = value
          }
          bound = true
          binding.associatedMenuItem = menuItem  // so we can indicate it in UI
          binding.displayMessage = "This key binding will activate the menu item: \(menuItem.menuPathDescription)"
          break
        }
      }
      if !bound {
        menuItem.keyEquivalent = ""
        menuItem.keyEquivalentModifierMask = []
      }
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
