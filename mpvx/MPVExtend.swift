//
//  MPVExtend.swift
//  mpvx
//
//  Created by lhc on 19/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Foundation


enum MPVEvent {
  case none
  case shutdown
  case logMessage(String, String, String)  // prefix, level, text
  case getPropertyReply
  case setPropertyReply
  case commandReply
  case startFile
  case endFile
  case fileLoaded
  case tracksChanged
  case trackSwitched
  case idle
  case pause
  case unpause
  case tick
  case scriptInputDispatch
  case clientMessage
  case videoReconfig
  case audioReconfig
  case metadataUpdate
  case seek
  case playbackRestart
  case propertyChange
  case chapterChange
  case queueOverflow
}

