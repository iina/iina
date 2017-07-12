//
//  iinaError.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

enum IINAError: Error {

  case unsupportedMPVNodeFormat(UInt32)

  case gifCannotCreateDestination
  case gifCannotConvertImage
  case gifCannotFinalize

}
