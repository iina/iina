//
//  MPVPlaylistItem+Scripting.swift
//  iina
//
//  Created by Nate Weaver on 2020-03-07.
//  Copyright © 2020 lhc. All rights reserved.
//

import Foundation

extension MPVPlaylistItem {

  @objc override var classCode: FourCharCode {
    return "cPlL"
  }

  var scriptingIndex: Int? {
    return player?.info.playlist.firstIndex { $0 === self }
  }

  @objc override var objectSpecifier: NSScriptObjectSpecifier? {
    guard let player = player else { return nil }

    let containerClass = NSScriptClassDescription(for: PlayerCore.self);
    let containerSpecifier = player.objectSpecifier

    guard let index = scriptingIndex else { return nil }

    return NSIndexSpecifier(containerClassDescription: containerClass!, containerSpecifier: containerSpecifier, key: "scriptingPlaylistItems", index: index)
  }

}

extension MPVPlaylistItem {

  @objc var scriptingURL: String { isNetworkResource ? filename : URL(fileURLWithPath: filename).absoluteString }

  @objc var scriptingFile: URL? { isNetworkResource ? nil : URL(fileURLWithPath: filename) }

  @objc var scriptingName: String? { title }

  @objc var scriptingIsCurrent: Bool { isCurrent }

  @objc var scriptingIsPlaying: Bool { isPlaying }

  @objc var scriptingIsNetworkResource: Bool { isNetworkResource }

}
