//
//  GifGenerator.swift
//  iina
//
//  Created by lhc on 19/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class GifGenerator: NSObject {
  
  func createGIF(from images: [NSImage], at url: URL, loopCount: Int = 0, frameDelay: Double) throws {
    
    let fileProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: loopCount]]
    let frameProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: frameDelay]]
    
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypeGIF, Int(images.count), nil) else {
      throw IINAError.gifCannotCreateDestination
    }
    
    CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
    
    for i in 0..<images.count {
      guard let cgimg = images[i].cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw IINAError.gifCannotConvertImage
      }
      CGImageDestinationAddImage(destination, cgimg, frameProperties as CFDictionary)
    }
    
    if !CGImageDestinationFinalize(destination) {
      throw IINAError.gifCannotFinalize
    }
  }

}
