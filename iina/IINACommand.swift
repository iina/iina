//
//  IINACommand.swift
//  iina
//
//  Created by lhc on 15/4/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

enum IINACommand: String {

  case escape
  case closeSidebars = "close-sidebars"
  case showPanel = "show-panel"
  case hidePanel = "hide-panel"
  case togglePanel = "toggle-panel"
  case nextPlugin = "next-plugin"
  case previousPlugin = "previous-plugin"
  case openPlugin = "open-plugin"
  case showOSC = "show-osc"
  case hideOSC = "hide-osc"
  case toggleOSC = "toggle-osc"
  case resetOSCPosition = "reset-osc-position"
  case configureOSCPosition = "configure-osc-position"
  case openCustomCrop = "open-custom-crop"

  enum Panel: String, CaseIterable {
    case settings, layout, video, audio, sub, playlist, chapters, plugins
  }

  var isInterfaceCommand: Bool {
    switch self {
    case .escape, .closeSidebars, .showPanel, .hidePanel, .togglePanel,
         .nextPlugin, .previousPlugin, .openPlugin, .showOSC, .hideOSC,
         .toggleOSC, .resetOSCPosition, .configureOSCPosition, .openCustomCrop: return true
    default: return false
    }
  }

  func acceptsArguments(_ arguments: [String]) -> Bool {
    switch self {
    case .showPanel, .hidePanel, .togglePanel:
      return arguments.count == 1 && Panel(rawValue: arguments[0]) != nil
    case .openPlugin:
      return arguments.count == 1 && !arguments[0].isEmpty
    default:
      return arguments.isEmpty
    }
  }

  case togglePIP = "toggle-pip"
  case openFile = "open-file"
  case openURL = "open-url"

  case audioPanel = "audio-panel"
  case videoPanel = "video-panel"
  case subPanel = "sub-panel"
  case playlistPanel = "playlist-panel"
  case chapterPanel = "chapter-panel"

  case toggleMusicMode = "toggle-music-mode"
  case liveText = "live-text"

  case flip = "toggle-flip"
  case mirror = "toggle-mirror"

  case biggerWindow = "bigger-window"
  case smallerWindow = "smaller-window"
  case fitToScreen = "fit-to-screen"

  case saveCurrentPlaylist = "save-playlist"
  case showCurrentFileInFinder = "show-current-file-in-finder"
  case deleteCurrentFile = "delete-current-file"
  case deleteCurrentFileHard = "delete-current-file-hard"

  case findOnlineSubs = "find-online-subs"
  case saveDownloadedSub = "save-downloaded-sub"

}
