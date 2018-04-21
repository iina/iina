//
//  MainWindowMenuActions.swift
//  iina
//
//  Created by lhc on 13/8/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

extension MainWindowController {

  @objc func menuShowPlaylistPanel(_ sender: NSMenuItem) {
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

  @objc func menuShowChaptersPanel(_ sender: NSMenuItem) {
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

  @objc func menuShowVideoQuickSettings(_ sender: NSMenuItem) {
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

  @objc func menuShowAudioQuickSettings(_ sender: NSMenuItem) {
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

  @objc func menuShowSubQuickSettings(_ sender: NSMenuItem) {
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

  @objc func menuChangeWindowSize(_ sender: NSMenuItem) {
    // -1: normal(non-retina), same as 1 when on non-retina screen
    //  0: half
    //  1: normal
    //  2: double
    //  3: fit screen
    //  10: smaller size
    //  11: bigger size
    let size = sender.tag
    guard let window = window, !screenState.isFullscreen else { return }
    
    let screenFrame = (window.screen ?? NSScreen.main!).visibleFrame
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

  @objc func menuAlwaysOnTop(_ sender: AnyObject) {
    isOntop = !isOntop
    setWindowFloatingOnTop(isOntop)
  }

  @available(macOS 10.12, *)
  @objc func menuTogglePIP(_ sender: NSMenuItem) {
    switch pipStatus {
    case .notInPIP:
      enterPIP()
    case .inPIP:
      exitPIP()
    default:
      return
    }
  }

  @objc func menuToggleFullScreen(_ sender: NSMenuItem) {
    toggleWindowFullScreen()
  }
  
  @objc func menuSwitchToMiniPlayer(_ sender: NSMenuItem) {
    player.switchToMiniPlayer()
  }

  @objc func menuSetDelogo(_ sender: NSMenuItem) {
    if sender.state == .on {
      if let filter = player.info.delogoFilter {
        let _ = player.removeVideoFilter(filter)
        player.info.delogoFilter = nil
      }
    } else {
      self.hideSideBar {
        self.enterInteractiveMode(.freeSelecting)
      }
    }
  }

  @objc
  func menuToggleVideoFilterString(_ sender: NSMenuItem) {
    if let string = (sender.representedObject as? String) {
      menuToggleFilterString(string, forType: MPVProperty.vf)
    }
  }

  @objc
  func menuToggleAudioFilterString(_ sender: NSMenuItem) {
    if let string = (sender.representedObject as? String) {
      menuToggleFilterString(string, forType: MPVProperty.af)
    }
  }

  private func menuToggleFilterString(_ string: String, forType type: String) {
    let isVideo = type == MPVProperty.vf
    if let filter = MPVFilter(rawString: string) {
      if player.mpv.getFilters(type).contains(where: { $0.stringFormat == string }) {
        // remove
        if isVideo {
          _ = player.removeVideoFilter(filter)
        } else {
          _ = player.removeAudioFilter(filter)
        }
      } else {
        // add
        if isVideo {
          if !player.addVideoFilter(filter) {
            Utility.showAlert("filter.incorrect")
          }
        } else {
          if !player.addAudioFilter(filter) {
            Utility.showAlert("filter.incorrect")
          }
        }
      }
    }
    if let vfWindow = (NSApp.delegate as? AppDelegate)?.vfWindow, vfWindow.isWindowLoaded {
      vfWindow.reloadTable()
    }
  }
}
