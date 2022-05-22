//
//  PlaylistSearchViewController.swift
//  iina
//
//  Created by Anas Saeed on 5/22/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation
import Cocoa

class PlaylistSearchViewController: NSWindowController {
  
  override var windowNibName: NSNib.Name {
    return NSNib.Name("PlaylistSearchViewController")
  }
  
  weak var playlistViewController: PlaylistViewController! {
    didSet {
      self.player = playlistViewController.player
    }
  }
  
  weak var player: PlayerCore!
  
  private var clickMonitor: Any?
  private var isOpen = false
  
  // MARK: Outlets
  @IBOutlet weak var inputField: NSTextField!
  @IBOutlet weak var clearBtn: NSButton!
  @IBOutlet weak var searchResultsTableView: NSTableView!
  @IBOutlet weak var inputBorderBottom: NSBox!
  
  override func windowDidLoad() {
    super.windowDidLoad()
    
    // Remove window titlebar and buttons
    window?.isMovableByWindowBackground = true
    window?.titlebarAppearsTransparent = true
    window?.titleVisibility = .hidden
    ([.closeButton, .miniaturizeButton, .zoomButton] as [NSWindow.ButtonType]).forEach {
      window?.standardWindowButton($0)?.isHidden = true
    }
  }
  
  // MARK: Opening and Closing Window
  func openSearchWindow() {
    if isOpen {
      return
    }
    isOpen = true
    
    addClickMonitor()
    showWindow(nil)
  }
  
  func hideSearchWindow() {
    if !isOpen {
      return
    }
    isOpen = false
    
    window?.close()
    removeClickMonitor()
  }
  
  @objc func cancel(_ sender: Any?) {
    hideSearchWindow()
  }
  
  // MARK: Click Events
  /**
   Creates a monitor for outside clicks. If user clicks outside the search window, the window will be hidden
   */
  func addClickMonitor() {
    clickMonitor = NSEvent.addLocalMonitorForEvents(matching: NSEvent.EventTypeMask.leftMouseDown) {
      (event) -> NSEvent? in
      if !(self.window?.windowNumber == event.windowNumber) {
        self.hideSearchWindow()
      }
      return event
    }
  }
  
  func removeClickMonitor() {
    if clickMonitor != nil {
      NSEvent.removeMonitor(clickMonitor!)
      clickMonitor = nil
    }
  }
  
}
