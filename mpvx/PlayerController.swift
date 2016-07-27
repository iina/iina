//
//  PlayerController.swift
//  mpvx
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class PlayerController: NSObject {
  
  let ud: UserDefaults = UserDefaults.standard
  
  lazy var mainWindow: MainWindow! = {
    let window = MainWindow()
    window.playerController = self
    return window
  }()
  
  lazy var mpvController: MPVController! = {
    let controller = MPVController(playerController: self)
    return controller
  }()
  
  lazy var preferenceWindow: PreferenceWindow! = {
    let window = PreferenceWindow()
    return window
  }()
  
  lazy var info: PlaybackInfo = PlaybackInfo()
  
  var syncPlayTimeTimer: Timer?
  
  var statusPaused: Bool = false
  
  // Open a file
  func openFile(_ url: URL!) {
    let path = url.path
    guard path != nil else {
      Utility.log("Error: empty file path or url")
      return
    }
    Utility.log("Open File \(path!)")
    info.currentURL = url
    mainWindow.showWindow(nil)
    // Send load file command
    mpvController.mpvCommand([MPVCommand.loadfile, path, nil])
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
    syncPlayTimeTimer?.invalidate()
    mpvController.mpvQuit()
    mainWindow.videoView.clearGLContext()
  }
  
  // MARK: - mpv commands
  
  /** Pause / resume */
  func togglePause(_ set: Bool?) {
    if let setPause = set {
      mpvController.mpvSetFlagProperty(MPVProperty.pause, setPause)
    } else {
      if (info.isPaused) {
        mpvController.mpvSetFlagProperty(MPVProperty.pause, false)
      } else {
        mpvController.mpvSetFlagProperty(MPVProperty.pause, true)
      }
    }
  }
  
  func seek(percent: Double) {
    let seekMode = ud.bool(forKey: Preference.Key.useExactSeek) ? "absolute-percent+exact" : "absolute-percent"
    mpvController.mpvCommand([MPVCommand.seek, "\(percent)", seekMode, nil])
  }
  
  func setVolume(_ volume: Int) {
    mpvController.mpvSetIntProperty(MPVProperty.volume, Int64(volume))
  }
  
  func fileLoaded() {
    DispatchQueue.main.sync {
      syncPlayTimeTimer = Timer.scheduledTimer(timeInterval: TimeInterval(AppData.getTimeInterval),
                                               target: self, selector: #selector(self.syncUITime), userInfo: nil, repeats: true)
      mainWindow.adjustFrameByVideoSize()
    }
    mpvController.mpvResume()
  }
  
  enum SyncUIOption {
    case Time
    case PlayButton
    case VolumeButton
  }
  
  func syncUITime() {
    syncUI(.Time)
  }
  
  func syncUI(_ option: SyncUIOption) {
    switch option {
    case .Time:
      let time = mpvController.mpvGetIntProperty(MPVProperty.timePos)
      info.videoPosition!.second = time
      DispatchQueue.main.async {
        self.mainWindow.updatePlayTime(withDuration: false, andProgressBar: true)
      }
    case .PlayButton:
      let pause = mpvController.mpvGetFlagProperty(MPVProperty.pause)
      info.isPaused = pause
      DispatchQueue.main.async {
        self.mainWindow.playButton.state = pause ? NSOffState : NSOnState
      }
    default:
      break
    }
  }

}
