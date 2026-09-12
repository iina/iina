//
//  SidebarTrackSelector.swift
//  iina
//
//  Created by Hechen Li on 2026-06-14.
//  Copyright © 2026 lhc. All rights reserved.
//

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
    tableView.gridStyleMask = [.solidHorizontalGridLineMask]

    translatesAutoresizingMaskIntoConstraints = false
    documentView = tableView
    drawsBackground = false
    wantsLayer = true
    layer?.cornerRadius = 8
    size(height: 98)

    player.observe(.iinaTracklistChanged) { [weak self] _ in
      self?.tableView.reloadData()
    }
    for key in observedKeys {
      player.observe(key) { [weak self] _ in
        self?.tableView.reloadData()
      }
    }
  }

  private enum ScrollGestureState {
    case idle
    case trackingTouch
    case trackingMomentumCandidate(touchEndedTimestamp: TimeInterval)
  }

  private var scrollGestureState = ScrollGestureState.idle

  override func scrollWheel(with event: NSEvent) {
    // If the content is small enough to fit in the view, it doesn't need to scroll.
    // In this case, strictly forward ALL scroll events to the parent (the sidebar)
    // so it doesn't trap the cursor and cause "focus stealing".
    if let documentView = documentView, documentView.bounds.height <= contentView.bounds.height {
      nextResponder?.scrollWheel(with: event)
      return
    }

    // Ensure gestures that started outside this view (e.g. over the parent sidebar)
    // are not trapped when this view scrolls under the cursor mid-gesture.
    if event.hasPreciseScrollingDeltas && (event.phase != [] || event.momentumPhase != []) {
      if event.phase == .mayBegin || event.phase == .began {
        scrollGestureState = .trackingTouch
      } else if event.phase == .changed {
        if case .trackingTouch = scrollGestureState {
          // Continue handling the gesture that began over this view.
        } else {
          scrollGestureState = .idle
        }
      } else if event.phase == .ended || event.phase == .cancelled {
        if case .idle = scrollGestureState {
          // Keep forwarding gestures that began outside this view.
        } else {
          scrollGestureState = .trackingMomentumCandidate(touchEndedTimestamp: event.timestamp)
        }
      } else if event.momentumPhase == .began {
        if case let .trackingMomentumCandidate(touchEndedTimestamp) = scrollGestureState,
           event.timestamp - touchEndedTimestamp < 0.1 {
          // Treat promptly following momentum as part of the tracked gesture.
        } else {
          scrollGestureState = .idle
        }
      } else if event.momentumPhase == .ended || event.momentumPhase == .cancelled {
        scrollGestureState = .idle
      }

      if case .idle = scrollGestureState {
        nextResponder?.scrollWheel(with: event)
        return
      }
    }

    super.scrollWheel(with: event)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  func numberOfRows(in tableView: NSTableView) -> Int {
    return player.info.trackList(trackType).count + 1
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    return 26
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let trackList = player.info.trackList(trackType)
    guard let column = tableColumn, row <= trackList.count else { return nil }

    let track = row == 0 ? nil : trackList[at: row - 1]
    let selectedTrack = player.info.currentTrack(trackType)

    let columnID = column.identifier
    let identifier = NSUserInterfaceItemIdentifier("\(columnID.rawValue)Cell")

    let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? CellView ?? {
      let cell = CellView()
      cell.identifier = identifier
      return cell
    }()
    let isChosen = track == selectedTrack
    switch columnID {
    case .trackName:
      cell.textField?.textColor = row == 0 ? .secondaryLabelColor : .labelColor
      cell.textField?.stringValue = track?.readableString(includingLanguage: false) ?? Constants.String.trackNone
      cell.selectedIndicator.isHidden = !isChosen
      cell.setLanguage(track?.readableLanguage)
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
    var selectedIndicator: ColoredView
    var languageTag: ColoredView
    var languageLabel: NSTextField

    override init(frame frameRect: NSRect) {
      self.selectedIndicator = ColoredView(color: .controlAccentColor, cornerRadius: 2)
      selectedIndicator.translatesAutoresizingMaskIntoConstraints = false

      self.languageTag = ColoredView(color: .controlColor, cornerRadius: 3)
      languageTag.translatesAutoresizingMaskIntoConstraints = false

      self.languageLabel = NSTextField(labelWithString: "")
      languageLabel.translatesAutoresizingMaskIntoConstraints = false

      super.init(frame: frameRect)

      let textField = NSTextField(labelWithString: "")
      textField.isSelectable = false
      textField.translatesAutoresizingMaskIntoConstraints = false
      textField.lineBreakMode = .byTruncatingMiddle
      textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      addSubview(textField)
      textField.padding(.leading(12)).center(.y)
      self.textField = textField

      addSubview(selectedIndicator)
      selectedIndicator.padding(.leading, .vertical(5))
        .size(width: 4)

      languageLabel.font = .systemFont(ofSize: 11)

      languageTag.addSubview(languageLabel)
      languageLabel.padding(.vertical(1), .horizontal(2))

      addSubview(languageTag)
      languageTag.padding(.trailing)
        .spacing(.leading(greaterThan: 4), to: textField)
        .center(.y)
    }

    func setLanguage(_ language: String?) {
      if let language, !language.isEmpty {
        languageTag.isHidden = false
        languageLabel.stringValue = language
      } else {
        languageTag.isHidden = true
      }
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }
}

class ColoredView: NSView {
  let color: NSColor
  let cornerRadius: CGFloat

  init(color: NSColor, cornerRadius: CGFloat = 0) {
    self.color = color
    self.cornerRadius = cornerRadius
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func draw(_ dirtyRect: NSRect) {
    color.setFill()
    NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
  }
}
