//
//  MainWindowMenuActions.swift
//  iina
//
//  Created by lhc on 13/8/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

extension MainWindowController {

  func menuShowPlaylistPanel(_ sender: NSMenuItem) {
    if sideBarStatus == .hidden || sideBarStatus == .settings {
      playlistView.pleaseSwitchToTab(.playlist)
      playlistButtonAction(sender)
    } else {
      if playlistView.currentTab != .playlist {
        playlistView.pleaseSwitchToTab(.playlist)
      } else {
        playlistButtonAction(sender)
      }
    }
  }

  func menuShowChaptersPanel(_ sender: NSMenuItem) {
    if sideBarStatus == .hidden || sideBarStatus == .settings {
      playlistView.pleaseSwitchToTab(.chapters)
      playlistButtonAction(sender)
    } else {
      if playlistView.currentTab != .chapters {
        playlistView.pleaseSwitchToTab(.chapters)
      } else {
        playlistButtonAction(sender)
      }
    }
  }

  func menuShowVideoQuickSettings(_ sender: NSMenuItem) {
    if sideBarStatus == .hidden || sideBarStatus == .playlist {
      quickSettingView.pleaseSwitchToTab(.video)
      settingsButtonAction(sender)
    } else {
      if quickSettingView.currentTab != .video {
        quickSettingView.pleaseSwitchToTab(.video)
      } else {
        settingsButtonAction(sender)
      }
    }
  }

  func menuShowAudioQuickSettings(_ sender: NSMenuItem) {
    if sideBarStatus == .hidden || sideBarStatus == .playlist {
      quickSettingView.pleaseSwitchToTab(.audio)
      settingsButtonAction(sender)
    } else {
      if quickSettingView.currentTab != .audio {
        quickSettingView.pleaseSwitchToTab(.audio)
      } else {
        settingsButtonAction(sender)
      }
    }
  }

  func menuShowSubQuickSettings(_ sender: NSMenuItem) {
    if sideBarStatus == .hidden || sideBarStatus == .playlist {
      quickSettingView.pleaseSwitchToTab(.sub)
      settingsButtonAction(sender)
    } else {
      if quickSettingView.currentTab != .sub {
        quickSettingView.pleaseSwitchToTab(.sub)
      } else {
        settingsButtonAction(sender)
      }
    }
  }

  func menuChangeWindowSize(_ sender: NSMenuItem) {
    // -1: normal(non-retina), same as 1 when on non-retina screen
    //  0: half
    //  1: normal
    //  2: double
    //  3: fit screen
    //  10: smaller size
    //  11: bigger size
    let size = sender.tag
    guard !isInFullScreen else { return }
    guard let w = window, var vw = playerCore.info.displayWidth, var vh = playerCore.info.displayHeight else { return }
    if vw == 0 { vw = AppData.widthWhenNoVideo }
    if vh == 0 { vh = AppData.heightWhenNoVideo }

    let useRetinaSize = UserDefaults.standard.bool(forKey: Preference.Key.usePhysicalResolution)
    let logicalSize = NSRect(x: w.frame.origin.x, y: w.frame.origin.y, width: CGFloat(vw), height: CGFloat(vh))
    var retinaSize = useRetinaSize ? w.convertFromBacking(logicalSize) : logicalSize
    let screenFrame = NSScreen.main()!.visibleFrame
    let newFrame: NSRect
    let sizeMap: [CGFloat] = [0.5, 1, 2]
    let scaleStep: CGFloat = 25

    switch size {
    // scale
    case 0, 1, 2:
      retinaSize.size.width *= sizeMap[size]
      retinaSize.size.height *= sizeMap[size]
      if retinaSize.size.width > screenFrame.size.width || retinaSize.size.height > screenFrame.size.height {
        newFrame = w.frame.centeredResize(to: w.frame.size.shrink(toSize: screenFrame.size)).constrain(in: screenFrame)
      } else {
        newFrame = w.frame.centeredResize(to: retinaSize.size.satisfyMinSizeWithSameAspectRatio(minSize)).constrain(in: screenFrame)
      }
    // fit screen
    case 3:
      w.center()
      newFrame = w.frame.centeredResize(to: w.frame.size.shrink(toSize: screenFrame.size))
    // bigger size
    case 10, 11:
      let newWidth = w.frame.width + scaleStep * (size == 10 ? -1 : 1)
      let newHeight = newWidth / (w.aspectRatio.width / w.aspectRatio.height)
      newFrame = w.frame.centeredResize(to: NSSize(width: newWidth, height: newHeight).satisfyMinSizeWithSameAspectRatio(minSize))
    default:
      return
    }

    w.setFrame(newFrame, display: true, animate: true)
  }

  func menuAlwaysOnTop(_ sender: AnyObject) {
    isOntop = !isOntop
    setWindowFloatingOnTop(isOntop)
  }

  @available(macOS 10.12, *)
  func menuTogglePIP(_ sender: NSMenuItem) {
    if !isInPIP {
      enterPIP()
    } else {
      exitPIP(manually: true)
    }
  }

  func menuToggleFullScreen(_ sender: NSMenuItem) {
    toggleWindowFullScreen()
  }
  
  
}
