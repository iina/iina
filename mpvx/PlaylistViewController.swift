//
//  PlaylistViewController.swift
//  mpvx
//
//  Created by lhc on 17/8/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class PlaylistViewController: NSViewController, NSTableViewDataSource {
  
  override var nibName: String {
    return "PlaylistView"
  }
  
  weak var playerCore: PlayerCore!
  weak var mainWindow: MainWindowController!
  
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
  }
  
  // MARK: - NSTableViewDelegate
  
  func numberOfRows(in tableView: NSTableView) -> Int {
    if tableView == playlistTableView {
      return playerCore.info.playlist.count
    } else if tableView == chapterTableView {
      return playerCore.info.chapters.count
    } else {
      return 0
    }
  }
  
  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
    if tableView == playlistTableView {
      let item = playerCore.info.playlist[row]
      let columnName = tableColumn?.identifier
      if columnName == Constants.Identifier.isChosen {
        return item.isPlaying ? Constants.String.play : ""
      } else if columnName == Constants.Identifier.trackName {
        return item.title ?? NSString(string: item.filename).lastPathComponent
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
    Utility.quickOpenPanel(title: "Add to playlist") { (url) in
      if url.isFileURL, let path = url.path{
        self.playerCore.addToPlaylist(path)
        self.playlistTableView.reloadData()
      }
    }
  }
  
  @IBAction func playlistBtnAction(_ sender: AnyObject) {
    tabView.selectTabViewItem(at: 0)
    playlistTableView.reloadData()
    playlistBtn.attributedTitle = AttributedString(string: "PLAYLIST", attributes: Utility.tabTitleActiveFontAttributes)
    chaptersBtn.attributedTitle = AttributedString(string: "CHAPTERS", attributes: Utility.tabTitleFontAttributes)
  }
  
  @IBAction func chaptersBtnAction(_ sender: AnyObject) {
    tabView.selectTabViewItem(at: 1)
    chapterTableView.reloadData()
    chaptersBtn.attributedTitle = AttributedString(string: "CHAPTERS", attributes: Utility.tabTitleActiveFontAttributes)
    playlistBtn.attributedTitle = AttributedString(string: "PLAYLIST", attributes: Utility.tabTitleFontAttributes)
  }
  
  // MARK: - Delegate class definition
  
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
      let nextChapterTime: VideoTime
      // next chapter time
      if row < chapters.count - 1 {
        nextChapterTime = chapters[row+1].time
      } else {
        nextChapterTime = info.videoDuration ?? VideoTime(99, 0, 0)
      }
      // construct view
      let columnName = tableColumn?.identifier
      if columnName == Constants.Identifier.isChosen {
        let v = tableView.make(withIdentifier: Constants.Identifier.isPlayingCell, owner: self) as! NSTableCellView
        let currentPos = info.videoPosition
        if currentPos >= chapter.time && currentPos < nextChapterTime {
          v.textField?.stringValue = Constants.String.play
        } else {
          v.textField?.stringValue = ""
        }
        return v
      } else if columnName == Constants.Identifier.trackName {
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
