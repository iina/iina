//
//  PlaylistViewController.swift
//  iina
//
//  Created by lhc on 17/8/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class PlaylistViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, SidebarViewController {

  override var nibName: String {
    return "PlaylistViewController"
  }

  var playerCore: PlayerCore = PlayerCore.shared
  weak var mainWindow: MainWindowController!
  
  let IINAPlaylistItemType = "IINAPlaylistItemType"

  /** Similiar to the one in `QuickSettingViewController`.
   Since IBOutlet is `nil` when the view is not loaded at first time,
   use this variable to cache which tab it need to switch to when the
   view is ready. The value will be handled after loaded.
   */
  private var pendingSwitchRequest: TabViewType?

  var playlistChangeObserver: NSObjectProtocol?

  /** Enum for tab switching */
  enum TabViewType: Int {
    case playlist = 0
    case chapters
  }

  var currentTab: TabViewType = .playlist

  @IBOutlet weak var playlistTableView: NSTableView!
  @IBOutlet weak var chapterTableView: NSTableView!
  @IBOutlet weak var playlistBtn: NSButton!
  @IBOutlet weak var chaptersBtn: NSButton!
  @IBOutlet weak var tabView: NSTabView!
  @IBOutlet weak var buttonTopConstraint: NSLayoutConstraint!
  @IBOutlet weak var deleteBtn: NSButton!
  @IBOutlet weak var loopBtn: NSButton!
  @IBOutlet weak var shuffleBtn: NSButton!
  @IBOutlet var subPopover: NSPopover!
  
  var downShift: CGFloat = 0 {
    didSet {
      buttonTopConstraint.constant = downShift
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    withAllTableViews { (view) in
      view.dataSource = self
    }
    playlistTableView.menu?.delegate = self

    [deleteBtn, loopBtn, shuffleBtn].forEach {
      $0?.image?.isTemplate = true
      $0?.alternateImage?.isTemplate = true
    }


    // handle pending switch tab request
    if pendingSwitchRequest != nil {
      switchToTab(pendingSwitchRequest!)
      pendingSwitchRequest = nil
    }

    // nofitications
    playlistChangeObserver = NotificationCenter.default.addObserver(forName: Constants.Noti.playlistChanged, object: nil, queue: OperationQueue.main) { _ in
      self.reloadData(playlist: true, chapters: false)
    }
    
    // register for double click action
    let action = #selector(performDoubleAction(sender:))
    playlistTableView.doubleAction = action
    playlistTableView.target = self
    
    // register for drag and drop
    playlistTableView.register(forDraggedTypes: [IINAPlaylistItemType, NSFilenamesPboardType])
  }

  override func viewDidAppear() {
    reloadData(playlist: true, chapters: true)

    let loopStatus = playerCore.mpvController.getString(MPVOption.PlaybackControl.loopPlaylist)
    loopBtn.state = (loopStatus == "inf" || loopStatus == "force") ? NSOnState : NSOffState
  }

  deinit {
    NotificationCenter.default.removeObserver(self.playlistChangeObserver!)
  }

  func reloadData(playlist: Bool, chapters: Bool) {
    if playlist {
      playerCore.getPLaylist()
      playlistTableView.reloadData()
    }
    if chapters {
      playerCore.getChapters()
      chapterTableView.reloadData()
    }
  }

  // MARK: - Tab switching

  /** Switch tab (call from other objects) */
  func pleaseSwitchToTab(_ tab: TabViewType) {
    if isViewLoaded {
      switchToTab(tab)
    } else {
      // cache the request
      pendingSwitchRequest = tab
    }
  }

  /** Switch tab (for internal call) */
  private func switchToTab(_ tab: TabViewType) {
    let playlistStr = NSLocalizedString("playlist.playlist_cap", comment: "PLAYLIST")
    let chapterStr = NSLocalizedString("playlist.chapter_cap", comment: "CHAPTERS")

    switch tab {
    case .playlist:
      tabView.selectTabViewItem(at: 0)
      playlistBtn.attributedTitle = NSAttributedString(string: playlistStr, attributes: Utility.tabTitleActiveFontAttributes)
      chaptersBtn.attributedTitle = NSAttributedString(string: chapterStr, attributes: Utility.tabTitleFontAttributes)
    case .chapters:
      tabView.selectTabViewItem(at: 1)
      chaptersBtn.attributedTitle = NSAttributedString(string: chapterStr, attributes: Utility.tabTitleActiveFontAttributes)
      playlistBtn.attributedTitle = NSAttributedString(string: playlistStr, attributes: Utility.tabTitleFontAttributes)
    }

    currentTab = tab
  }

  // MARK: - NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    if tableView == playlistTableView {
      return playerCore.info.playlist.count
    } else if tableView == chapterTableView {
      return playerCore.info.chapters.count
    } else {
      return 0
    }
  }
  
  // MARK: - Drag and Drop
  
  
  func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
    let data = NSKeyedArchiver.archivedData(withRootObject: [rowIndexes])
    pboard.declareTypes([IINAPlaylistItemType], owner:self)
    pboard.setData(data, forType:IINAPlaylistItemType)
    return true
  }


  func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableViewDropOperation) -> NSDragOperation {
    let pasteboard = info.draggingPasteboard()

    if let fileNames = pasteboard.propertyList(forType: NSFilenamesPboardType) as? [String] {
      var hasItemToAdd: Bool = false
      for path in fileNames {
        let ext = (path as NSString).pathExtension
        if !Utility.supportedFileExt[.sub]!.contains(ext) {
          hasItemToAdd = true
          break
        }
      }

      if !hasItemToAdd {
        return []
      }
      playlistTableView.setDropRow(row, dropOperation: .above)
      return .copy
    }
    if let _ = pasteboard.propertyList(forType: IINAPlaylistItemType) {
      playlistTableView.setDropRow(row, dropOperation: .above)
      return .move
    }
    return []
  }

  func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableViewDropOperation) -> Bool {
    let pasteboard = info.draggingPasteboard()

    if let rowData = pasteboard.data(forType: IINAPlaylistItemType) {
      var dataArray = NSKeyedUnarchiver.unarchiveObject(with: rowData) as! Array<IndexSet>
      let indexSet = dataArray[0]

      let playlistCount = playerCore.info.playlist.count - 1
      var order: [Int] = Array(0...playlistCount)
      var finalRow = row
      let reversedIndexSet = indexSet.reversed()

      for selectedRow in reversedIndexSet {
        if selectedRow < row {
          finalRow -= 1
        }
        order.remove(at: selectedRow)
      }

      for selectedRow in reversedIndexSet {
        order.insert(selectedRow, at: finalRow)
      }

      var fileList: [String] = []
      var playing = 0
      for playlistItem in playerCore.info.playlist {
        fileList.append(playlistItem.filename)
        if playlistItem.isPlaying {
          playing = fileList.count - 1
        }
      }

      for i in (0...playlistCount).reversed() {
        if i == playing {
          continue
        }
        playerCore.removeFromPlaylist(index: i)
      }

      var insertPosition = 0
      var foundPlaying: Bool = false

      for i in 0...playlistCount {
        if order[i] == playing {
          foundPlaying = true
          continue
        }
        playerCore.addToPlaylist(fileList[order[i]])
        if !foundPlaying {
          playerCore.playlistMove(insertPosition + 1, to: insertPosition)
          insertPosition += 1
        }
      }

      NotificationCenter.default.post(Notification(name: Constants.Noti.playlistChanged))

      var finalIndexSet: IndexSet = []
      for i in 0...playlistCount {
        if tableView.selectedRowIndexes.contains(order[i]) {
          finalIndexSet.insert(i)
        }
      }
      tableView.deselectAll(self)
      tableView.selectRowIndexes(finalIndexSet, byExtendingSelection: false)

      return true

    } else if let fileNames = pasteboard.propertyList(forType: NSFilenamesPboardType) as? [String] {
      var added = 0
      var currentRow = row
      var playlistItems = tableView.numberOfRows - 1
      fileNames.forEach({ (path) in
        let ext = (path as NSString).pathExtension
        if !Utility.supportedFileExt[.sub]!.contains(ext)  {
          playerCore.addToPlaylist(path)
          playlistItems += 1
          playerCore.playlistMove(playlistItems, to: currentRow)
          currentRow += 1
          added += 1
        }
      })

      if added == 0 {
        return false
      }
      
      var finalIndexSet: IndexSet = []
      let selectedIndexSet: IndexSet = tableView.selectedRowIndexes
      for i in selectedIndexSet {
        if i >= row {
          finalIndexSet.insert(i + added)
        } else {
          finalIndexSet.insert(i)
        }
      }
      tableView.deselectAll(self)
      tableView.selectRowIndexes(finalIndexSet, byExtendingSelection: false)

      NotificationCenter.default.post(Notification(name: Constants.Noti.playlistChanged))
      playerCore.sendOSD(.addToPlaylist(added))
      return true
    } else {
      return false
    }
  }

  // MARK: - private methods

  private func withAllTableViews(_ block: (NSTableView) -> Void) {
    block(playlistTableView)
    block(chapterTableView)
  }

  // MARK: - IBActions

  @IBAction func addToPlaylistBtnAction(_ sender: AnyObject) {
    Utility.quickOpenPanel(title: "Add to playlist", isDir: false) { (url) in
      if url.isFileURL {
        self.playerCore.addToPlaylist(url.path)
        self.reloadData(playlist: true, chapters: false)
        self.mainWindow.displayOSD(.addToPlaylist(1))
      }
    }
  }


  @IBAction func clearPlaylistBtnAction(_ sender: AnyObject) {
    playerCore.clearPlaylist()
    reloadData(playlist: true, chapters: false)
    mainWindow.displayOSD(.clearPlaylist)
  }

  @IBAction func playlistBtnAction(_ sender: AnyObject) {
    reloadData(playlist: true, chapters: false)
    switchToTab(.playlist)
  }

  @IBAction func chaptersBtnAction(_ sender: AnyObject) {
    reloadData(playlist: false, chapters: true)
    switchToTab(.chapters)
  }

  @IBAction func loopBtnAction(_ sender: AnyObject) {
    playerCore.togglePlaylistLoop()
  }

  @IBAction func shuffleBtnAction(_ sender: AnyObject) {
    playerCore.toggleShuffle()
  }

  
  func performDoubleAction(sender: AnyObject) {
    let tv = sender as! NSTableView
    if tv.numberOfSelectedRows > 0 {
      playerCore.playFileInPlaylist(tv.selectedRow)
      tv.deselectAll(self)
      tv.reloadData()
    }
  }

  // MARK: - Table delegates

  @IBAction func prefixBtnAction(_ sender: PlaylistPrefixButton) {
    sender.isFolded = !sender.isFolded
  }

  @IBAction func subBtnAction(_ sender: NSButton) {
    let row = playlistTableView.row(for: sender)
    guard let vc = subPopover.contentViewController as? SubPopoverViewController else { return }
    vc.filePath = playerCore.info.playlist[row].filename
    vc.tableView.reloadData()
    subPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    let tv = notification.object as! NSTableView
    guard tv.numberOfSelectedRows > 0 else { return }
    if tv == chapterTableView {
      let index = tv.selectedRow
      playerCore.playChapter(index)
      let chapter = playerCore.info.chapters[index]
      tv.deselectAll(self)
      tv.reloadData()
      mainWindow.displayOSD(.chapter(chapter.title))
    }
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let identifier = tableColumn?.identifier else { return nil }
    let info = playerCore.info
    let v = tableView.make(withIdentifier: identifier, owner: self) as! NSTableCellView

    // playlist
    if tableView == playlistTableView {
      guard row < info.playlist.count else { return nil }
      let item = info.playlist[row]

      if identifier == Constants.Identifier.isChosen {
        v.textField?.stringValue = item.isPlaying ? Constants.String.play : ""
      } else if identifier == Constants.Identifier.trackName {
        let cellView = v as! PlaylistTrackCellView
        // file name
        let filename = item.filenameForDisplay
        let filenameWithoutExt: String = NSString(string: filename).deletingPathExtension
        if let prefix = playerCore.info.currentVideosInfo.first(where: { $0.path == item.filename })?.prefix, !prefix.isEmpty,
          prefix.characters.count <= filenameWithoutExt.characters.count {  // check whether prefix length > filename length
          cellView.prefixBtn.hasPrefix = true
          cellView.prefixBtn.text = prefix
          cellView.textField?.stringValue = filename.substring(from: filename.index(filename.startIndex, offsetBy: prefix.characters.count))
        } else {
          cellView.prefixBtn.hasPrefix = false
          cellView.textField?.stringValue = filename
        }
        // sub button
        if let matchedSubs = playerCore.info.matchedSubs[item.filename], !matchedSubs.isEmpty {
          cellView.subBtn.isHidden = false
        } else {
          cellView.subBtn.isHidden = true
        }
        cellView.subBtn.image?.isTemplate = true
      }
      return v
    }
    // chapter
    else if tableView == chapterTableView {
      let chapters = info.chapters
      let chapter = chapters[row]
      // next chapter time
      let nextChapterTime = chapters.at(row+1)?.time ?? Constants.Time.infinite
      // construct view

      if identifier == Constants.Identifier.isChosen {
        // left column
        let currentPos = info.videoPosition!
        if currentPos.between(chapter.time, nextChapterTime) {
          v.textField?.stringValue = Constants.String.play
        } else {
          v.textField?.stringValue = ""
        }
        return v
      } else if identifier == Constants.Identifier.trackName {
        // right column
        let cellView = v as! ChapterTableCellView
        cellView.textField?.stringValue = chapter.title.isEmpty ? "Chapter \(row)" : chapter.title
        cellView.durationTextField.stringValue = "\(chapter.time.stringRepresentation) → \(nextChapterTime.stringRepresentation)"
        return cellView
      } else {
        return nil
      }
    }
    else {
      return nil
    }
  }

  // MARK: - Context menu

  var selectedRows: IndexSet?

  func menuNeedsUpdate(_ menu: NSMenu) {
    var indexSet = playlistTableView.selectedRowIndexes
    if playlistTableView.clickedRow >= 0 {
      indexSet.insert(playlistTableView.clickedRow)
    }

    selectedRows = indexSet
    menu.removeAllItems()
    let items = buildMenu(forRows: indexSet).items
    for item in items {
      menu.addItem(item)
    }
  }

  @IBAction func contextMenuPlayNext(_ sender: NSMenuItem) {
    guard let selectedRows = selectedRows else { return }
    let current = playerCore.mpvController.getInt(MPVProperty.playlistPos)
    var ob = 0  // index offset before current playing item
    var mc = 1  // moved item count, +1 because move to next item of current played one
    for item in selectedRows {
      if item == current { continue }
      if item < current {
        playerCore.playlistMove(item + ob, to: current + mc + ob)
        ob -= 1
      } else {
        playerCore.playlistMove(item, to: current + mc + ob)
      }
      mc += 1
    }
    playlistTableView.deselectAll(nil)
    NotificationCenter.default.post(Notification(name: Constants.Noti.playlistChanged))
  }

  @IBAction func contextMenuRemove(_ sender: NSMenuItem) {
    guard let selectedRows = selectedRows else { return }
    var count = 0
    for item in selectedRows {
      playerCore.playlistRemove(item - count)
      count += 1
    }
    playlistTableView.deselectAll(nil)
    NotificationCenter.default.post(Notification(name: Constants.Noti.playlistChanged))
  }

  @IBAction func contextMenuDeleteFile(_ sender: NSMenuItem) {
    guard let selectedRows = selectedRows else { return }
    var count = 0
    for index in selectedRows {
      playerCore.playlistRemove(index)
      let url = URL(fileURLWithPath: playerCore.info.playlist[index].filename)
      do {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        count += 1
      } catch let error {
        Utility.showAlert("playlist.error_deleting", arguments:
          [error.localizedDescription])
      }
    }
    playlistTableView.deselectAll(nil)
    NotificationCenter.default.post(Notification(name: Constants.Noti.playlistChanged))
  }

  @IBAction func contextMenuDeleteFileAfterPlayback(_ sender: NSMenuItem) {
    // WIP
  }

  @IBAction func contextMenuRevealInFinder(_ sender: NSMenuItem) {
    guard let selectedRows = selectedRows else { return }
    var urls: [URL] = []
    for index in selectedRows {
      urls.append(URL(fileURLWithPath: playerCore.info.playlist[index].filename))
    }
    playlistTableView.deselectAll(nil)
    NSWorkspace.shared().activateFileViewerSelecting(urls)
  }

  @IBAction func contextMenuAddSubtitle(_ sender: NSMenuItem) {
    guard let selectedRows = selectedRows, let index = selectedRows.first else { return }
    let filename = playerCore.info.playlist[index].filename
    let fileURL = URL(fileURLWithPath: filename).deletingLastPathComponent()
    Utility.quickMultipleOpenPanel(title: NSLocalizedString("alert.choose_media_file.title", comment: "Choose Media File"), dir: fileURL) { subURLs in
      for subURL in subURLs {
        guard Utility.supportedFileExt[.sub]!.contains(subURL.pathExtension) else { return }
        self.playerCore.info.matchedSubs.safeAppend(subURL, for: filename)
      }
      self.playlistTableView.reloadData(forRowIndexes: selectedRows, columnIndexes: IndexSet(integersIn: 0...1))
    }
  }

  @IBAction func contextMenuWrongSubtitle(_ sender: NSMenuItem) {
    guard let selectedRows = selectedRows else { return }
    for index in selectedRows {
      let filename = playerCore.info.playlist[index].filename
      playerCore.info.matchedSubs[filename]?.removeAll()
      playlistTableView.reloadData(forRowIndexes: selectedRows, columnIndexes: IndexSet(integersIn: 0...1))
    }

  }

  private func buildMenu(forRows rows: IndexSet) -> NSMenu {
    let result = NSMenu()
    let isSingleItem = rows.count == 1

    if !rows.isEmpty {
      let firstURL = playerCore.info.playlist[rows.first!]
      let matchedSubCount = playerCore.info.matchedSubs[firstURL.filename]?.count ?? 0
      let title: String = isSingleItem ?
        firstURL.filenameForDisplay :
        String(format: NSLocalizedString("pl_menu.title_multi", comment: "%d Items"), rows.count)

      result.addItem(withTitle: title)
      result.addItem(NSMenuItem.separator())
      result.addItem(withTitle: NSLocalizedString("pl_menu.play_next", comment: "Play Next"), action: #selector(self.contextMenuPlayNext(_:)))
      result.addItem(withTitle: NSLocalizedString(isSingleItem ? "pl_menu.remove" : "pl_menu.remove_multi", comment: "Remove"), action: #selector(self.contextMenuRemove(_:)))

      result.addItem(NSMenuItem.separator())
      if isSingleItem {
        result.addItem(withTitle: String(format: NSLocalizedString("pl_menu.matched_sub", comment: "Matched %d Subtitle(s)"), matchedSubCount))
        result.addItem(withTitle: NSLocalizedString("pl_menu.add_sub", comment: "Add Subtitle…"), action: #selector(self.contextMenuAddSubtitle(_:)))
      }
      result.addItem(withTitle: NSLocalizedString("pl_menu.wrong_sub", comment: "Wrong Subtitle"), action: #selector(self.contextMenuWrongSubtitle(_:)))

      result.addItem(NSMenuItem.separator())
      result.addItem(withTitle: NSLocalizedString(isSingleItem ? "pl_menu.delete" : "pl_menu.delete_multi", comment: "Delete"), action: #selector(self.contextMenuDeleteFile(_:)))
      // result.addItem(withTitle: NSLocalizedString(isSingleItem ? "pl_menu.delete_after_play" : "pl_menu.delete_after_play_multi", comment: "Delete After Playback"), action: #selector(self.contextMenuDeleteFileAfterPlayback(_:)))

      // result.addItem(NSMenuItem.separator())
      result.addItem(withTitle: NSLocalizedString("pl_menu.reveal_in_finder", comment: "Reveal in Finder"), action: #selector(self.contextMenuRevealInFinder(_:)))
      result.addItem(NSMenuItem.separator())
    }
    result.addItem(withTitle: NSLocalizedString("pl_menu.add_item", comment: "Add Item"), action: #selector(self.addToPlaylistBtnAction(_:)))
    result.addItem(withTitle: NSLocalizedString("pl_menu.clear_playlist", comment: "Clear Playlist"), action: #selector(self.clearPlaylistBtnAction(_:)))
    return result
  }

}


class PlaylistTrackCellView: NSTableCellView {

  @IBOutlet weak var subBtn: NSButton!
  @IBOutlet weak var prefixBtn: PlaylistPrefixButton!

}


class PlaylistPrefixButton: NSButton {

  var text = "" {
    didSet {
      refresh()
    }
  }

  var hasPrefix = true {
    didSet {
      refresh()
    }
  }

  var isFolded = true {
    didSet {
      refresh()
    }
  }

  private func refresh() {
    self.title = hasPrefix ? (isFolded ? "…" : text) : ""
  }

}


class PlaylistView: NSView {

  override func resetCursorRects() {
    let rect = NSRect(x: frame.origin.x - 4, y: frame.origin.y, width: 4, height: frame.height)
    addCursorRect(rect, cursor: NSCursor.resizeLeftRight())
  }

}


class SubPopoverViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {

  @IBOutlet weak var tableView: NSTableView!
  @IBOutlet weak var playlistTableView: NSTableView!

  var filePath: String = ""

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    guard let matchedSubs = PlayerCore.shared.info.matchedSubs[filePath] else { return nil }
    return matchedSubs[row].lastPathComponent
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    return PlayerCore.shared.info.matchedSubs[filePath]?.count ?? 0
  }

  @IBAction func wrongSubBtnAction(_ sender: AnyObject) {
    PlayerCore.shared.info.matchedSubs[filePath]?.removeAll()
    if let row = PlayerCore.shared.info.playlist.index(where: { $0.filename == filePath }) {
      playlistTableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0...1))
    }
  }

}
