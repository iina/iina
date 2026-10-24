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
    sidebars.show(tab: "playlist")
  }

  @objc func menuShowChaptersPanel(_ sender: NSMenuItem) {
    sidebars.show(tab: "chapters")
  }

  @objc func menuShowVideoQuickSettings(_ sender: NSMenuItem) {
    sidebars.show(tab: "video")
  }

  @objc func menuShowAudioQuickSettings(_ sender: NSMenuItem) {
    sidebars.show(tab: "audio")
  }

  @objc func menuShowSubQuickSettings(_ sender: NSMenuItem) {
    sidebars.show(tab: "sub")
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
    guard let window, !fsState.isFullscreen else { return }

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
      let aspect = Preference.unlockWindowAspectRatio ? window.frame.size : window.aspectRatio
      let newHeight = newWidth / aspect.aspect
      newFrame = window.frame.centeredResize(to: NSSize(width: newWidth, height: newHeight).satisfyMinSizeWithSameAspectRatio(minimumWindowSize))
    default:
      return
    }

    setUserWindowFrame(windowFrameConstrainedToScreen(newFrame, screenFrame: screenFrame))
  }

  @objc func menuAlwaysOnTop(_ sender: AnyObject) {
    setWindowFloatingOnTop(!isOntop)
  }

  @objc func menuLockAspectRatio(_ sender: NSMenuItem) {
    let unlock = Preference.bool(for: .unlockWindowAspectRatio)
    Preference.set(!unlock, for: .unlockWindowAspectRatio)
  }

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
    guard player.info.state.loaded, !interactiveMode.isActive, !isCropTransitionInProgress else { return }
    if sender.state == .on {
      if let filter = player.info.delogoFilter {
        let _ = player.removeVideoFilter(filter)
        player.info.delogoFilter = nil
      }
    } else {
      guard interactiveMode.canEnter else { return }
      self.sidebars.hideAllSideBars {
        self.interactiveMode.enter(mode: .delogo)
      }
    }
  }
}

extension MainWindowController: NSMenuItemValidation {
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(menuSwitchToMiniPlayer(_:)):
      return !player.isInMiniPlayer && player.info.state.active && loaded &&
        !interactiveMode.isActive && !isCropTransitionInProgress && pipStatus == .notInPIP &&
        !isFullscreenTransitionInProgress && videoView.superview === videoViewContainer
    case #selector(menuSetDelogo(_:)):
      if player.info.delogoFilter != nil {
        return player.info.state.loaded && !interactiveMode.isActive && !isCropTransitionInProgress
      }
      return interactiveMode.canEnter
    default:
      return true
    }
  }
}
