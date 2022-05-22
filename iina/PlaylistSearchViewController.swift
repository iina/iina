//
//  PlaylistSearchViewController.swift
//  iina
//
//  Created by Anas Saeed on 5/22/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation
import Cocoa

fileprivate let WindowWidth = 500
fileprivate let InputFieldHeight = 48
fileprivate let TableCellHeight = 24
fileprivate let MaxTableViewHeight = TableCellHeight * 10

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
  
  // Click Monitor for detecting if a click occured on the main window, if so, then the search window will close
  private var clickMonitor: Any?
  private var isOpen = false
  
  // MARK: Search Results
  var searchResults: [String] = []
  
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
    
    // Delegates
    inputField.delegate = self
    
    searchResultsTableView.delegate = self
    searchResultsTableView.dataSource = self
    
    // Reset Input
    clearInput()
  }
  
  // MARK: Showing and Hiding Window and Elements
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
  
  func hideClearBtn() {
    clearBtn.isHidden = true
  }
  
  func showClearBtn() {
    clearBtn.isHidden = false
  }
  
  func hideTable() {
    searchResultsTableView.isHidden = true
    inputBorderBottom.isHidden = true
    
    let size = NSMakeSize(CGFloat(WindowWidth), CGFloat(InputFieldHeight))
    window?.setContentSize(size)
  }
  
  func showTable() {
    searchResultsTableView.isHidden = false
    inputBorderBottom.isHidden = false
    
    resizeTable()
  }
  
  func resizeTable() {
    let maxHeight = InputFieldHeight + MaxTableViewHeight
    
    let neededHeight = searchResults.count * TableCellHeight
    
    let height = (neededHeight < maxHeight) ? neededHeight : maxHeight
    
    let size = NSMakeSize(CGFloat(WindowWidth), CGFloat(height))
    window?.setContentSize(size)
  }
  
  func focusInput() {
    window?.makeFirstResponder(inputField)
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
  
  // MARK: IBActions
  @IBAction func clearBtnAction(_ sender: Any) {
    clearInput()
  }
  
  // MARK: Input and SearchResults utilities
  
  func clearInput() {
    inputField.stringValue = ""
    hideClearBtn()
    clearSearchResults()
    focusInput()
  }
  
  func clearSearchResults() {
    searchResults.removeAll()
    reloadTable()
  }
  
  func reloadTable() {
    searchResultsTableView.reloadData()
    
    if searchResults.isEmpty {
      hideTable()
    } else {
      showTable()
    }
  }
  
}

// MARK: Input Text Field Delegate
extension PlaylistSearchViewController: NSTextFieldDelegate {
  func controlTextDidChange(_ obj: Notification) {
    let input = inputField.stringValue
    
    if input.isEmpty {
      clearInput()
      return
    }
    
    showClearBtn()
    
  }
}

// MARK: Table View Delegate
extension PlaylistSearchViewController: NSTableViewDelegate, NSTableViewDataSource {
  
  func numberOfRows(in tableView: NSTableView) -> Int {
    return searchResults.count
  }
  
  // Enables arrow keys to be used in tableview
  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    return true
  }
  
}
