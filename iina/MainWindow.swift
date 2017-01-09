//
//  MainWindow.swift
//  iina
//
//  Created by Jiaqi Gu on 1/6/17.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class MainWindow: NSWindow, NSDraggingDestination{
  let expectedExt = ["srt","ass"]
  var filePath: String?
  lazy var playerCore = PlayerCore.shared
  override init(contentRect: NSRect, styleMask style: NSWindowStyleMask, backing bufferingType: NSBackingStoreType, defer flag: Bool) {
    super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
    setup()
  }
  func setup() {
    self.registerForDraggedTypes([kUTTypeURL as String])
  }
  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    if checkExtension(sender) == true {
      return .copy
    } else {
      return NSDragOperation()
    }
  }
  private func checkExtension(_ drag: NSDraggingInfo) -> Bool {
    guard let board = drag.draggingPasteboard().propertyList(forType: "NSFilenamesPboardType") as? NSArray,
      let path = board[0] as? String
      else { return false }
    let suffix = URL(fileURLWithPath: path).pathExtension
    for ext in self.expectedExt {
      if ext.lowercased() == suffix {
        return true
      }
    }
    return false
  }
  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let pasteboard = sender.draggingPasteboard().propertyList(forType: "NSFilenamesPboardType") as? NSArray,
      let path = pasteboard[0] as? String
    else { return false }
    let url = URL(fileURLWithPath: path,isDirectory: false)
    self.playerCore.loadExternalSubFile(url)
    return true
  }
}

