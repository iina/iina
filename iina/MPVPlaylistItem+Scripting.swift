//
//  MPVPlaylistItem+Scripting.swift
//  iina
//
//  Created by Nate Weaver on 2020-03-07.
//  Copyright © 2020 lhc. All rights reserved.
//

import Foundation

@objc extension MPVPlaylistItem {

  override var classCode: FourCharCode {
    return "cPLI"
  }

  @nonobjc var scriptingIndex: Int? {
    return player?.info.playlist.firstIndex { $0 === self }
  }

  override var objectSpecifier: NSScriptObjectSpecifier? {
    guard let player = player else { return nil }

    let containerClass = NSScriptClassDescription(for: PlayerCore.self);
    let containerSpecifier = player.objectSpecifier

    guard let index = scriptingIndex else { return nil }

    return NSIndexSpecifier(containerClassDescription: containerClass!, containerSpecifier: containerSpecifier, key: "scriptingPlaylistItems", index: index)
  }

}

@objc extension MPVPlaylistItem {

  var scriptingURLString: String { isNetworkResource ? filename : URL(fileURLWithPath: filename).absoluteString }

  var scriptingFile: URL? { isNetworkResource ? nil : URL(fileURLWithPath: filename) }

  var scriptingName: String? { title }

  var scriptingIsCurrent: Bool { isCurrent }

  var scriptingIsPlaying: Bool { isPlaying }

  var scriptingIsNetworkResource: Bool { isNetworkResource }

}
