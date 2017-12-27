//
//  IINACommand.swift
//  iina
//
//  Created by lhc on 15/4/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

enum IINACommand: String {

  case togglePIP = "toggle-pip"
  case openFile = "open-file"
  case openURL = "open-url"

  case audioPanel = "audio-panel"
  case videoPanel = "video-panel"
  case subPanel = "sub-panel"
  case playlistPanel = "playlist-panel"
  case chapterPanel = "chapter-panel"

  case flip = "toggle-flip"
  case mirror = "toggle-mirror"

  case biggerWindow = "bigger-window"
  case smallerWindow = "smaller-window"

  case saveCurrentPlaylist = "save-playlist"
  case deleteCurrentFile = "delete-current-file"

  case findOnlineSubs = "find-online-subs"
  case saveDownloadedSub = "save-downloaded-sub"

}
