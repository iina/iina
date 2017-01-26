//
//  PlaylistViewController.swift
//  iina
//
//  Created by lhc on 17/8/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class PlaylistViewController: NSViewController, NSTableViewDataSource {

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

  @IBOutlet weak var playlistTableView: NSTableView!
  @IBOutlet weak var chapterTableView: NSTableView!
  @IBOutlet weak var playlistBtn: NSButton!
  @IBOutlet weak var chaptersBtn: NSButton!
  @IBOutlet weak var tabView: NSTabView!
  @IBOutlet weak var deleteBtn: NSButton!

  lazy var playlistDelegate: PlaylistTableDelegate = {
    return PlaylistTableDelegate(self)
  }()

  lazy var chapterDelegate: ChapterTableDelegate = {
    return ChapterTableDelegate(self)
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    withAllTableViews { (view) in
      view.dataSource = self
    }
    playlistTableView.delegate = playlistDelegate
    chapterTableView.delegate = chapterDelegate

    deleteBtn.image?.isTemplate = true

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

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    if tableView == playlistTableView {
      guard row < playerCore.info.playlist.count else { return nil }
      let item = playerCore.info.playlist[row]
      let columnName = tableColumn?.identifier
      if columnName == Constants.Identifier.isChosen {
        return item.isPlaying ? Constants.String.play : ""
      } else if columnName == Constants.Identifier.trackName {
        return item.filenameForDisplay
      } else {
        return nil
      }
    } else {
      return nil
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
        if !playerCore.supportedSubtitleFormat.contains(ext) {
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
      
      let playlistCount = tableView.numberOfRows - 1
      var order: Array<Int> = Array(0...playlistCount)
      var finalRow = row
      
      for selectedRow in indexSet.reversed() {
        if selectedRow < row {
          finalRow -= 1
        }
        order.remove(at: selectedRow)
      }
      
      for selectedRow in indexSet.reversed() {
        order.insert(selectedRow, at: finalRow)
      }
      
      var fileList: [String] = []
      var playing: Int = 0
      for playlistItem in playerCore.info.playlist {
        fileList.append(playlistItem.filename)
        if playlistItem.isPlaying {
          playing = fileList.count - 1
        }
      }
      
      for i in Array(0...playlistCount).reversed() {
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
          playerCore.mpvController.command(.playlistMove, args: [(insertPosition + 1).toStr(), insertPosition.toStr()])
          insertPosition += 1
        }
      }
      
      NotificationCenter.default.post(Notification(name: Constants.Noti.playlistChanged))
      
      tableView.deselectAll(self)
      var finalIndexSet: IndexSet = []
      for i in 0...playlistCount {
        if indexSet.contains(order[i]) {
          finalIndexSet.insert(i)
        }
      }
      tableView.selectRowIndexes(finalIndexSet, byExtendingSelection: false)
      
      return true
      
    } else if let fileNames = pasteboard.propertyList(forType: NSFilenamesPboardType) as? [String] {
      var added = 0
      var currentRow = row
      var playlistItems = tableView.numberOfRows - 1
      fileNames.forEach({ (path) in
        let ext = (path as NSString).pathExtension
        if !playerCore.supportedSubtitleFormat.contains(ext) {
          playerCore.addToPlaylist(path)
          playlistItems += 1
          playerCore.mpvController.command(.playlistMove, args: [playlistItems.toStr(), currentRow.toStr()])
          
          currentRow += 1
          added += 1
        }
      })
      
      if added == 0 {
        return false
      }
      
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
    let _ = Utility.quickOpenPanel(title: "Add to playlist", isDir: false) { (url) in
      if url.isFileURL {
        self.playerCore.addToPlaylist(url.path)
        reloadData(playlist: true, chapters: false)
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
  
  func performDoubleAction(sender: AnyObject) {
    let tv = sender as! NSTableView
    if tv.numberOfSelectedRows > 0 {
      playerCore.playFileInPlaylist(tv.selectedRow)
      tv.deselectAll(self)
      tv.reloadData()
    }
  }

  // MARK: - Table delegates

  class PlaylistTableDelegate: NSObject, NSTableViewDelegate {

    weak var parent: PlaylistViewController!

    init(_ parent: PlaylistViewController) {
      self.parent = parent
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
      return
    }
  }

  class ChapterTableDelegate: NSObject, NSTableViewDelegate {

    weak var parent: PlaylistViewController!

    init(_ parent: PlaylistViewController) {
      self.parent = parent
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
      let tv = notification.object as! NSTableView
      if tv.numberOfSelectedRows > 0 {
        let index = tv.selectedRow
        parent.playerCore.playChapter(index)
        let chapter = parent.playerCore.info.chapters[index]
        tv.deselectAll(self)
        tv.reloadData()
        parent.mainWindow.displayOSD(.chapter(chapter.title))
      }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
      let info = parent.playerCore.info
      let chapters = info.chapters
      let chapter = chapters[row]
      // next chapter time
      let nextChapterTime = chapters.at(row+1)?.time ?? Constants.Time.infinite
      // construct view
      let columnName = tableColumn?.identifier
      if columnName == Constants.Identifier.isChosen {
        // left column
        let v = tableView.make(withIdentifier: Constants.Identifier.isPlayingCell, owner: self) as! NSTableCellView
        let currentPos = info.videoPosition!
        if currentPos.between(chapter.time, nextChapterTime) {
          v.textField?.stringValue = Constants.String.play
        } else {
          v.textField?.stringValue = ""
        }
        return v
      } else if columnName == Constants.Identifier.trackName {
        // right column
        let v = tableView.make(withIdentifier: Constants.Identifier.trackNameCell, owner: self) as! ChapterTableCellView
        v.textField?.stringValue = chapter.title
        v.durationTextField.stringValue = "\(chapter.time.stringRepresentation) → \(nextChapterTime.stringRepresentation)"
        return v
      } else {
        return nil
      }
    }
  }

}
