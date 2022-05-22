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
fileprivate let TableCellFontSize = 13

fileprivate let MinScore = 5 // Minimum matching score to be rendered on search results table


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
  var searchResults: [SearchItem] = []
  // Run the fuzzy matching in a different thread so we don't pause the inputField
  var searchWorkQueue: DispatchQueue = DispatchQueue(label: "IINAPlaylistSearchTask", qos: .userInitiated)
  // Make the searching cancellable so we aren't searching for a pattern when the pattern has changed
  var searchWorkItem: DispatchWorkItem? = nil
  
  // Make updating the ui cancellable so we aren't rendering old search results
  var updateTableWorkItem: DispatchWorkItem? = nil
  
  // Fixes bug where table would render search results if user clears input before searchWorkItem is finished
  var isInputEmpty = true
  
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
    isInputEmpty = true
    hideClearBtn()
    clearSearchResults()
    focusInput()
  }
  
  func clearSearchResults() {
    searchResults.removeAll()
    reloadTable()
  }
  
  func reloadTable() {
    updateTableWorkItem?.cancel()
    updateTableWorkItem = DispatchWorkItem {
      self.searchResultsTableView.reloadData()
    
      if self.searchResults.isEmpty {
        self.hideTable()
      } else {
        self.showTable()
      }
    }
    DispatchQueue.main.async(execute: updateTableWorkItem!)
  }
  
}

// MARK: Input Text Field Delegate
extension PlaylistSearchViewController: NSTextFieldDelegate {
  func controlTextDidChange(_ obj: Notification) {
    let input = inputField.stringValue
    
    searchWorkItem?.cancel()
    
    if input.isEmpty {
      searchWorkItem = nil
      
      clearInput()
      return
    }
    
    showClearBtn()
    
    isInputEmpty = false
    
    let playlist = player.info.playlist
    
    searchWorkItem = DispatchWorkItem {
      let results = searchPlaylist(playlist: playlist, pattern: input)
      
      if self.isInputEmpty {
        return
      }
      
      self.searchResults = results
      
      self.reloadTable()
    }
    
    searchWorkQueue.async(execute: searchWorkItem!)
    
  }
}

// MARK: Table View Delegate
extension PlaylistSearchViewController: NSTableViewDelegate, NSTableViewDataSource {
  
  func numberOfRows(in tableView: NSTableView) -> Int {
    return searchResults.count
  }
  
  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    
    let searchItem = searchResults[row]
    let render = NSMutableAttributedString(string: searchItem.item.filenameForDisplay)
    
    // Add bold for matching letters
    for index in searchItem.result.pos {
      let range = NSMakeRange(index , 1)
      render.addAttribute(NSAttributedString.Key.font, value: NSFont.boldSystemFont(ofSize: CGFloat(TableCellFontSize)), range: range)
      render.addAttribute(NSAttributedString.Key.foregroundColor, value: NSColor.textColor, range: range)
    }
    
    return [
      "filename": render
    ]
    
  }
  
  // Enables arrow keys to be used in tableview
  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    return true
  }
  
}

// MARK: Search Playlist

// TODO: Move to another file

struct SearchItem {
  let item: MPVPlaylistItem
  let result: Result
  let playlistIndex: Int
}

extension SearchItem: Comparable {
  static func < (l: SearchItem, r: SearchItem) -> Bool {
    return l.result.score < r.result.score
  }
  
  static func > (l: SearchItem, r: SearchItem) -> Bool {
    return l.result.score > r.result.score
  }
  
  static func == (l: SearchItem, r: SearchItem) -> Bool {
    return l.result.score == r.result.score
  }
}

func searchPlaylist(playlist: [MPVPlaylistItem], pattern: String) -> [SearchItem] {
  var results: [SearchItem] = []
  
  for (index, item) in playlist.enumerated() {
    let result = fuzzyMatch(text: item.filenameForDisplay, pattern: pattern)
    
    if result.score < MinScore {
      continue
    }
    
    let searchItem = SearchItem(item: item, result: result, playlistIndex: index)
    
    results.append(searchItem)
  }
  
  results.sort(by: >)
  
  return results
}
