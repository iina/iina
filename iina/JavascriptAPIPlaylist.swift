//
//  JavascriptAPIPlaylist.swift
//  iina
//
//  Created by Yuze Jiang on 2/20/20.
//  Copyright © 2020 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

@objc protocol JavascriptAPIPlaylistExportable: JSExport {
  func list() -> [String]?
  func add(_ url: JSValue, _ at: Int)
  func append(_ url: JSValue)
  func delete(_ index: JSValue)
  func move(_ index: Int, _ to: Int)
  func play(_ index: Int)
  func playNext()
  func playPrevious()
}

class JavascriptAPIPlaylist: JavascriptAPI, JavascriptAPIPlaylistExportable {

  @objc func list() -> [String]? {
    return whenPermitted(to: .playlist) {
      return player.info.playlist.map { $0.filename }
    }
  }

  @objc func add(_ url: JSValue, _ at: Int) {
    whenPermitted(to: .playlist) {
      if (url.isArray) {
        player.addToPlaylist(paths: url.toArray() as! [String], at: at)
      } else {
        player.addToPlaylist(url.toString())
      }
    }
  }

  @objc func append(_ url: JSValue) {
    add(url, player.info.playlist.count)
  }

  @objc func delete(_ index: JSValue) {
    whenPermitted(to: .playlist) {
      if (index.isArray) {
        player.playlistRemove(IndexSet(index.toArray() as! [Int]))
      } else {
        player.playlistRemove(Int(index.toInt32()))
      }
    }
  }

  @objc func move(_ index: Int, _ to: Int) {
    whenPermitted(to: .playlist) {
      player.playlistMove(index, to: to)
    }
  }

  @objc func play(_ index: Int) {
    player.playFileInPlaylist(index)
  }

  @objc func playNext() {
    player.navigateInPlaylist(nextMedia: true)
  }

  @objc func playPrevious() {
    player.navigateInPlaylist(nextMedia: false)
  }

}
