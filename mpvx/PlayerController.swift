//
//  PlayerController.swift
//  mpvx
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class PlayerController: NSObject {
  
  lazy var mainWindow: MainWindow! = {
    let window = MainWindow()
    window.playerController = self
    return window
  }()
  
  lazy var mpvController: MPVController! = {
    let controller = MPVController(playerController: self)
    return controller
  }()
  
  var statusPaused: Bool = false
  
  // Open a file
  func openFile(_ url: URL!) {
    let path = url.path
    guard path != nil else {
      Utility.log("Error: empty file path or url")
      return
    }
    Utility.log("Open File \(path!)")
    AppData.currentURL = url
    mainWindow.showWindow(nil)
    // Send load file command
    mpvController.mpvCommand(["loadfile", path, nil])
  }
  
  func startMPV() {
    mpvController.mpvInit()
  }
  
  func startMPVOpenGLCB(_ videoView: VideoView) {
    let mpvGLContext = mpvController.mpvInitCB()
    videoView.mpvGLContext = OpaquePointer(mpvGLContext)
  }
  
  // Terminate mpv
  func terminateMPV() {
    mpvController.mpvQuit()
    mainWindow.videoView.clearGLContext()
  }
  
  // Pause / resume
  func togglePause(_ set: Bool?) {
    if let setPause = set {
      mpvController.mpvSetFlagProperty("pause", setPause)
    } else {
      if (statusPaused) {
        mpvController.mpvSetFlagProperty("pause", false)
        statusPaused = false
      } else {
        mpvController.mpvSetFlagProperty("pause", true)
        statusPaused = true
      }
    }
  }
  
  func fileLoadedWithVideoSize(_ width: Int, _ height: Int) {
    DispatchQueue.main.sync {
      mainWindow.adjustFrameByVideoSize(width, height)
    }
    mpvController.mpvResume()
  }

}
