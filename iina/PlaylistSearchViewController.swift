//
//  PlaylistSearchViewController.swift
//  iina
//
//  Created by Anas Saeed on 5/22/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation
import Cocoa

fileprivate let WindowWidth = 600
fileprivate let InputFieldHeight = 46
fileprivate let TableCellHeight = 30
fileprivate let MaxTableViewHeight = TableCellHeight * 10
fileprivate let BottomMargin = 6

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
  
  // MARK: Observed Values
  internal var observedPrefKeys: [Preference.Key] = [
    .themeMaterial
  ]
  
  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath, let change = change else { return }
    
    switch keyPath {
    case PK.themeMaterial.rawValue:
      if let newValue = change[.newKey] as? Int {
        setMaterial(Preference.Theme(rawValue: newValue))
      }
    default:
      return
    }
  }
  
  internal func setMaterial(_ theme: Preference.Theme?) {
    guard let window = window, let theme = theme else { return }
    
    if #available(macOS 10.14, *) {
      window.appearance = NSAppearance(iinaTheme: theme)
    }
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
  
  deinit {
    ObjcUtils.silenced {
      for key in self.observedPrefKeys {
        UserDefaults.standard.removeObserver(self, forKeyPath: key.rawValue)
      }
    }
    removeClickMonitor()
  }
  
  // MARK: Outlets
  @IBOutlet weak var inputField: NSTextField!
  @IBOutlet weak var clearBtn: NSButton!
  @IBOutlet weak var searchResultsTableView: NSTableView!
  @IBOutlet weak var inputBorderBottom: NSBox!
  
  override func windowDidLoad() {
    super.windowDidLoad()
    
    // Reset Input
    hideClearBtn()
    hideTable()
    
    // Remove window titlebar and buttons
    window?.isMovableByWindowBackground = true
    window?.titlebarAppearsTransparent = true
    window?.titleVisibility = .hidden
    ([.closeButton, .miniaturizeButton, .zoomButton] as [NSWindow.ButtonType]).forEach {
      window?.standardWindowButton($0)?.isHidden = true
    }
    
    // Observe theme changes
    setMaterial(Preference.enum(for: .themeMaterial))
    
    observedPrefKeys.forEach { key in
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }
    
    // Delegates
    inputField.delegate = self
    
    searchResultsTableView.delegate = self
    searchResultsTableView.dataSource = self
    
    searchResultsTableView.doubleAction = #selector(handleSubmit)
    searchResultsTableView.action = #selector(handleSubmit)
  }
  
  // MARK: Showing and Hiding Window and Elements
  func openSearchWindow() {
    if isOpen {
      return
    }
    isOpen = true
    
    addClickMonitor()
    showWindow(nil)
    focusInput()
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
    // Make the first item selected
    changeSelection(by: 1)
  }
  
  func resizeTable() {
    let maxHeight = InputFieldHeight + MaxTableViewHeight + BottomMargin
    
    let neededHeight = InputFieldHeight + (searchResults.count * TableCellHeight) + BottomMargin
    
    let height = (neededHeight < maxHeight) ? neededHeight : maxHeight
    
    let size = NSMakeSize(CGFloat(WindowWidth), CGFloat(height))
    window?.setContentSize(size)
  }
  
  func focusInput() {
    window?.makeFirstResponder(inputField)
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
  
  func changeSelection(by: Int) {
    let length = searchResultsTableView.numberOfRows
    
    let selected = searchResultsTableView.selectedRow
    
    let updated = selected + by
    
    if updated >= length || updated < 0 {
      return
    }
    
    let indexSet = NSIndexSet(index: updated)
    searchResultsTableView.selectRowIndexes(indexSet as IndexSet, byExtendingSelection: false)
    searchResultsTableView.scrollRowToVisible(updated)
  }
  
  @objc func handleSubmit() {
    guard let item = searchResults[at: searchResultsTableView.selectedRow] ?? searchResults.first else { return }
    
    player.playFileInPlaylist(item.playlistIndex)
    
    playlistViewController.playlistTableView.scrollRowToVisible(item.playlistIndex)
    
    hideSearchWindow()
  }
  
}

// MARK: Input Text Field Delegate
extension PlaylistSearchViewController: NSTextFieldDelegate, NSControlTextEditingDelegate {
  func controlTextDidChange(_ obj: Notification) {
    var input = inputField.stringValue
    
    // Removes spaces from pattern
    // If your input was "hello world", the fuzzy match wouldn't match "helloworld" as a favorable option because of the space in between the two words
    input = input.filter {!$0.isWhitespace}
    
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
  
  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    // Esc: clear input or hide window
    if commandSelector == #selector(cancel(_:)) {
      if inputField.stringValue == "" {
        return false
      }
      clearInput()
      return true
    }
    // Up or Shift+Tab: Move table selection up by 1
    else if commandSelector == #selector(moveUp(_:)) || commandSelector == #selector(insertBacktab(_:)) {
      changeSelection(by: -1)
      return true
    }
    // Down or Tab: Move table selection down by 1
    else if commandSelector == #selector(moveDown(_:)) || commandSelector == #selector(insertTab(_:)) {
      changeSelection(by: 1)
      return true
    }
    // Enter: play selected file
    else if commandSelector == #selector(insertNewline(_:)) {
      handleSubmit()
      return false
    }
    return false
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
    
    var a = "" , d = ""
    
    let item = searchItem.item
    
    func getCachedMetadata() -> (artist: String, title: String)? {
      guard Preference.bool(for: .playlistShowMetadata) else { return nil }
      if Preference.bool(for: .playlistShowMetadataInMusicMode) && !player.isInMiniPlayer {
        return nil
      }
      guard let metadata = player.info.getCachedMetadata(item.filename) else { return nil }
      guard let artist = metadata.artist, let title = metadata.title else { return nil }
      return (artist, title)
    }
    
    if let (artist, title) = getCachedMetadata() {
      a = artist
    }
    if let cached = self.player.info.getCachedVideoDurationAndProgress(item.filename), let duration = cached.duration {
      if duration > 0 {
        d = VideoTime(duration).stringRepresentation
      }
    } else {
      
      searchWorkQueue.async {
        
        self.player.refreshCachedVideoInfo(forVideoPath: item.filename)
        
        if let cached = self.player.info.getCachedVideoDurationAndProgress(item.filename), let duration = cached.duration, duration > 0 {
          DispatchQueue.main.async {
            self.searchResultsTableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
          }
        }
      }
      
    }
    
    // Add bold for matching letters
    for index in searchItem.result.pos {
      let range = NSMakeRange(index , 1)
      render.addAttribute(NSAttributedString.Key.font, value: NSFont.boldSystemFont(ofSize: CGFloat(TableCellFontSize)), range: range)
      render.addAttribute(NSAttributedString.Key.foregroundColor, value: NSColor.textColor, range: range)
    }
    
    return [
      "name": render,
      "artist": a,
      "duration": d
    ]
    
  }
  
  // Enables arrow keys to be used in tableview
  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    return true
  }
  
  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    return FixRowView()
  }
  
}

// Fixes bug when system theme is different from IINA's selected theme, the search results would use the system theme's selected row view background instead of IINA's selected theme
class FixRowView: NSTableRowView {
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
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
