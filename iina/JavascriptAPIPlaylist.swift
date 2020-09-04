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
  func list() -> [[String: Any]]
  func count() -> Int
  func add(_ url: JSValue, _ at: Int) -> Any
  func remove(_ index: JSValue) -> Any
  func move(_ index: Int, _ to: Int) -> Any
  func play(_ index: Int)
  func playNext()
  func playPrevious()
  func registerMenuItemBuilder(_ builder: JSValue)
}

class JavascriptAPIPlaylist: JavascriptAPI, JavascriptAPIPlaylistExportable {
  var menuItemBuilder: JSManagedValue?

  private func isPlaying() -> Bool {
    if player.info.isIdle {
      log("Playlist API is only available when playing files.", level: .error)
      return false
    }
    return true
  }

  func list() -> [[String: Any]] {
    guard isPlaying() else { return [] }

    return player.info.playlist.map {
      [
        "filename": $0.filename,
        "title": $0.title ?? NSNull(),
        "isPlaying": $0.isPlaying,
        "isCurrent": $0.isCurrent
      ]
    }
  }

  func count() -> Int {
    return player.info.playlist.count
  }

  func add(_ url: JSValue, _ at: Int = -1) -> Any {
    guard isPlaying() else { return false }

    let count = player.info.playlist.count
    guard at < count else {
      log("playlist.add: Invalid index.", level: .error)
      return false
    }
    if url.isArray {
      if let paths = url.toArray() as? [String] {
        player.addToPlaylist(paths: paths, at: at)
        return true
      }
    } else if url.isString {
      player.addToPlaylist(paths: [url.toString()], at: at)
      return true
    }
    log("playlist.add: The first argument should be a string or an array of strings.", level: .error)
    return false
  }

  func remove(_ index: JSValue) -> Any {
    guard isPlaying() else { return false }
    let count = player.info.playlist.count

    if index.isArray, let indices = index.toArray() as? [Int] {
      guard indices.allSatisfy({ $0 >= 0 && $0 < count }) else {
        log("playlist.remove: Invalid index.", level: .error)
        return false
      }
      player.playlistRemove(IndexSet(indices))
      return true
    } else if index.isNumber {
      let index = Int(index.toInt32())
      guard index >= 0 && index < count else {
        log("playlist.remove: Invalid index.", level: .error)
        return false
      }
      player.playlistRemove(index)
      return true
    }
    log("playlist.remove: The argument should be a number or an array of numbers.", level: .error)
    return false
  }

  func move(_ index: Int, _ to: Int) -> Any {
    guard isPlaying() else { return false }
    let count = player.info.playlist.count

    guard index >= 0 && index < count && to >= 0 && to < count && index != to else {
      log("playlist.move: Invalid index.", level: .error)
      return false
    }
    player.playlistMove(index, to: to)
    return true
  }

  func play(_ index: Int) {
    guard isPlaying() else { return }
    let count = player.info.playlist.count

    guard index >= 0 && index < count else {
      log("playlist.play: Invalid index.", level: .error)
      return
    }
    player.playFileInPlaylist(index)
  }

  func playNext() {
    guard isPlaying() else { return }

    player.navigateInPlaylist(nextMedia: true)
  }

  func playPrevious() {
    guard isPlaying() else { return }

    player.navigateInPlaylist(nextMedia: false)
  }

  func registerMenuItemBuilder(_ builder: JSValue) {
    if let previousBuilder = menuItemBuilder {
      JSContext.current()!.virtualMachine.removeManagedReference(previousBuilder, withOwner: self)
    }
    menuItemBuilder = JSManagedValue(value: builder)
    JSContext.current()!.virtualMachine.addManagedReference(menuItemBuilder, withOwner: self)
  }
}
