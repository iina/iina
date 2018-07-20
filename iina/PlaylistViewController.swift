//
//  PlaylistViewController.swift
//  iina
//
//  Created by lhc on 17/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate let PrefixMinLength = 7
fileprivate let FilenameMinLength = 12

class PlaylistViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, SidebarViewController {

  override var nibName: NSNib.Name {
    return NSNib.Name("PlaylistViewController")
  }

  weak var mainWindow: MainWindowController! {
    didSet {
      self.player = mainWindow.player
    }
  }

  weak var player: PlayerCore!

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
  @IBOutlet weak var tabHeightConstraint: NSLayoutConstraint!
  @IBOutlet weak var deleteBtn: NSButton!
  @IBOutlet weak var loopBtn: NSButton!
  @IBOutlet weak var shuffleBtn: NSButton!
  @IBOutlet var subPopover: NSPopover!
  @IBOutlet var addFileMenu: NSMenu!

  var downShift: CGFloat = 0 {
    didSet {
      buttonTopConstraint.constant = downShift
    }
  }

  var useCompactTabHeight = false {
    didSet {
      tabHeightConstraint.constant = useCompactTabHeight ? 32 : 48
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
    playlistChangeObserver = NotificationCenter.default.addObserver(forName: .iinaPlaylistChanged, object: player, queue: OperationQueue.main) { _ in
      self.reloadData(playlist: true, chapters: false)
    }
    
    // register for double click action
    let action = #selector(performDoubleAction(sender:))
    playlistTableView.doubleAction = action
    playlistTableView.target = self
    
    // register for drag and drop
    playlistTableView.registerForDraggedTypes([.iinaPlaylistItem, .nsFilenames, .nsURL, .string])

    if let popoverView = subPopover.contentViewController?.view,
      popoverView.trackingAreas.isEmpty {
      popoverView.addTrackingArea(NSTrackingArea(rect: popoverView.bounds,
                                                 options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                                                 owner: mainWindow, userInfo: ["obj": 0]))
    }
  }

  override func viewDidAppear() {
    reloadData(playlist: true, chapters: true)

    let loopStatus = player.mpv.getString(MPVOption.PlaybackControl.loopPlaylist)
    loopBtn.state = (loopStatus == "inf" || loopStatus == "force") ? .on : .off
  }

  deinit {
    NotificationCenter.default.removeObserver(self.playlistChangeObserver!)
  }

  func reloadData(playlist: Bool, chapters: Bool) {
    if playlist {
      player.getPlaylist()
      playlistTableView.reloadData()
    }
    if chapters {
      player.getChapters()
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
      return player.info.playlist.count
    } else if tableView == chapterTableView {
      return player.info.chapters.count
    } else {
      return 0
    }
  }
  
  // MARK: - Drag and Drop
  
  
  func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
    if tableView == playlistTableView {
      let indexesData = NSKeyedArchiver.archivedData(withRootObject: rowIndexes)
      let filePaths = rowIndexes.map { player.info.playlist[$0].filename }
      pboard.declareTypes([.iinaPlaylistItem, .nsFilenames], owner: tableView)
      pboard.setData(indexesData, forType: .iinaPlaylistItem)
      pboard.setPropertyList(filePaths, forType: .nsFilenames)
      return true
    }
    return false
  }


  func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
    playlistTableView.setDropRow(row, dropOperation: .above)
    if info.draggingSource() as? NSTableView === tableView {
      return .move
    }
    return player.acceptFromPasteboard(info, isPlaylist: true)
  }

  func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
    let pasteboard = info.draggingPasteboard()

    if info.draggingSource() as? NSTableView === tableView {
      if let rowData = pasteboard.data(forType: .iinaPlaylistItem) {
        let indexSet = NSKeyedUnarchiver.unarchiveObject(with: rowData) as! IndexSet

        let playlistCount = player.info.playlist.count
        var order: [Int] = Array(0..<playlistCount)
        var droppedRow = row
        let reversedIndexSet = indexSet.reversed()

        for selectedRow in reversedIndexSet {
          if selectedRow < row {
            droppedRow -= 1
          }
          order.remove(at: selectedRow)
        }

        for selectedRow in reversedIndexSet {
          order.insert(selectedRow, at: droppedRow)
        }

        let fileList = player.info.playlist.map { $0.filename }
        var current: Int?
        for i in 0..<playlistCount {
          if player.info.playlist[i].isCurrent {
            current = i
            continue
          }
        }
        player.clearPlaylist()

        var before: [String] = []
        var after: [String] = []
        var foundCurrent = false
        for position in order {
          if position == current! {
            foundCurrent = true
            continue
          }
          foundCurrent ? after.append(fileList[position]) : before.append(fileList[position])
        }
        player.addToPlaylist(paths: after, at: 1)
        player.addToPlaylist(paths: before, at: 0)
      }
    } else if let paths = pasteboard.propertyList(forType: .nsFilenames) as? [String] {
      let playableFiles = Utility.resolveURLs(player.getPlayableFiles(in: paths.map{ URL(fileURLWithPath: $0) }))
      if playableFiles.count == 0 {
        return false
      }
      player.addToPlaylist(paths: playableFiles.map { $0.path }, at: row)
    } else if let urls = pasteboard.propertyList(forType: .nsURL) as? [String] {
      player.addToPlaylist(paths: urls, at: row)
    } else if let droppedString = pasteboard.string(forType: .string), Regex.url.matches(droppedString) {
      player.addToPlaylist(paths: [droppedString], at: row)
    } else {
      return false
    }
    player.postNotification(.iinaPlaylistChanged)
    return true
  }

  // MARK: - private methods

  private func withAllTableViews(_ block: (NSTableView) -> Void) {
    block(playlistTableView)
    block(chapterTableView)
  }

  // MARK: - IBActions

  @IBAction func addToPlaylistBtnAction(_ sender: NSButton) {
    addFileMenu.popUp(positioning: nil, at: .zero, in: sender)
  }

  @IBAction func addFileAction(_ sender: AnyObject) {
    Utility.quickMultipleOpenPanel(title: "Add to playlist", canChooseDir: true) { urls in
      let playableFiles = self.player.getPlayableFiles(in: urls)
      if playableFiles.count != 0 {
        self.player.addToPlaylist(paths: playableFiles.map { $0.path }, at: self.player.info.playlist.count)
        self.player.mainWindow.playlistView.reloadData(playlist: true, chapters: false)
        self.player.sendOSD(.addToPlaylist(playableFiles.count))
      }
    }
  }

  @IBAction func addURLAction(_ sender: AnyObject) {
    Utility.quickPromptPanel("add_url") { url in
      if Regex.url.matches(url) {
        self.player.addToPlaylist(url)
        self.player.mainWindow.playlistView.reloadData(playlist: true, chapters: false)
        self.player.sendOSD(.addToPlaylist(1))
      } else {
        Utility.showAlert("wrong_url_format")
      }
    }
  }

  @IBAction func clearPlaylistBtnAction(_ sender: AnyObject) {
    player.clearPlaylist()
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
    player.togglePlaylistLoop()
  }

  @IBAction func shuffleBtnAction(_ sender: AnyObject) {
    player.toggleShuffle()
  }

  
  @objc func performDoubleAction(sender: AnyObject) {
    let tv = sender as! NSTableView
    if tv.numberOfSelectedRows > 0 {
      player.playFileInPlaylist(tv.selectedRow)
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
    vc.filePath = player.info.playlist[row].filename
    vc.tableView.reloadData()
    vc.heightConstraint.constant = (vc.tableView.rowHeight + vc.tableView.intercellSpacing.height) * CGFloat(vc.tableView.numberOfRows)
    subPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    let tv = notification.object as! NSTableView
    guard tv.numberOfSelectedRows > 0 else { return }
    if tv == chapterTableView {
      let index = tv.selectedRow
      player.playChapter(index)
      let chapter = player.info.chapters[index]
      tv.deselectAll(self)
      tv.reloadData()
      mainWindow.displayOSD(.chapter(chapter.title))
    }
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let identifier = tableColumn?.identifier else { return nil }
    let info = player.info
    let v = tableView.makeView(withIdentifier: identifier, owner: self) as! NSTableCellView

    // playlist
    if tableView == playlistTableView {
      guard row < info.playlist.count else { return nil }
      let item = info.playlist[row]

      if identifier == .isChosen {
        v.textField?.stringValue = item.isPlaying ? Constants.String.play : ""
      } else if identifier == .trackName {
        let cellView = v as! PlaylistTrackCellView
        // file name
        let filename = item.filenameForDisplay
        let filenameWithoutExt: String = NSString(string: filename).deletingPathExtension
        if let prefix = player.info.currentVideosInfo.first(where: { $0.path == item.filename })?.prefix,
          !prefix.isEmpty,
          prefix.count <= filenameWithoutExt.count,  // check whether prefix length > filename length
          prefix.count >= PrefixMinLength,
          filename.count > FilenameMinLength {
          cellView.prefixBtn.hasPrefix = true
          cellView.prefixBtn.text = prefix
          cellView.textField?.stringValue = String(filename[filename.index(filename.startIndex, offsetBy: prefix.count)...])
        } else {
          cellView.prefixBtn.hasPrefix = false
          cellView.textField?.stringValue = filename
        }
        // playback progress and duration
        cellView.durationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        cellView.durationLabel.stringValue = ""
        if let cached = player.info.cachedVideoDurationAndProgress[item.filename],
          let duration = cached.duration {
          // if it's cached
          if duration > 0 {
            // if FFmpeg got the duration succcessfully
            cellView.durationLabel.stringValue = VideoTime(duration).stringRepresentation
            if let progress = cached.progress {
              cellView.playbackProgressView.percentage = progress / duration
              cellView.playbackProgressView.needsDisplay = true
            }
          }
        } else {
          // get related data and schedule a reload
          if Preference.bool(for: .prefetchPlaylistVideoDuration) {
            player.playlistQueue.async {
              self.player.refreshCachedVideoProgress(forVideoPath: item.filename)
              DispatchQueue.main.async {
                self.playlistTableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0...1))
              }
            }
          }
        }
        // sub button
        if let matchedSubs = player.info.matchedSubs[item.filename], !matchedSubs.isEmpty {
          cellView.subBtn.isHidden = false
          cellView.subBtnWidthConstraint.constant = 12
        } else {
          cellView.subBtn.isHidden = true
          cellView.subBtnWidthConstraint.constant = 0
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
      let nextChapterTime = chapters[at: row+1]?.time ?? .infinite
      // construct view

      if identifier == .isChosen {
        // left column
        let currentPos = info.videoPosition!
        if currentPos.between(chapter.time, nextChapterTime) {
          v.textField?.stringValue = Constants.String.play
        } else {
          v.textField?.stringValue = ""
        }
        return v
      } else if identifier == .trackName {
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
    let selectedRow = playlistTableView.selectedRowIndexes
    let clickedRow = playlistTableView.clickedRow
    var target = IndexSet()

    if clickedRow != -1 {
      if selectedRow.contains(clickedRow) {
        target = selectedRow
      } else {
        target.insert(clickedRow)
      }
    }

    selectedRows = target
    menu.removeAllItems()
    let items = buildMenu(forRows: target).items
    for item in items {
      menu.addItem(item)
    }
  }

  @IBAction func contextMenuPlayNext(_ sender: NSMenuItem) {
    guard let selectedRows = selectedRows else { return }
    let current = player.mpv.getInt(MPVProperty.playlistPos)
    var ob = 0  // index offset before current playing item
    var mc = 1  // moved item count, +1 because move to next item of current played one
    for item in selectedRows {
      if item == current { continue }
      if item < current {
        player.playlistMove(item + ob, to: current + mc + ob)
        ob -= 1
      } else {
        player.playlistMove(item, to: current + mc + ob)
      }
      mc += 1
    }
    playlistTableView.deselectAll(nil)
    player.postNotification(.iinaPlaylistChanged)
  }

  @IBAction func contextMenuPlayInNewWindow(_ sender: NSMenuItem) {
    let files = selectedRows!.enumerated().map { (_, i) in
      URL(fileURLWithPath: player.info.playlist[i].filename)
    }
    PlayerCore.newPlayerCore.openURLs(files, shouldAutoLoad: false)
  }

  @IBAction func contextMenuRemove(_ sender: NSMenuItem) {
    guard let selectedRows = selectedRows else { return }
    var count = 0
    for item in selectedRows {
      player.playlistRemove(item - count)
      count += 1
    }
    playlistTableView.deselectAll(nil)
    player.postNotification(.iinaPlaylistChanged)
  }

  @IBAction func contextMenuDeleteFile(_ sender: NSMenuItem) {
    guard let selectedRows = selectedRows else { return }
    var count = 0
    for index in selectedRows {
      player.playlistRemove(index)
      guard !player.info.playlist[index].isNetworkResource else { continue }
      let url = URL(fileURLWithPath: player.info.playlist[index].filename)
      do {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        count += 1
      } catch let error {
        Utility.showAlert("playlist.error_deleting", arguments:
          [error.localizedDescription])
      }
    }
    playlistTableView.deselectAll(nil)
    player.postNotification(.iinaPlaylistChanged)
  }

  @IBAction func contextMenuDeleteFileAfterPlayback(_ sender: NSMenuItem) {
    // WIP
  }

  @IBAction func contextMenuRevealInFinder(_ sender: NSMenuItem) {
    guard let selectedRows = selectedRows else { return }
    var urls: [URL] = []
    for index in selectedRows {
      if !player.info.playlist[index].isNetworkResource {
        urls.append(URL(fileURLWithPath: player.info.playlist[index].filename))
      }
    }
    playlistTableView.deselectAll(nil)
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }

  @IBAction func contextMenuAddSubtitle(_ sender: NSMenuItem) {
    guard let selectedRows = selectedRows, let index = selectedRows.first else { return }
    let filename = player.info.playlist[index].filename
    let fileURL = URL(fileURLWithPath: filename).deletingLastPathComponent()
    Utility.quickMultipleOpenPanel(title: NSLocalizedString("alert.choose_media_file.title", comment: "Choose Media File"), dir: fileURL, canChooseDir: true) { subURLs in
      for subURL in subURLs {
        guard Utility.supportedFileExt[.sub]!.contains(subURL.pathExtension.lowercased()) else { return }
        self.player.info.matchedSubs[filename, default: []].append(subURL)
      }
      self.playlistTableView.reloadData(forRowIndexes: selectedRows, columnIndexes: IndexSet(integersIn: 0...1))
    }
  }

  @IBAction func contextMenuWrongSubtitle(_ sender: NSMenuItem) {
    guard let selectedRows = selectedRows else { return }
    for index in selectedRows {
      let filename = player.info.playlist[index].filename
      player.info.matchedSubs[filename]?.removeAll()
      playlistTableView.reloadData(forRowIndexes: selectedRows, columnIndexes: IndexSet(integersIn: 0...1))
    }

  }

  private func buildMenu(forRows rows: IndexSet) -> NSMenu {
    let result = NSMenu()
    let isSingleItem = rows.count == 1

    if !rows.isEmpty {
      let firstURL = player.info.playlist[rows.first!]
      let matchedSubCount = player.info.matchedSubs[firstURL.filename]?.count ?? 0
      let title: String = isSingleItem ?
        firstURL.filenameForDisplay :
        String(format: NSLocalizedString("pl_menu.title_multi", comment: "%d Items"), rows.count)

      result.addItem(withTitle: title)
      result.addItem(NSMenuItem.separator())
      result.addItem(withTitle: NSLocalizedString("pl_menu.play_next", comment: "Play Next"), action: #selector(self.contextMenuPlayNext(_:)))
      result.addItem(withTitle: NSLocalizedString("pl_menu.play_in_new_window", comment: "Play in New Window"), action: #selector(self.contextMenuPlayInNewWindow(_:)))
      result.addItem(withTitle: NSLocalizedString(isSingleItem ? "pl_menu.remove" : "pl_menu.remove_multi", comment: "Remove"), action: #selector(self.contextMenuRemove(_:)))

      if !player.isInMiniPlayer {
        result.addItem(NSMenuItem.separator())
        if isSingleItem {
          result.addItem(withTitle: String(format: NSLocalizedString("pl_menu.matched_sub", comment: "Matched %d Subtitle(s)"), matchedSubCount))
          result.addItem(withTitle: NSLocalizedString("pl_menu.add_sub", comment: "Add Subtitle…"), action: #selector(self.contextMenuAddSubtitle(_:)))
        }
        if matchedSubCount != 0 {
          result.addItem(withTitle: NSLocalizedString("pl_menu.wrong_sub", comment: "Wrong Subtitle"), action: #selector(self.contextMenuWrongSubtitle(_:)))
        }
      }

      result.addItem(NSMenuItem.separator())

      // file related operations
      if rows.contains (where: {!player.info.playlist[$0].isNetworkResource}) {
        result.addItem(withTitle: NSLocalizedString(isSingleItem ? "pl_menu.delete" : "pl_menu.delete_multi", comment: "Delete"), action: #selector(self.contextMenuDeleteFile(_:)))
        // result.addItem(withTitle: NSLocalizedString(isSingleItem ? "pl_menu.delete_after_play" : "pl_menu.delete_after_play_multi", comment: "Delete After Playback"), action: #selector(self.contextMenuDeleteFileAfterPlayback(_:)))

        result.addItem(withTitle: NSLocalizedString("pl_menu.reveal_in_finder", comment: "Reveal in Finder"), action: #selector(self.contextMenuRevealInFinder(_:)))
        result.addItem(NSMenuItem.separator())
      }
    }
    result.addItem(withTitle: NSLocalizedString("pl_menu.add_file", comment: "Add File"), action: #selector(self.addFileAction(_:)))
    result.addItem(withTitle: NSLocalizedString("pl_menu.add_url", comment: "Add URL"), action: #selector(self.addURLAction(_:)))
    result.addItem(withTitle: NSLocalizedString("pl_menu.clear_playlist", comment: "Clear Playlist"), action: #selector(self.clearPlaylistBtnAction(_:)))
    return result
  }

}


class PlaylistTrackCellView: NSTableCellView {

  @IBOutlet weak var subBtn: NSButton!
  @IBOutlet weak var subBtnWidthConstraint: NSLayoutConstraint!
  @IBOutlet weak var prefixBtn: PlaylistPrefixButton!
  @IBOutlet weak var durationLabel: NSTextField!
  @IBOutlet weak var playbackProgressView: PlaylistPlaybackProgressView!

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
    addCursorRect(rect, cursor: .resizeLeftRight)
  }

  // override var allowsVibrancy: Bool { return true }

}


class SubPopoverViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {

  @IBOutlet weak var tableView: NSTableView!
  @IBOutlet weak var playlistTableView: NSTableView!
  @IBOutlet weak var heightConstraint: NSLayoutConstraint!

  lazy var playerCore: PlayerCore = {
    let windowController = self.playlistTableView.window!.windowController
    return (windowController as? MainWindowController)?.player ?? (windowController as! MiniPlayerWindowController).player
  }()

  var filePath: String = ""

  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    return false
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    guard let matchedSubs = playerCore.info.matchedSubs[filePath] else { return nil }
    return matchedSubs[row].lastPathComponent
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    return playerCore.info.matchedSubs[filePath]?.count ?? 0
  }

  @IBAction func wrongSubBtnAction(_ sender: AnyObject) {
    playerCore.info.matchedSubs[filePath]?.removeAll()
    tableView.reloadData()
    if let row = playerCore.info.playlist.index(where: { $0.filename == filePath }) {
      playlistTableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0...1))
    }
  }

}

class ChapterTableCellView: NSTableCellView {

  @IBOutlet weak var durationTextField: NSTextField!

}

