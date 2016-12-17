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
    
    // handle pending switch tab request
    if pendingSwitchRequest != nil {
      switchToTab(pendingSwitchRequest!)
      pendingSwitchRequest = nil
    }
    
    // nofitications
    playlistChangeObserver = NotificationCenter.default.addObserver(forName: Constants.Noti.playlistChanged, object: nil, queue: OperationQueue.main) { _ in
      self.reloadData(playlist: true, chapters: false)
    }
  }
  
  override func viewDidDisappear() {
    // nofifications
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
    switch tab {
    case .playlist:
      tabView.selectTabViewItem(at: 0)
      playlistBtn.attributedTitle = NSAttributedString(string: "PLAYLIST", attributes: Utility.tabTitleActiveFontAttributes)
      chaptersBtn.attributedTitle = NSAttributedString(string: "CHAPTERS", attributes: Utility.tabTitleFontAttributes)
    case .chapters:
      tabView.selectTabViewItem(at: 1)
      chaptersBtn.attributedTitle = NSAttributedString(string: "CHAPTERS", attributes: Utility.tabTitleActiveFontAttributes)
      playlistBtn.attributedTitle = NSAttributedString(string: "PLAYLIST", attributes: Utility.tabTitleFontAttributes)
    }
  }
  
  // MARK: - NSTableViewSource
  
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
  
  private func withAllTableViews(_ block: (NSTableView) -> Void) {
    block(playlistTableView)
    block(chapterTableView)
  }
  
  // MARK: - IBActions
  
  @IBAction func addToPlaylistBtnAction(_ sender: AnyObject) {
    let _ = Utility.quickOpenPanel(title: "Add to playlist", isDir: false) { (url) in
      if url.isFileURL {
        self.playerCore.addToPlaylist(url.path)
        self.playlistTableView.reloadData()
        self.mainWindow.displayOSD(.addToPlaylist(1))
      }
    }
  }
  
  
  @IBAction func clearPlaylistBtnAction(_ sender: AnyObject) {
    playerCore.clearPlaylist()
    mainWindow.displayOSD(.clearPlaylist)
  }
  
  @IBAction func playlistBtnAction(_ sender: AnyObject) {
    playlistTableView.reloadData()
    switchToTab(.playlist)
  }
  
  @IBAction func chaptersBtnAction(_ sender: AnyObject) {
    chapterTableView.reloadData()
    switchToTab(.chapters)
  }
  
  // MARK: - Table delegates
  
  class PlaylistTableDelegate: NSObject, NSTableViewDelegate {
    
    weak var parent: PlaylistViewController!
    
    init(_ parent: PlaylistViewController) {
      self.parent = parent
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
      let tv = notification.object as! NSTableView
      if tv.numberOfSelectedRows > 0 {
        parent.playerCore.playFileInPlaylist(tv.selectedRow)
        tv.deselectAll(self)
        tv.reloadData()
      }
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
