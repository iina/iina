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
  func getPlaylist() -> [String]?
  func addMutiple(_ urls: [String], _ at: Int)
  func add(_ url: String, _ at: Int)
  func appendMutiple(_ urls: [String])
  func append(_ url: String)
  func deleteMutiple(_ indexes: [Int])
  func delete(_ index: Int)
  func play(_ index: Int)
}

class JavascriptAPIPlaylist: JavascriptAPI, JavascriptAPIPlaylistExportable {

  @objc func getPlaylist() -> [String]? {
    return whenPermitted(to: .playlist) {
      return player.info.playlist.map { $0.filename }
    }
  }

  @objc func addMutiple(_ urls: [String], _ at: Int) {
    whenPermitted(to: .playlist) {
      player.addToPlaylist(paths: urls, at: at)
    }
  }

  @objc func add(_ url: String, _ at: Int) {
    addMutiple([url], at)
  }

  @objc func appendMutiple(_ urls: [String]) {
    addMutiple(urls, player.info.playlist.count)
  }

  @objc func append(_ url: String) {
    appendMutiple([url])
  }

  @objc func deleteMutiple(_ indexes: [Int]) {
    whenPermitted(to: .playlist) {
      player.playlistRemove(IndexSet(indexes))
    }
  }

  @objc func delete(_ index: Int) {
    deleteMutiple([index])
  }

  @objc func play(_ index: Int) {
    player.playFileInPlaylist(index)
  }

}
