//
//  SidebarTrackSelector.swift
//  iina
//
//  Created by Hechen Li on 2026-06-14.
//  Copyright © 2026 lhc. All rights reserved.
//

fileprivate extension NSUserInterfaceItemIdentifier {
//  static let selected = NSUserInterfaceItemIdentifier("selected")
//  static let trackName = NSUserInterfaceItemIdentifier("trackName")
}

class TrackSelector: NSScrollView, NSTableViewDelegate, NSTableViewDataSource {
  private let trackType: MPVTrack.TrackType
  private unowned let player: PlayerCore

  private var tableView: NSTableView

  init(_ trackType: MPVTrack.TrackType, player: PlayerCore, observedKeys: [Notification.Name]) {
    self.player = player
    self.trackType = trackType
    self.tableView = NSTableView()
    super.init(frame: .zero)

    tableView.delegate = self
    tableView.dataSource = self
    tableView.style = .plain

    tableView.addTableColumn(NSTableColumn(identifier: .trackName))
    tableView.headerView = nil
    tableView.backgroundColor = .clear

    translatesAutoresizingMaskIntoConstraints = false
    documentView = tableView
    drawsBackground = false
    size(height: 75)

    player.observe(.iinaTracklistChanged) { [weak self] _ in
      self?.tableView.reloadData()
    }
    for key in observedKeys {
      player.observe(key) { [weak self] _ in
        self?.tableView.reloadData()
      }
    }
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  func numberOfRows(in tableView: NSTableView) -> Int {
    return player.info.trackList(trackType).count + 1
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    return 22
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let trackList = player.info.trackList(trackType)
    guard let column = tableColumn, row <= trackList.count else { return nil }

    let track = row == 0 ? nil : trackList[at: row - 1]
    let selectedTrack = player.info.currentTrack(trackType)

    let columnID = column.identifier
    let identifier = NSUserInterfaceItemIdentifier("\(columnID.rawValue)Cell")

    let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? CellView
      ?? makeCell(identifier: identifier, columnID: columnID)
    let isChosen = track == selectedTrack
    switch columnID {
    case .trackName:
      cell.textField?.textColor = row == 0 ? .secondaryLabelColor : .labelColor
      cell.textField?.stringValue = track?.infoString ?? Constants.String.trackNone
      cell.selectedIndicator.isHidden = !isChosen
    default:
      break
    }
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard tableView.numberOfSelectedRows > 0 else { return }
    let trackId = if tableView.selectedRow > 0 {
      player.info.trackList(trackType)[tableView.selectedRow-1].id
    } else {
      0
    }
    player.setTrack(trackId, forType: trackType)
    tableView.deselectAll(nil)
  }

  private func makeCell(identifier: NSUserInterfaceItemIdentifier, columnID: NSUserInterfaceItemIdentifier) -> CellView {
    let cell = CellView()
    cell.identifier = identifier
    return cell
  }

  private class CellView: NSTableCellView {
    var selectedIndicator: NSView

    override init(frame frameRect: NSRect) {
      self.selectedIndicator = NSView()
      selectedIndicator.translatesAutoresizingMaskIntoConstraints = false
      super.init(frame: frameRect)

      let textField = NSTextField(wrappingLabelWithString: "")
      textField.isSelectable = false
      textField.translatesAutoresizingMaskIntoConstraints = false
      addSubview(textField)
      textField.padding(.leading(12), .trailing, .vertical(2))
      self.textField = textField

      selectedIndicator.wantsLayer = true
      if let layer = selectedIndicator.layer {
        layer.backgroundColor = NSColor.controlAccentColor.cgColor
        layer.cornerRadius = 2
      }
      addSubview(selectedIndicator)
      selectedIndicator.padding(.leading, .vertical(2))
        .size(width: 4)
    }
    
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }
}

