//
//  InspectorWindowController.swift
//  iina
//
//  Created by lhc on 21/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate let watchTableBackgroundColor = NSColor(red: 2.0/3, green: 2.0/3, blue: 2.0/3, alpha: 0.1)
fileprivate let watchTableColumnHeaderColor = NSColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)

class InspectorWindowController: NSWindowController, NSWindowDelegate, NSTableViewDelegate, NSTableViewDataSource {

  override var windowNibName: NSNib.Name {
    return NSNib.Name("InspectorWindowController")
  }

  var updateTimer: Timer?

  var watchProperties: [String] = []

  @IBOutlet weak var tabView: NSTabView!
  @IBOutlet weak var tabButtonGroup: NSSegmentedControl!
  @IBOutlet weak var trackPopup: NSPopUpButton!

  @IBOutlet weak var pathField: NSTextField!
  @IBOutlet weak var fileSizeField: NSTextField!
  @IBOutlet weak var fileFormatField: NSTextField!
  @IBOutlet weak var chaptersField: NSTextField!
  @IBOutlet weak var editionsField: NSTextField!

  @IBOutlet weak var durationField: NSTextField!
  @IBOutlet weak var vformatField: NSTextField!
  @IBOutlet weak var vcodecField: NSTextField!
  @IBOutlet weak var vdecoderField: NSTextField!
  @IBOutlet weak var vcolorspaceField: NSTextField!
  @IBOutlet weak var vprimariesField: NSTextField!
  @IBOutlet weak var vPixelFormat: NSTextField!

  @IBOutlet weak var voField: NSTextField!
  @IBOutlet weak var vsizeField: NSTextField!
  @IBOutlet weak var vbitrateField: NSTextField!
  @IBOutlet weak var vfpsField: NSTextField!
  @IBOutlet weak var aformatField: NSTextField!
  @IBOutlet weak var acodecField: NSTextField!
  @IBOutlet weak var aoField: NSTextField!
  @IBOutlet weak var achannelsField: NSTextField!
  @IBOutlet weak var abitrateField: NSTextField!
  @IBOutlet weak var asamplerateField: NSTextField!

  @IBOutlet weak var trackIdField: NSTextField!
  @IBOutlet weak var trackDefaultField: NSTextField!
  @IBOutlet weak var trackForcedField: NSTextField!
  @IBOutlet weak var trackSelectedField: NSTextField!
  @IBOutlet weak var trackExternalField: NSTextField!
  @IBOutlet weak var trackSourceIdField: NSTextField!
  @IBOutlet weak var trackTitleField: NSTextField!
  @IBOutlet weak var trackLangField: NSTextField!
  @IBOutlet weak var trackFilePathField: NSTextField!
  @IBOutlet weak var trackCodecField: NSTextField!
  @IBOutlet weak var trackDecoderField: NSTextField!
  @IBOutlet weak var trackFPSField: NSTextField!
  @IBOutlet weak var trackChannelsField: NSTextField!
  @IBOutlet weak var trackSampleRateField: NSTextField!

  @IBOutlet weak var avsyncField: NSTextField!
  @IBOutlet weak var totalAvsyncField: NSTextField!
  @IBOutlet weak var droppedFramesField: NSTextField!
  @IBOutlet weak var mistimedFramesField: NSTextField!
  @IBOutlet weak var displayFPSField: NSTextField!
  @IBOutlet weak var voFPSField: NSTextField!
  @IBOutlet weak var edispFPSField: NSTextField!
  @IBOutlet weak var watchTableView: NSTableView!
  @IBOutlet weak var deleteButton: NSButton!

  @IBOutlet weak var watchTableContainerView: NSView!
  private var tableHeightConstraint: NSLayoutConstraint? = nil

  override func windowDidLoad() {
    super.windowDidLoad()

    watchProperties = Preference.array(for: .watchProperties) as! [String]
    watchTableView.delegate = self
    watchTableView.dataSource = self

    let headerFont = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
    for column in watchTableView.tableColumns {
      let headerCell = WatchTableColumnHeaderCell()
      // Use title from the XIB
      let title = column.headerCell.title
      // Use small bold system font
      headerCell.attributedStringValue = NSMutableAttributedString(string: title, attributes: [.font: headerFont])
      column.headerCell = headerCell
    }

    watchTableContainerView.wantsLayer = true
    watchTableContainerView.layer?.backgroundColor = watchTableBackgroundColor.cgColor

    tableHeightConstraint = watchTableContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: computeMinTableHeight())
    tableHeightConstraint!.isActive = true
    watchTableContainerView.layout()

    deleteButton.isEnabled = false

    if #available(macOS 10.14, *) {} else {
      window?.appearance = NSAppearance(named: .vibrantDark)
    }

    updateInfo()
    watchTableView.scrollRowToVisible(0)

    updateTimer = Timer.scheduledTimer(timeInterval: TimeInterval(1), target: self, selector: #selector(dynamicUpdate), userInfo: nil, repeats: true)

    NotificationCenter.default.addObserver(self, selector: #selector(fileLoaded), name: .iinaFileLoaded, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(fileLoaded), name: .iinaMainWindowChanged, object: nil)
  }

  /// Workaround (as of MacOS 13.4): try to ensure `watchTableView` never scrolls vertically, because `NSTableView` will draw rows
  /// overlapping the header (maybe only a problem for custom `NSTableHeaderCell`s which are not opaque), but looks quite ugly.
  private func computeMinTableHeight() -> CGFloat {
    /// Add `1` to `numberOfRows` because it will scroll if there is not at least 1 empty row
    return watchTableView.headerView!.frame.height + CGFloat(
      watchTableView.numberOfRows + 1) * (watchTableView.rowHeight + watchTableView.intercellSpacing.height)
  }

  deinit {
    ObjcUtils.silenced {
      NotificationCenter.default.removeObserver(self)
    }
  }

  func updateInfo(dynamic: Bool = false) {
    let player = PlayerCore.lastActive
    guard !player.isStopping, !player.isStopped, !player.isShuttingDown, !player.isShutdown else { return }
    let controller = player.mpv!
    let info = player.info

    DispatchQueue.main.async {

      if !dynamic {

        // string properties

        let strProperties: [String: NSTextField] = [
          MPVProperty.path: self.pathField,
          MPVProperty.fileFormat: self.fileFormatField,
          MPVProperty.chapters: self.chaptersField,
          MPVProperty.editions: self.editionsField,

          MPVProperty.videoFormat: self.vformatField,
          MPVProperty.videoCodec: self.vcodecField,
          MPVProperty.hwdecCurrent: self.vdecoderField,
          MPVProperty.containerFps: self.vfpsField,
          MPVProperty.currentVo: self.voField,
          MPVProperty.audioCodec: self.acodecField,
          MPVProperty.currentAo: self.aoField,
          MPVProperty.audioParamsFormat: self.aformatField,
          MPVProperty.audioParamsChannels: self.achannelsField,
          MPVProperty.audioBitrate: self.abitrateField,
          MPVProperty.audioParamsSamplerate: self.asamplerateField
        ]

        for (k, v) in strProperties {
          var value = controller.getString(k)
          if value == "" { value = nil }
          v.stringValue = value ?? "N/A"
          self.setLabelColor(v, by: value != nil)
        }

        // other properties

        let duration = controller.getDouble(MPVProperty.duration)
        self.durationField.stringValue = VideoTime(duration).stringRepresentation

        let vwidth = controller.getInt(MPVProperty.width)
        let vheight = controller.getInt(MPVProperty.height)
        self.vsizeField.stringValue = "\(vwidth)\u{d7}\(vheight)"

        let fileSize = controller.getInt(MPVProperty.fileSize)
        self.fileSizeField.stringValue = "\(FloatingPointByteCountFormatter.string(fromByteCount: fileSize))B"

        // track list

        self.trackPopup.removeAllItems()
        var needSeparator = false
        for track in info.videoTracks {
          self.trackPopup.menu?.addItem(withTitle: "Video" + track.readableTitle,
                                   action: nil, tag: nil, obj: track, stateOn: false)
          needSeparator = true
        }
        if needSeparator && !info.audioTracks.isEmpty {
          self.trackPopup.menu?.addItem(NSMenuItem.separator())
        }
        for track in info.audioTracks {
          self.trackPopup.menu?.addItem(withTitle: "Audio" + track.readableTitle,
                                   action: nil, tag: nil, obj: track, stateOn: false)
          needSeparator = true
        }
        if needSeparator && !info.subTracks.isEmpty {
          self.trackPopup.menu?.addItem(NSMenuItem.separator())
        }
        for track in info.subTracks {
          self.trackPopup.menu?.addItem(withTitle: "Subtitle" + track.readableTitle,
                                   action: nil, tag: nil, obj: track, stateOn: false)
        }
        self.trackPopup.selectItem(at: 0)
        self.updateTrack()
      }

      let vbitrate = controller.getInt(MPVProperty.videoBitrate)
      self.vbitrateField.stringValue = FloatingPointByteCountFormatter.string(fromByteCount: vbitrate) + "bps"

      let abitrate = controller.getInt(MPVProperty.audioBitrate)
      self.abitrateField.stringValue = FloatingPointByteCountFormatter.string(fromByteCount: abitrate) + "bps"

      let dynamicStrProperties: [String: NSTextField] = [
        MPVProperty.avsync: self.avsyncField,
        MPVProperty.totalAvsyncChange: self.totalAvsyncField,
        MPVProperty.frameDropCount: self.droppedFramesField,
        MPVProperty.mistimedFrameCount: self.mistimedFramesField,
        MPVProperty.displayFps: self.displayFPSField,
        MPVProperty.estimatedVfFps: self.voFPSField,
        MPVProperty.estimatedDisplayFps: self.edispFPSField
      ]

      for (k, v) in dynamicStrProperties {
        let value = controller.getString(k)
        v.stringValue = value ?? "N/A"
        self.setLabelColor(v, by: value != nil)
      }

      let sigPeak = controller.getDouble(MPVProperty.videoParamsSigPeak);
      self.vprimariesField.stringValue = sigPeak > 0
        ? "\(controller.getString(MPVProperty.videoParamsPrimaries) ?? "?") / \(controller.getString(MPVProperty.videoParamsGamma) ?? "?") (\(sigPeak > 1 ? "H" : "S")DR)"
        : "N/A";
      self.setLabelColor(self.vprimariesField, by: sigPeak > 0)

      if PlayerCore.lastActive.mainWindow.loaded && controller.fileLoaded {
        if #available(macOS 10.15, *), let colorspace = PlayerCore.lastActive.mainWindow.videoView.videoLayer.colorspace {
          let isHdr = colorspace != VideoView.SRGB
          self.vcolorspaceField.stringValue = "\(colorspace.name!) (\(isHdr ? "H" : "S")DR)"
        } else {
          self.vcolorspaceField.stringValue = "Unspecified (SDR)"
        }
      } else {
        self.vcolorspaceField.stringValue = "N/A"
      }
      self.setLabelColor(self.vcolorspaceField, by: controller.fileLoaded)

      if PlayerCore.lastActive.mainWindow.loaded && controller.fileLoaded {
        if let hwPf = controller.getString(MPVProperty.videoParamsHwPixelformat) {
          self.vPixelFormat.stringValue = "\(hwPf) (HW)"
        } else if let swPf = controller.getString(MPVProperty.videoParamsPixelformat) {
          self.vPixelFormat.stringValue = "\(swPf) (SW)"
        } else {
          self.vPixelFormat.stringValue = "N/A"
        }
      }
      self.setLabelColor(self.vPixelFormat, by: controller.fileLoaded)
    }
  }

  @objc func fileLoaded() {
    updateInfo()
  }

  @objc func dynamicUpdate() {
    updateInfo(dynamic: true)
    /// Do not call `reloadData()` (no arg version) because it will clear the selection. Also, because we know the number of rows will not change,
    /// calling `reloadData(forRowIndexes:)` will get the same result but much more efficiently
    watchTableView.reloadData(forRowIndexes: IndexSet(0..<watchTableView.numberOfRows), columnIndexes: IndexSet(0..<watchTableView.numberOfColumns))
  }

  func updateTrack() {
    guard let track = trackPopup.selectedItem?.representedObject as? MPVTrack else { return }

    trackIdField.stringValue = "\(track.id)"
    setLabelColor(trackDefaultField, by: track.isDefault)
    setLabelColor(trackForcedField, by: track.isForced)
    setLabelColor(trackSelectedField, by: track.isSelected)
    setLabelColor(trackExternalField, by: track.isExternal)

    let strProperties: [(String?, NSTextField)] = [
      (track.srcId?.description, trackSourceIdField),
      (track.title, trackTitleField),
      (track.lang, trackLangField),
      (track.externalFilename, trackFilePathField),
      (track.codec, trackCodecField),
      (track.decoderDesc, trackDecoderField),
      (track.demuxFps?.description, trackFPSField),
      (track.demuxChannels, trackChannelsField),
      (track.demuxSamplerate?.description, trackSampleRateField)
    ]

    for (str, field) in strProperties {
      field.stringValue = str ?? "N/A"
      setLabelColor(field, by: str != nil)
    }
  }

  // MARK: NSTableView

  func numberOfRows(in tableView: NSTableView) -> Int {
    return watchProperties.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let identifier = tableColumn?.identifier else { return nil }
    guard let cell = watchTableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView else {
      return nil
    }
    guard let property = watchProperties[at: row] else { return nil }

    switch identifier {
    case .key:
      if let textField = cell.textField {
        textField.stringValue =  property
      }
      return cell
    case .value:
      let player = PlayerCore.lastActive

      if let textField = cell.textField {
        if !player.isStopping, !player.isStopped, !player.isShuttingDown, !player.isShutdown,
            let value = PlayerCore.lastActive.mpv.getString(property) {
          textField.stringValue = value
          textField.textColor = .controlTextColor
        } else {
          let errorString = NSLocalizedString("inspector.error", comment: "Error")

          let italicDescriptor: NSFontDescriptor = textField.font!.fontDescriptor.withSymbolicTraits(NSFontDescriptor.SymbolicTraits.italic)
          let errorFont = NSFont(descriptor: italicDescriptor, size: textField.font!.pointSize)

          textField.attributedStringValue = NSMutableAttributedString(string: errorString, attributes: [.font: errorFont!])
          textField.textColor = .disabledControlTextColor
        }
      }
      return cell
    default:
      Logger.log("Unrecognized column: '\(identifier.rawValue)'", level: .error)
      return nil
    }
  }

  func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
    /// The background color for a `NSTableRowView` will default to the parent's background color, which results in an
    /// unwanted additive effect for translucent backgrounds. Just make each row transparent.
    rowView.backgroundColor = .clear
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    deleteButton.isEnabled = !watchTableView.selectedRowIndexes.isEmpty
  }

  func resizeTableColumns(forTableWidth tableWidth: CGFloat) {
    guard let keyColumn = watchTableView.tableColumn(withIdentifier: .key),
          let valueColumn = watchTableView.tableColumn(withIdentifier: .value),
          let tableScrollView = watchTableView.enclosingScrollView else {
      return
    }

    let adjustedTableWidth = tableWidth - tableScrollView.verticalScroller!.frame.width
    let keyColumnMaxWidth = adjustedTableWidth - valueColumn.minWidth
    var newKeyColumnWidth = keyColumn.width
    if keyColumn.width > keyColumnMaxWidth {
      newKeyColumnWidth = keyColumnMaxWidth
      keyColumn.width = newKeyColumnWidth
    }
    valueColumn.width = adjustedTableWidth - newKeyColumnWidth
    tableScrollView.needsLayout = true
    tableScrollView.needsDisplay = true
  }

  func windowWillResize(_ sender: NSWindow, to newWindowSize: NSSize) -> NSSize {
    if let window = window, window.inLiveResize {
      /// Table size will change with window size, so need to find the new table width from `newWindowSize`.
      /// We know that our window's width is composed of 2 things: the table width + all other fixed "non-table" stuff.
      /// We first find the non-table width by subtracting current table size from current window size.
      /// Note: `NSTableView` does not give an honest answer for its width, but can use its parent (`NSClipView`) width.
      let oldTableWidth = watchTableView.superview!.frame.width
      let nonTableWidth = window.frame.width - oldTableWidth
      let newTableWidth = newWindowSize.width - nonTableWidth
      resizeTableColumns(forTableWidth: newTableWidth)
    }

    return newWindowSize
  }

  func windowDidResize(_ notification: Notification) {
    if let window = window, window.inLiveResize {
      let tableWidth = watchTableView.superview!.frame.width
      resizeTableColumns(forTableWidth: tableWidth)
    }
  }

  @IBAction func addWatchAction(_ sender: AnyObject) {
    Utility.quickPromptPanel("add_watch", sheetWindow: window) { [self] str in
      self.watchProperties.append(str)
      self.saveWatchList()

      // Append row to end of table, with animation if preferred
      let insertIndexSet = IndexSet(integer: watchTableView.numberOfRows)
      watchTableView.insertRows(at: insertIndexSet, withAnimation: AccessibilityPreferences.motionReductionEnabled ? [] : .slideDown)
      watchTableView.selectRowIndexes(insertIndexSet, byExtendingSelection: false)
      tableHeightConstraint?.constant = computeMinTableHeight()
      watchTableContainerView.layout()
    }
  }

  @IBAction func removeWatchAction(_ sender: AnyObject) {
    let rowIndexes = watchTableView.selectedRowIndexes
    guard !rowIndexes.isEmpty else { return }

    let watchPropertiesOld = watchProperties
    var watchPropertiesNew: [String] = []
    for (index, property) in watchPropertiesOld.enumerated() {
      if !rowIndexes.contains(index) {
        watchPropertiesNew.append(property)
      }
    }
    watchProperties = watchPropertiesNew
    saveWatchList()

    watchTableView.removeRows(at: rowIndexes, withAnimation: AccessibilityPreferences.motionReductionEnabled ? [] : .slideUp)
    tableHeightConstraint?.constant = computeMinTableHeight()
    watchTableContainerView.layout()
  }


  // MARK: IBActions

  @IBAction func tabSwitched(_ sender: NSSegmentedControl) {
    tabView.selectTabViewItem(at: sender.selectedSegment)
  }

  @IBAction func trackSwitched(_ sender: AnyObject) {
    updateTrack()
  }


  // MARK: Utils

  private func setLabelColor(_ label: NSTextField, by state: Bool) {
    label.textColor = state ? NSColor.textColor : NSColor.disabledControlTextColor
  }

  private func saveWatchList() {
    Preference.set(watchProperties, for: .watchProperties)
  }

  class WatchTableColumnHeaderCell: NSTableHeaderCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
      // Override background color
      self.drawsBackground = false
      watchTableColumnHeaderColor.set()
      cellFrame.fill(using: .sourceOver)

      super.draw(withFrame: cellFrame, in: controlView)
    }
  }
}
