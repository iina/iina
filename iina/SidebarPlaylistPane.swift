//
//  SidebarPlaylistPane.swift
//  iina
//
//  Created by Hechen Li on 2026-06-19.
//  Copyright © 2026 lhc. All rights reserved.
//

fileprivate let PrefixMinLength = 7
fileprivate let FilenameMinLength = 12

fileprivate let MenuItemTagCut = 601
fileprivate let MenuItemTagCopy = 602
fileprivate let MenuItemTagPaste = 603
fileprivate let MenuItemTagDelete = 604


fileprivate let ui = UIHelper.shared

fileprivate extension LayoutValue {
  static let toolbarPaddingVertical = LayoutValue(10, 6)
  static let toolbarPaddingHorizontal = LayoutValue(12, 10)
  static let tableRowHeight = LayoutValue(30, 26)
}


class SidebarPlaylistPane: NSView, SidebarPane {
  let prefObserver = Preference.Observer()
  weak var player: PlayerCore!

  private var scrollView: NSScrollView!
  var tableView: NSTableView!
  private var addBtn: NSButton!
  private var removeBtn: NSButton!
  private var deleteBtn: NSButton!
  private var loopBtn: NSButton!
  private var shuffleBtn: NSButton!
  private var sortBtn: NSButton!
  private var totalLengthLabel: NSTextField!
  private var addFileMenu: NSMenu!

  var horizontalScroll: ((Bool) -> Void)?

  @Atomic private var playlistTotalLengthIsReady = false
  @Atomic private var playlistTotalLength: Double? = nil

  var selectedRows: IndexSet?

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    self.addFileMenu = NSMenu()
    addFileMenu.addItem(
      withTitle: NSLocalizedString("sidebar.add_file", comment: ""), action: #selector(addFileAction), target: self)
    addFileMenu.addItem(
      withTitle: NSLocalizedString("sidebar.add_url", comment: ""), action: #selector(addURLAction), target: self)

    func makeButton(_ title: String, _ image: NSImage, _ action: Selector) -> NSButton {
      let btn = NSButton(image: image, target: self, action: action)
      btn.isBordered = false
      btn.toolTip = NSLocalizedString("mini_player.\(title)", comment: title)
      return btn
    }

    loopBtn = makeButton("loop", .loop, #selector(loopBtnAction))
    loopBtn.bezelStyle = .smallSquare
    loopBtn.setButtonType(.toggle)
    loopBtn.allowsMixedState = true
    loopBtn.alternateImage = .loopDark
    shuffleBtn = makeButton("shuffle", .sf("shuffle")!, #selector(shuffleBtnAction))
    sortBtn = makeButton("sort", .sf("arrow.up.arrow.down")!, #selector(sortBtnAction))
    addBtn = makeButton("add", .plus, #selector(addToPlaylistBtnAction))
    removeBtn = makeButton("remove", .minus, #selector(removeBtnAction))
    deleteBtn = makeButton("delete", .sf("trash")!, #selector(clearPlaylistBtnAction))

    totalLengthLabel = NSTextField(labelWithString: "")
    totalLengthLabel.textColor = .secondaryLabelColor
    totalLengthLabel.font = .controlContentFont(ofSize: 11)
    totalLengthLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    hideTotalLength()

    self.scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false

    self.tableView = NSTableView()
    tableView.style = .fullWidth
    tableView.intercellSpacing = .init(width: 4, height: 2)
    tableView.allowsColumnResizing = false
    tableView.allowsEmptySelection = true
    tableView.allowsMultipleSelection = true
    tableView.delegate = self
    tableView.dataSource = self
    tableView.menu = NSMenu()
    tableView.menu!.delegate = self
    tableView.target = self
    tableView.doubleAction = #selector(doubleAction)
    tableView.registerForDraggedTypes([.iinaPlaylistItem, .nsFilenames, .nsURL, .string])
    tableView.headerView = nil
    tableView.backgroundColor = .sidebarTableBackground
    tableView.gridStyleMask = [.solidHorizontalGridLineMask]

    tableView.rowHeight = LayoutValue.tableRowHeight.get()
    LayoutValue.tableRowHeight.use { [weak self] val in
      self?.tableView.rowHeight = val
      self?.tableView.reloadData()
    }

    let isChosenColumn = NSTableColumn(identifier: .isChosen)
    isChosenColumn.width = 16
    tableView.addTableColumn(isChosenColumn)
    tableView.addTableColumn(NSTableColumn(identifier: .trackName))

    scrollView.documentView = tableView

    let buttonContainer = NSView()
    buttonContainer.translatesAutoresizingMaskIntoConstraints = false

    let buttonStack = ui.hStack(spacing: 8)
    buttonStack.distribution = .gravityAreas

    [loopBtn, shuffleBtn, sortBtn].forEach {
      buttonStack.addView($0, in: .leading)
    }
    buttonStack.addView(totalLengthLabel, in: .center)
    [addBtn, removeBtn, deleteBtn].forEach {
      buttonStack.addView($0, in: .trailing)
    }
    buttonContainer.addSubview(buttonStack)
    buttonStack.padding(.horizontal(.toolbarPaddingHorizontal), .vertical(.toolbarPaddingVertical))

    addSubview(scrollView)
    addSubview(buttonContainer)

    scrollView.padding(.top, .horizontal).spacing(.bottom, to: buttonContainer)
    buttonContainer.padding(.bottom, .horizontal)

    prefObserver.addAll(.playlistShowMetadata, .playlistShowMetadataInMusicMode) { [unowned self] _ in
      updateTable()
    }

    player.observe(.iinaFileLoaded) { [unowned self] _ in
      updateTable()
    }

    player.observe(.iinaPlaylistChanged) { [unowned self] _ in
      playlistTotalLengthIsReady = false
      updateTable()
    }

    player.observe(.iinaLoopStatusChanged) { [unowned self] _ in
      updateLoopBtnStatus()
    }

    updateTable()
  }

  private func update() {
    updateTable()
    updateLoopBtnStatus()
  }

  private func updateTable() {
    guard player.info.state.active else { return }
    player.getPlaylist()
    tableView.reloadData()
  }

  func updateLoopBtnStatus() {
    guard player.info.state.active else { return }
    let loopMode = player.getLoopMode()
    loopBtn.state = switch loopMode {
    case .off: .off
    case .file: .on
    default: .mixed
    }
    loopBtn.alternateImage = NSImage.init(named: loopBtn.state == .on ? "loop_file" : "loop_dark")
  }


  // MARK: - Total length

  private func showTotalLength() {
    guard let playlistTotalLength = playlistTotalLength, playlistTotalLengthIsReady else { return }
    totalLengthLabel.isHidden = false
    if tableView.numberOfSelectedRows > 0 {
      let info = player.info
      let selectedDuration = info.calculateTotalDuration(tableView.selectedRowIndexes)
      totalLengthLabel.stringValue = String(format: NSLocalizedString("playlist.total_length_with_selected", comment: "%@ of %@ selected"),
                                            VideoTime(selectedDuration).stringRepresentation,
                                            VideoTime(playlistTotalLength).stringRepresentation)
    } else {
      totalLengthLabel.stringValue = String(format: NSLocalizedString("playlist.total_length", comment: "%@ in total"),
                                            VideoTime(playlistTotalLength).stringRepresentation)
    }
  }

  private func hideTotalLength() {
    totalLengthLabel.stringValue = ""
    totalLengthLabel.isHidden = true
  }

  func refreshTotalLength() {
    let totalDuration: Double? = player.info.calculateTotalDuration()
    if let duration = totalDuration {
      playlistTotalLengthIsReady = true
      playlistTotalLength = duration
      DispatchQueue.main.async {
        self.showTotalLength()
      }
    } else {
      DispatchQueue.main.async {
        self.hideTotalLength()
      }
    }
  }

  // MARK: - Actions

  @objc func copy(_ sender: NSMenuItem) {
    copyToPasteboard(tableView, writeRowsWith: tableView.selectedRowIndexes, to: .general)
  }

  @objc func cut(_ sender: NSMenuItem) {
    copy(sender)
    delete(sender)
  }

  @objc func paste(_ sender: NSMenuItem) {
    let dest = tableView.selectedRowIndexes.first ?? 0
    pasteFromPasteboard(row: dest, from: .general)
  }


  @objc func delete(_ sender: NSMenuItem) {
    player.playlistRemove(tableView.selectedRowIndexes)
  }

  @objc func addToPlaylistBtnAction(_ sender: NSButton) {
    addFileMenu.popUp(positioning: nil, at: .zero, in: sender)
  }

  @objc func removeBtnAction(_ sender: NSButton) {
    player.playlistRemove(tableView.selectedRowIndexes)
  }

  @objc func addFileAction(_ sender: AnyObject) {
    Utility.quickMultipleOpenPanel(title: "Add to playlist", canChooseDir: true) { urls in
      let playableFiles = self.player.getPlayableFiles(in: urls)
      if playableFiles.count != 0 {
        self.player.addToPlaylist(paths: playableFiles.map { $0.path },
                                  at: self.player.info.$playlist.withLock { $0.count })
        self.updateTable()
        self.player.sendOSD(.addToPlaylist(playableFiles.count))
      }
    }
  }

  @objc func addURLAction(_ sender: AnyObject) {
    Utility.quickPromptPanel("add_url") { url in
      if Regex.url.matches(url) {
        self.player.appendToPlaylist(url)
        self.updateTable()
        self.player.sendOSD(.addToPlaylist(1))
      } else {
        Utility.showAlert("wrong_url_format")
      }
    }
  }

  @objc func clearPlaylistBtnAction(_ sender: AnyObject) {
    player.clearPlaylist()
    player.sendOSD(.clearPlaylist)
  }

  @objc func loopBtnAction(_ sender: NSButton) {
    player.nextLoopMode()
  }

  @objc func shuffleBtnAction(_ sender: AnyObject) {
    player.toggleShuffle()
  }

  @objc func doubleAction(_ sender: AnyObject) {
    guard tableView.numberOfSelectedRows > 0 else { return }
    player.playFileInPlaylist(tableView.selectedRow)
    tableView.deselectAll(self)
    tableView.reloadData()
  }

  // MARK: - Sorting

  @objc func sortBtnAction(_ sender: NSButton) {
    let menu = NSMenu()
    if #available(macOS 14.0, *) {
      menu.addItem(.sectionHeader(title: NSLocalizedString("playlist.sorting.header", comment: "Sorting")))
    }
    menu.addItem(withTitle: NSLocalizedString("playlist.sorting.filename_ascending", comment: "Filename Ascending"), action: #selector(sortPathAscending), keyEquivalent: "")
    menu.addItem(withTitle: NSLocalizedString("playlist.sorting.filename_descending", comment: "Filename Descending"), action: #selector(sortPathDesecnding), keyEquivalent: "")
    menu.addItem(withTitle: NSLocalizedString("playlist.sorting.path_ascending", comment: "File Path Ascending"), action: #selector(sortPathAscending), keyEquivalent: "")
    menu.addItem(withTitle: NSLocalizedString("playlist.sorting.path_descending", comment: "File Path Descending"), action: #selector(sortPathDesecnding), keyEquivalent: "")
    NSMenu.popUpContextMenu(menu, with: NSApplication.shared.currentEvent!, for: sender)
  }

  @objc func sortNameAscending() { sortName(ascending: true) }
  @objc func sortNameDesecnding() { sortName(ascending: false) }
  @objc func sortPathAscending() { sortPath(ascending: true) }
  @objc func sortPathDesecnding() { sortPath(ascending: false) }

  private func sortName(ascending: Bool) {
    var playlist = player.info.playlist
    playlist.sort(by: {
      let results = $0.filenameForDisplay < $1.filenameForDisplay
      return ascending ? results : !results
    })
    player.playlistReorder(newPlaylist: playlist)
  }

  private func sortPath(ascending: Bool) {
    var playlist = player.info.playlist
    playlist.sort(by: {
      let results = $0.filename < $1.filename
      return ascending ? results : !results
    })
    player.playlistReorder(newPlaylist: playlist)
  }


  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

// MARK: - Table view

extension SidebarPlaylistPane: NSTableViewDelegate, NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    return player.info.$playlist.withLock { $0.count }
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    LayoutValue.tableRowHeight.get()
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    showTotalLength()
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let identifier = tableColumn?.identifier else { return nil }

    let item: MPVPlaylistItem? = player.info.$playlist.withLock { playlist in
      guard row < playlist.count else { return nil }
      return playlist[row]
    }
    guard let item else { return nil }

    if identifier == .isChosen {
      let view = tableView.makeView(withIdentifier: identifier, owner: self) as? PlaylistIsChosenCellView ?? {
        let cell = PlaylistIsChosenCellView()
        cell.identifier = identifier
        return cell
      }()

      let pointer = userInterfaceLayoutDirection == .rightToLeft ?
      Constants.String.blackLeftPointingTriangle :  Constants.String.blackRightPointingTriangle
      view.label.stringValue = item.isPlaying ? pointer : ""
      return view
    } else if identifier == .trackName {
      let view = tableView.makeView(withIdentifier: identifier, owner: self) as? PlaylistTrackCellView ?? {
        let cell = PlaylistTrackCellView()
        cell.identifier = identifier
        return cell
      }()

      view.update(pane: self, player: player, item: item, row: row)
      return view
    }

    return nil
  }

  // Drag and Drop
  
  func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
    if tableView == tableView {
      copyToPasteboard(tableView, writeRowsWith: rowIndexes, to: pboard)
      return true
    }
    return false
  }

  func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
    tableView.setDropRow(row, dropOperation: .above)
    if info.draggingSource as? NSTableView === tableView {
      return .move
    }
    return player.acceptFromPasteboard(info, isPlaylist: true)
  }

  func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
    if info.draggingSource as? NSTableView === tableView,
      let rowData = info.draggingPasteboard.data(forType: .iinaPlaylistItem),
      let indexSet = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSIndexSet.self, from: rowData) as? IndexSet {
      // Drag & drop within playlistTableView
      var oldIndexOffset = 0, newIndexOffset = 0
      for oldIndex in indexSet {
        if oldIndex < row {
          player.playlistMove(oldIndex + oldIndexOffset, to: row)
          oldIndexOffset -= 1
        } else {
          player.playlistMove(oldIndex, to: row + newIndexOffset)
          newIndexOffset += 1
        }
        Logger.log("Playlist Drag & Drop from \(oldIndex) to \(row)", subsystem: player.subsystem)
      }
      player.postNotification(.iinaPlaylistChanged)
      return true
    }
    // Otherwise, could be copy/cut & paste within playlistTableView
    return pasteFromPasteboard(row: row, from: info.draggingPasteboard)
  }

  func copyToPasteboard(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) {
    do {
      let indexesData = try NSKeyedArchiver.archivedData(withRootObject: rowIndexes, requiringSecureCoding: true)
      let filePaths = player.info.$playlist.withLock { playlist in
        rowIndexes.map { playlist[$0].filename }
      }
      pboard.declareTypes([.iinaPlaylistItem, .nsFilenames], owner: tableView)
      pboard.setData(indexesData, forType: .iinaPlaylistItem)
      pboard.setPropertyList(filePaths, forType: .nsFilenames)
    } catch {
      // Internal error, archivedData should not fail.
      Logger.log("Failed to copy from playlist to pasteboard: \(error)", level: .error,
                 subsystem: player.subsystem)
    }
  }

  @discardableResult
  func pasteFromPasteboard(row: Int, from pboard: NSPasteboard) -> Bool {
    if let paths = pboard.propertyList(forType: .nsFilenames) as? [String] {
      let playableFiles = Utility.resolveURLs(player.getPlayableFiles(in: paths.map {
        $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : URL(string: $0)!
      }))
      if playableFiles.count == 0 {
        return false
      }
      player.addToPlaylist(paths: playableFiles.map { $0.isFileURL ? $0.path : $0.absoluteString }, at: row)
    } else if let urls = pboard.propertyList(forType: .nsURL) as? [String] {
      player.addToPlaylist(paths: urls, at: row)
    } else if let droppedString = pboard.string(forType: .string), Regex.url.matches(droppedString) {
      player.addToPlaylist(paths: [droppedString], at: row)
    } else {
      return false
    }
    player.postNotification(.iinaPlaylistChanged)
    return true
  }
}

// MARK: - Context menu

extension SidebarPlaylistPane: NSMenuDelegate, NSMenuItemValidation {
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.tag {
    case MenuItemTagCut, MenuItemTagCopy, MenuItemTagDelete:
      return tableView.selectedRow != -1
    case MenuItemTagPaste:
      return NSPasteboard.general.types?.contains(.nsFilenames) ?? false
    default:
      return menuItem.isEnabled
    }
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    let selectedRow = tableView.selectedRowIndexes
    let clickedRow = tableView.clickedRow
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
    tableView.deselectAll(nil)
    player.postNotification(.iinaPlaylistChanged)
  }

  @IBAction func contextMenuPlayInNewWindow(_ sender: NSMenuItem) {
    let files = {
      self.player.info.$playlist.withLock { playlist in
        self.selectedRows!.enumerated().map { (_, i) in
          URL(fileURLWithPath: playlist[i].filename)
        }}
    }()
    PlayerCore.newPlayerCore.openURLs(files, shouldAutoLoad: false)
  }

  @IBAction func contextMenuRemove(_ sender: NSMenuItem) {
    guard let selectedRows = selectedRows else { return }
    player.playlistRemove(selectedRows)
  }

  @IBAction func contextMenuDeleteFile(_ sender: NSMenuItem) {
    guard let selectedRows = selectedRows else { return }
    Logger.log("User chose to delete files from playlist at indexes: \(selectedRows.map{$0})", subsystem: player.subsystem)

    var successes = IndexSet()
    for index in selectedRows {
      let playlistItem = player.info.$playlist.withLock { $0[index] }
      guard !playlistItem.isNetworkResource else { continue }
      let url = URL(fileURLWithPath: playlistItem.filename)
      do {
        Logger.log("Trashing row \(index): \(url.standardizedFileURL)", subsystem: player.subsystem)
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        successes.insert(index)
      } catch let error {
        Utility.showAlert("playlist.error_deleting", arguments: [error.localizedDescription])
      }
    }
    if !successes.isEmpty {
      player.playlistRemove(successes)
    }
  }

  @IBAction func contextMenuDeleteFileAfterPlayback(_ sender: NSMenuItem) {
    // WIP
  }

  @IBAction func contextMenuShowInFinder(_ sender: NSMenuItem) {
    guard let selectedRows = selectedRows else { return }
    var urls: [URL] = []
    player.info.$playlist.withLock { playlist in
      for index in selectedRows {
        if !playlist[index].isNetworkResource {
          urls.append(URL(fileURLWithPath: playlist[index].filename))
        }
      }
    }
    tableView.deselectAll(nil)
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }

  @IBAction func contextMenuAddSubtitle(_ sender: NSMenuItem) {
    guard let selectedRows = selectedRows, let index = selectedRows.first else { return }
    let filename = player.info.$playlist.withLock { $0[index].filename }
    let fileURL = URL(fileURLWithPath: filename).deletingLastPathComponent()
    Utility.quickMultipleOpenPanel(title: NSLocalizedString("alert.choose_media_file.title", comment: "Choose Media File"), dir: fileURL, canChooseDir: true) { subURLs in
      for subURL in subURLs {
        guard Utility.supportedFileExt[.sub]!.contains(subURL.pathExtension.lowercased()) else { return }
        self.player.info.$matchedSubs.withLock { $0[filename, default: []].append(subURL) }
      }
      self.tableView.reloadData(forRowIndexes: selectedRows, columnIndexes: IndexSet(integersIn: 0...1))
    }
  }

  @IBAction func contextMenuWrongSubtitle(_ sender: NSMenuItem) {
    guard let selectedRows = selectedRows else { return }
    for index in selectedRows {
      let filename = player.info.$playlist.withLock { $0[index].filename }
      player.info.$matchedSubs.withLock { $0[filename]?.removeAll() }
      tableView.reloadData(forRowIndexes: selectedRows, columnIndexes: IndexSet(integersIn: 0...1))
    }
  }

  @IBAction func contextOpenInBrowser(_ sender: NSMenuItem) {
    guard let selectedRows = selectedRows else { return }
    selectedRows.forEach { i in
      let info = player.info.playlist[i]
      if info.isNetworkResource, let url = URL(string: info.filename) {
        NSWorkspace.shared.open(url)
      }
    }
  }

  @IBAction func contextCopyURL(_ sender: NSMenuItem) {
    guard let selectedRows = selectedRows else { return }
    let urls = selectedRows.compactMap { i -> String? in
      let info = player.info.playlist[i]
      return info.isNetworkResource ? info.filename : nil
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([urls.joined(separator: "\n") as NSString])
  }

  private func buildMenu(forRows rows: IndexSet) -> NSMenu {
    let result = NSMenu()
    let isSingleItem = rows.count == 1

    if !rows.isEmpty {
      let matchedSubCount = rows.map { index in
        player.info.$playlist.withLock {
          player.info.getMatchedSubs($0[index].filename)?.count ?? 0
        }
      }.reduce(0, +)
      let title: String = isSingleItem ?
        player.info.$playlist.withLock { $0[rows.first!] }.filenameForDisplay:
        String(format: NSLocalizedString("pl_menu.title_multi", comment: "%d Items"), rows.count)

      result.addItem(withTitle: title)
      result.addItem(NSMenuItem.separator())
      if #available(macOS 14.0, *) {
        result.addItem(.sectionHeader(title: NSLocalizedString("pl_menu.playback", comment: "Playback")))
      }
      result.addItem(withTitle: NSLocalizedString("pl_menu.play_next", comment: "Play Next"), action: #selector(self.contextMenuPlayNext(_:)))
      result.addItem(withTitle: NSLocalizedString("pl_menu.play_in_new_window", comment: "Play in New Window"), action: #selector(self.contextMenuPlayInNewWindow(_:)))
      result.addItem(withTitle: NSLocalizedString(isSingleItem ? "pl_menu.remove" : "pl_menu.remove_multi", comment: "Remove"), action: #selector(self.contextMenuRemove(_:)))

      if !player.isInMiniPlayer && (isSingleItem || matchedSubCount != 0) {
        result.addItem(NSMenuItem.separator())
        if #available(macOS 14.0, *) {
          result.addItem(.sectionHeader(title: String(format: NSLocalizedString("pl_menu.subtitles", comment: "Subtitles (%@ loaded)"), matchedSubCount)))
        } else {
          result.addItem(withTitle: String(format: NSLocalizedString("pl_menu.matched_sub", comment: "Matched %d Subtitle(s)"), matchedSubCount))
        }
        if isSingleItem {
          result.addItem(withTitle: NSLocalizedString("pl_menu.add_sub", comment: "Add Subtitle…"), action: #selector(self.contextMenuAddSubtitle(_:)))
        }
        if matchedSubCount != 0 {
          result.addItem(withTitle: NSLocalizedString("pl_menu.wrong_sub", comment: "Wrong Subtitle"), action: #selector(self.contextMenuWrongSubtitle(_:)))
        }
      }

      result.addItem(NSMenuItem.separator())
      // network resources related operations
      let networkCount = player.info.$playlist.withLock { playlist in
        rows.filter { playlist[$0].isNetworkResource }
      }.count
      if networkCount != 0 {
        if #available(macOS 14.0, *) {
          result.addItem(.sectionHeader(title: NSLocalizedString("pl_menu.network_resources", comment: "Network Resources")))
        }
        result.addItem(withTitle: NSLocalizedString("pl_menu.browser", comment: "Open in Browser"), action: #selector(self.contextOpenInBrowser(_:)))
        result.addItem(withTitle: NSLocalizedString(networkCount == 1 ? "pl_menu.copy_url" : "pl_menu.copy_url_multi", comment: "Copy URL(s)"), action: #selector(self.contextCopyURL(_:)))
        result.addItem(NSMenuItem.separator())
      }
      // file related operations
      let localCount = rows.count - networkCount
      if localCount != 0 {
        if #available(macOS 14.0, *) {
          result.addItem(.sectionHeader(title: NSLocalizedString("pl_menu.file_operations", comment: "File Operations")))
        }
        result.addItem(withTitle: NSLocalizedString(localCount == 1 ? "pl_menu.delete" : "pl_menu.delete_multi", comment: "Delete"), action: #selector(self.contextMenuDeleteFile(_:)))
        // result.addItem(withTitle: NSLocalizedString(isSingleItem ? "pl_menu.delete_after_play" : "pl_menu.delete_after_play_multi", comment: "Delete After Playback"), action: #selector(self.contextMenuDeleteFileAfterPlayback(_:)))

        result.addItem(withTitle: NSLocalizedString("pl_menu.show_in_finder", comment: "Show in Finder"), action: #selector(self.contextMenuShowInFinder(_:)))
        result.addItem(NSMenuItem.separator())
      }
    }

    // menu items from plugins
    var hasPluginMenuItems = false
    let filenames = Array(rows)
    let pluginMenuItems = player.plugins.map {
      plugin -> (JavascriptPluginInstance, [JavascriptPluginMenuItem]) in
      if let builder = (plugin.apis["playlist"] as! JavascriptAPIPlaylist).menuItemBuilder?.value,
        let value = builder.call(withArguments: [filenames]),
        value.isObject,
        let items = value.toObject() as? [JavascriptPluginMenuItem] {
        hasPluginMenuItems = true
        return (plugin, items)
      }
      return (plugin, [])
    }
    if hasPluginMenuItems {
      result.addItem(withTitle: NSLocalizedString("pl_menu.plugin", comment: "Plugin"))
      for (plugin, items) in pluginMenuItems {
        for item in items {
          add(menuItemDef: item, to: result, for: plugin)
        }
      }
      result.addItem(NSMenuItem.separator())
    }

    if #available(macOS 14.0, *) {
      result.addItem(.sectionHeader(title: NSLocalizedString("pl_menu.playlist", comment: "Playlist")))
    }
    result.addItem(withTitle: NSLocalizedString("pl_menu.add_file", comment: "Add File"), action: #selector(self.addFileAction(_:)))
    result.addItem(withTitle: NSLocalizedString("pl_menu.add_url", comment: "Add URL"), action: #selector(self.addURLAction(_:)))
    result.addItem(withTitle: NSLocalizedString("pl_menu.clear_playlist", comment: "Clear Playlist"), action: #selector(self.clearPlaylistBtnAction(_:)))
    return result
  }

  @discardableResult
  private func add(menuItemDef item: JavascriptPluginMenuItem,
                   to menu: NSMenu,
                   for plugin: JavascriptPluginInstance) -> NSMenuItem {
    if (item.isSeparator) {
      let item = NSMenuItem.separator()
      menu.addItem(item)
      return item
    }

    let menuItem: NSMenuItem
    if item.action == nil {
      menuItem = menu.addItem(withTitle: item.title, action: nil, target: plugin, obj: item)
    } else {
      menuItem = menu.addItem(withTitle: item.title,
                              action: #selector(plugin.playlistMenuItemAction(_:)),
                              target: plugin,
                              obj: item)
    }

    menuItem.isEnabled = item.enabled
    menuItem.state = item.selected ? .on : .off
    if !item.items.isEmpty {
      menuItem.submenu = NSMenu()
      for submenuItem in item.items {
        add(menuItemDef: submenuItem, to: menuItem.submenu!, for: plugin)
      }
    }
    return menuItem
  }
}


class PlaylistIsChosenCellView: NSTableCellView {
  let label: NSTextField

  override init(frame frameRect: NSRect) {
    self.label = NSTextField(labelWithString: "")
    label.translatesAutoresizingMaskIntoConstraints = false
    super.init(frame: frameRect)
    addSubview(label)
    label.padding(.horizontal(2)).center(.y)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}


class PlaylistTrackCellView: NSTableCellView {
  private var stackView: NSStackView!
  private var prefixBtn: PlaylistPrefixButton!
  private var trackNameLabel: NSTextField!
  private var infoLabel: NSTextField!
  private var durationLabel: NSTextField!
  private var playbackProgressView: PlaylistPlaybackProgressView!

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    self.prefixBtn = PlaylistPrefixButton()
    self.trackNameLabel = ui.label("")
    trackNameLabel.lineBreakMode = .byTruncatingMiddle
    trackNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    self.infoLabel = ui.label("", font: .boldSystemFont(ofSize: 11), isSecondary: true)
    self.durationLabel = ui.label("", isSmall: true, isSecondary: true)
    self.stackView = ui.hStack(
      spacing: 4,
      prefixBtn,
      trackNameLabel,
      ui.flexibleSpace(),
      infoLabel,
      durationLabel,
    )
    stackView.setCustomSpacing(0, after: prefixBtn)

    addSubview(stackView)
    stackView.padding(.horizontal(2), .vertical)

    self.playbackProgressView = PlaylistPlaybackProgressView()
    playbackProgressView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(playbackProgressView)
    playbackProgressView.padding(.horizontal, .bottom).size(height: 4)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setPrefix(_ prefix: String?) {
    if let prefix = prefix {
      stackView.setVisibilityPriority(.mustHold, for: prefixBtn)
      prefixBtn.text = prefix
    } else {
      stackView.setVisibilityPriority(.notVisible, for: prefixBtn)
    }
  }

  private func setAdditionalInfo(_ string: String?) {
    if let string = string {
      stackView.setVisibilityPriority(.mustHold, for: infoLabel)
      infoLabel.stringValue = string
      infoLabel.toolTip = string
    } else {
      stackView.setVisibilityPriority(.notVisible, for: infoLabel)
      infoLabel.stringValue = ""
    }
  }

  private func setTitle(_ title: String) {
    trackNameLabel.stringValue = title
    trackNameLabel.toolTip = title
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    playbackProgressView.percentage = 0
    playbackProgressView.needsDisplay = true
    setPrefix(nil)
    setAdditionalInfo(nil)
  }

  func update(pane: SidebarPlaylistPane, player: PlayerCore, item: MPVPlaylistItem, row: Int) {
    // file name
    let filename = item.filenameForDisplay
    let displayStr: String = NSString(string: filename).deletingPathExtension

    func getCachedMetadata() -> (artist: String, title: String)? {
      guard Preference.bool(for: .playlistShowMetadata) else { return nil }
      if Preference.bool(for: .playlistShowMetadataInMusicMode) && !player.isInMiniPlayer {
        return nil
      }
      guard let metadata = player.info.getCachedMetadata(item.filename) else { return nil }
      guard let artist = metadata.artist, let title = metadata.title else { return nil }
      return (artist, title)
    }

    if let prefix = player.info.currentVideosInfo.first(where: { $0.path == item.filename })?.prefix,
       !prefix.isEmpty,
       prefix.count <= displayStr.count,  // check whether prefix length > filename length
       prefix.count >= PrefixMinLength,
       filename.count > FilenameMinLength {
      setPrefix(prefix)
      setTitle(String(filename[filename.index(filename.startIndex, offsetBy: prefix.count)...]))
    } else {
      setPrefix(nil)
      setTitle(filename)
    }
    // playback progress and duration
    durationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    durationLabel.stringValue = ""
    player.playlistQueue.async { [weak self] in
      guard let self else { return }
      if let (artist, title) = getCachedMetadata() {
        DispatchQueue.main.async {
          self.setTitle(title)
          self.setAdditionalInfo(artist)
        }
      }
      if let cached = player.info.getCachedVideoDurationAndProgress(item.filename),
         let duration = cached.duration {
        // if it's cached
        if duration > 0 {
          // if FFmpeg got the duration successfully
          DispatchQueue.main.async {
            self.durationLabel.stringValue = VideoTime(duration).stringRepresentation
            if let progress = cached.progress {
              self.playbackProgressView.percentage = progress / duration
              self.playbackProgressView.needsDisplay = true
            }
          }
          pane.refreshTotalLength()
        }
      } else {
        // get related data and schedule a reload
        if Preference.bool(for: .prefetchPlaylistVideoDuration) {
          player.refreshCachedVideoInfo(forVideoPath: item.filename)
          // Only schedule a reload if data was obtained and cached to avoid looping
          if let cached = player.info.getCachedVideoDurationAndProgress(item.filename),
             let duration = cached.duration, duration > 0 {
            // if FFmpeg got the duration successfully
            pane.refreshTotalLength()
            DispatchQueue.main.async {
              pane.tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0...1))
            }
          }
        }
      }
    }
  }
}


class PlaylistPrefixButton: NSButton {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    bezelStyle = .smallSquare
    isBordered = false
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  var text = "" {
    didSet {
      refresh()
    }
  }

  var isFolded = true {
    didSet {
      refresh()
    }
  }

  override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
    isFolded = !isFolded
    return true
  }

  private func refresh() {
    self.title = isFolded ? "…" : text
  }
}
