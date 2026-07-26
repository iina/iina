//
//  SidebarChaptersPane.swift
//  iina
//
//  Created by Hechen Li on 2026-06-19.
//  Copyright © 2026 lhc. All rights reserved.
//

fileprivate let ui = UIHelper.shared


class SidebarChaptersPane: NSView, SidebarPane {
  let prefObserver = Preference.Observer()
  weak var player: PlayerCore!

  private var scrollView: NSScrollView!
  private var tableView: NSTableView!

  var horizontalScroll: ((Bool) -> Void)?

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    self.scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false

    self.tableView = NSTableView()
    tableView.style = .fullWidth
    tableView.intercellSpacing = .init(width: 4, height: 2)
    tableView.allowsColumnResizing = false
    tableView.selectionHighlightStyle = .none
    tableView.rowHeight = 40
    tableView.delegate = self
    tableView.dataSource = self
    tableView.target = self
    tableView.delegate = self
    tableView.doubleAction = #selector(doubleAction)
    tableView.headerView = nil
    tableView.backgroundColor = .sidebarTableBackground
    tableView.gridStyleMask = [.solidHorizontalGridLineMask]

    let isChosenColumn = NSTableColumn(identifier: .isChosen)
    isChosenColumn.width = 16
    tableView.addTableColumn(isChosenColumn)
    tableView.addTableColumn(NSTableColumn(identifier: .trackName))

    scrollView.documentView = tableView
    addSubview(scrollView)
    scrollView.padding(.all)

    player.observe(.iinaChapterListChanged) { [unowned self] _ in
      tableView.reloadData()
    }
  }

  @objc func doubleAction(_ sender: AnyObject) {
    let index = tableView.selectedRow
    player.playChapter(index)
    tableView.deselectAll(self)
    tableView.reloadData()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}


extension SidebarChaptersPane: NSTableViewDelegate, NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    return player.info.chapters.count
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    40
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let identifier = tableColumn?.identifier else { return nil }
    let chapters = player.info.chapters
    guard row < chapters.count else {
      return nil
    }

    let chapter = chapters[row]
    let nextChapterTime = chapters[at: row+1]?.time ?? .infinite

    if identifier == .isChosen {
      let isPlaying = player.info.chapter == row
      let view = tableView.makeView(withIdentifier: identifier, owner: self) as? PlaylistIsChosenCellView ?? {
        let cell = PlaylistIsChosenCellView()
        cell.identifier = identifier
        return cell
      }()

      let pointer = userInterfaceLayoutDirection == .rightToLeft ?
      Constants.String.blackLeftPointingTriangle :  Constants.String.blackRightPointingTriangle
      view.label.stringValue = isPlaying ? pointer : ""
      return view
    } else if identifier == .trackName {
      let view = tableView.makeView(withIdentifier: identifier, owner: self) as? ChapterTableCellView ?? {
        let cell = ChapterTableCellView()
        cell.identifier = identifier
        return cell
      }()

      view.update(chapter: chapter, nextChapterTime: nextChapterTime, row: row)
      return view
    }
    return nil
  }
}


class ChapterTableCellView: NSTableCellView {
  private var titleTextField: NSTextField!
  private var durationTextField: NSTextField!

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    titleTextField = ui.label("")
    durationTextField = ui.label("", isSmall: true, isSecondary: true)

    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(titleTextField)
    container.addSubview(durationTextField)
    addSubview(container)

    titleTextField.padding(.top, .horizontal)
      .spacing(.bottom, to: durationTextField)
    durationTextField.padding(.bottom, .horizontal)
    container.padding(.horizontal).center(.y)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  func update(chapter: MPVChapter, nextChapterTime: VideoTime, row: Int) {
    let title = chapter.title.isEmpty ? "Chapter \(row)" : chapter.title
    titleTextField.stringValue = title
    titleTextField.toolTip = title
    durationTextField.stringValue = "\(chapter.time.stringRepresentation) → \(nextChapterTime.stringRepresentation)"
  }
}
