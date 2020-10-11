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
    showPlaylistSidebar(tab: .playlist)
  }

  @objc func menuShowChaptersPanel(_ sender: NSMenuItem) {
    showPlaylistSidebar(tab: .chapters)
  }

  @objc func menuShowVideoQuickSettings(_ sender: NSMenuItem) {
    showSettingsSidebar(tab: .video)
  }

  @objc func menuShowAudioQuickSettings(_ sender: NSMenuItem) {
    showSettingsSidebar(tab: .audio)
  }

  @objc func menuShowSubQuickSettings(_ sender: NSMenuItem) {
    showSettingsSidebar(tab: .sub)
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
    guard let window = window, !fsState.isFullscreen else { return }

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
    setWindowFloatingOnTop(!isOntop)
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
      // Removing a filter based on its position within the filter list is the preferred way to do
      // it as per discussion with the mpv project. Search the list of filters and find the index
      // of the specified filter (if present).
      if let index = player.mpv.getFilters(type).firstIndex(of: filter) {
        // remove
        if isVideo {
          _ = player.removeVideoFilter(filter, index)
        } else {
          _ = player.removeAudioFilter(filter, index)
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
    if let vfWindow = (NSApp.delegate as? AppDelegate)?.vfWindow, vfWindow.loaded {
      vfWindow.reloadTable()
    }
  }
}
