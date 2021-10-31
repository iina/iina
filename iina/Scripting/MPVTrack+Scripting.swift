//
//  MPVTrack+Scripting.swift
//  iina
//
//  Created by Nate Weaver on 2020-03-04.
//  Copyright © 2020 lhc. All rights reserved.
//

import Foundation

@objc extension MPVTrack {

  override var classCode: FourCharCode {
    switch type {
      case .video:
        return "cTrV"
      case .audio:
        return "cTrA"
      case .sub, .secondSub:
        return "cTrS"
    }
  }

  @nonobjc private var scriptingContainerProperty: String {
    let scriptingType: String

    switch type {
      case .video:
        scriptingType = "Video"
      case .audio:
        scriptingType = "Audio"
      case .sub, .secondSub:
        scriptingType = "Subtitle"
    }

    return "scripting\(scriptingType)Tracks"

  }

  override var objectSpecifier: NSScriptObjectSpecifier? {
    let containerClass = NSScriptClassDescription(for: PlayerCore.self);
    let containerSpecifier = self.player?.objectSpecifier

    return NSIndexSpecifier(containerClassDescription: containerClass!, containerSpecifier: containerSpecifier, key: scriptingContainerProperty, index: self.id - 1)
  }

  var scriptingIndex: Int { id }

  var scriptingType: FourCharCode {
    switch type {
      case .video:
        return "kTTV"
      case .audio:
        return "kTTA"
      case .sub, .secondSub:
        return "kTTS"
    }
  }

  var scriptingCodec: String? { codec }

  var scriptingLanguage: String? { lang }

  var scriptingTitle: String? { title }

  var scriptingInfoString: String? { infoString }

  var scriptingIsDefault: Bool { isDefault }

}

// MARK: Video track properties
@objc extension MPVTrack {

  var scriptingFPS: Double { demuxFps ?? 0.0 }

  var scriptingWidth: Int { demuxW ?? 0 }

  var scriptingHeight: Int { demuxH ?? 0 }

}

// MARK: Audio track properties
@objc extension MPVTrack {

  var scriptingSampleRate: Int { demuxSamplerate ?? 0 }

  var scriptingChannelCount: Int { demuxChannelCount ?? 0 }

}
