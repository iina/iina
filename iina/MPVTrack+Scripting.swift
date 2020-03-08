//
//  MPVTrack+Scripting.swift
//  iina
//
//  Created by Nate Weaver on 2020-03-04.
//  Copyright © 2020 lhc. All rights reserved.
//

import Foundation

extension MPVTrack {

  @objc override var classCode: FourCharCode {
    switch type {
      case .video:
        return "cTrV"
      case .audio:
        return "cTrA"
      case .sub, .secondSub:
        return "cTrS"
    }
  }

  private var scriptingContainerProperty: String {
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

  @objc override var objectSpecifier: NSScriptObjectSpecifier? {
    let containerClass = NSScriptClassDescription(for: PlayerCore.self);
    let containerSpecifier = self.player?.objectSpecifier

    return NSIndexSpecifier(containerClassDescription: containerClass!, containerSpecifier: containerSpecifier, key: scriptingContainerProperty, index: self.id - 1)
  }

  @objc var scriptingIndex: Int { id }

  @objc var scriptingType: FourCharCode {
    switch type {
      case .video:
        return "kTTV"
      case .audio:
        return "kTTA"
      case .sub, .secondSub:
        return "kTTS"
    }
  }

  @objc var scriptingCodec: String? { codec }

  @objc var scriptingLanguage: String? { lang }

  @objc var scriptingTitle: String? { title }

  @objc var scriptingInfoString: String? { infoString }

  @objc var scriptingIsDefault: Bool { isDefault }

}

// MARK: Video track properties
extension MPVTrack {

  @objc var scriptingFPS: Double { demuxFps ?? 0.0 }

  @objc var scriptingWidth: Int { demuxW ?? 0 }

  @objc var scriptingHeight: Int { demuxH ?? 0 }

}

// MARK: Audio track properties
extension MPVTrack {

  @objc var scriptingSampleRate: Int { demuxSamplerate ?? 0 }

  @objc var scriptingChannelCount: Int { demuxChannelCount ?? 0 }

}
