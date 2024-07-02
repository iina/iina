//
//  FFmpegControllerLogger.swift
//  iina
//
//  Created by low-batt on 5/22/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// Logger for the `FFmpegController`.
///
/// This class gives the `FFmpegController`, which is implemented in Objective-C, the ability to log messages using the
/// `Logger`.class.
@objc class FFmpegLogger: NSObject {

  @objc static func debug(_ message: String) {
    Logger.log(message, subsystem: Logger.Sub.ffmpeg)
  }

  @objc static func error(_ message: String) {
    Logger.log(message, level: .error, subsystem: Logger.Sub.ffmpeg)
  }

  @objc static func warn(_ message: String) {
    Logger.log(message, level: .warning, subsystem: Logger.Sub.ffmpeg)
  }
}

extension Logger.Sub {
  static let ffmpeg = Logger.makeSubsystem("ffmpeg")
}
