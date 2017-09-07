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
    guard let window = window, !isInFullScreen else { return }
    
    let screenFrame = (window.screen ?? NSScreen.main()!).visibleFrame
    let newFrame: NSRect
    let sizeMap: [Double] = [0.5, 1, 2]
    let scaleStep: CGFloat = 25

    switch size {
    // scale
    case 0, 1, 2:
      setWindowScale(sizeMap[size])
      return
    // fit screen
    case 3:
      window.center()
      newFrame = window.frame.centeredResize(to: window.frame.size.shrink(toSize: screenFrame.size))
    // bigger size
    case 10, 11:
      let newWidth = window.frame.width + scaleStep * (size == 10 ? -1 : 1)
      let newHeight = newWidth / (window.aspectRatio.width / window.aspectRatio.height)
      newFrame = window.frame.centeredResize(to: NSSize(width: newWidth, height: newHeight).satisfyMinSizeWithSameAspectRatio(minSize))
    default:
      return
    }

    window.setFrame(newFrame, display: true, animate: true)
  }

  func menuAlwaysOnTop(_ sender: AnyObject) {
    isOntop = !isOntop
    setWindowFloatingOnTop(isOntop)
  }

  @available(macOS 10.12, *)
  func menuTogglePIP(_ sender: NSMenuItem) {
    switch pipStatus {
    case .notInPIP:
      enterPIP()
    case .inPIP:
      exitPIP()
    default:
      return
    }
  }

  func menuToggleFullScreen(_ sender: NSMenuItem) {
    toggleWindowFullScreen()
  }
  
  func menuSwitchToMiniPlayer(_ sender: NSMenuItem) {
    player.switchToMiniPlayer()
  }

  func menuSetDelogo(_ sender: NSMenuItem) {
    if sender.state == NSOnState {
      if let filter = player.info.delogoFiter {
        let _ = player.removeVideoFiler(filter)
        player.info.delogoFiter = nil
      }
    } else {
      self.hideSideBar {
        self.enterInteractiveMode(.freeSelecting)
      }
    }
  }
}
