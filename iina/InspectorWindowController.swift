//
//  InspectorWindowController.swift
//  iina
//
//  Created by lhc on 21/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate let topPadding: ALConstraint = .top(15)
fileprivate let bottomPadding: ALConstraint = .bottom(15)
fileprivate let leadingPadding: ALConstraint = .leading(20)
fileprivate let trailingPadding: ALConstraint = .trailing(20)
fileprivate let saperatorPadding: ALConstraint = .top(15)
fileprivate let gridColumnSpacing: CGFloat = 15

fileprivate let watchTableBackgroundColor = NSColor(red: 2.0/3, green: 2.0/3, blue: 2.0/3, alpha: 0.1)
fileprivate let watchTableColumnHeaderColor = NSColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)

fileprivate let subsystem = Logger.makeSubsystem("inspector", ["tablecells"])

fileprivate func formLink(_ value: String) -> NSAttributedString? {
  guard let url = URL(string: value), let scheme = url.scheme,
        scheme == "http" || scheme == "https" else { return nil }
  return NSAttributedString(string: value, attributes: [.link: url])
}

protocol InspectorTabUpdating {
  func updateInfo(dynamic: Bool)
}

class InspectorWindowController: NSWindowController, NSWindowDelegate {
  private var updateTimer: Timer?
  private var observers: [NSObjectProtocol] = []

  private var tabController: InspectorTabController? { window?.contentViewController as? InspectorTabController }

  private var selectedTabVC: (NSViewController & InspectorTabUpdating)? {
    guard let tabController else { return nil }
    return tabController.tabViewItems[tabController.selectedTabViewItemIndex].viewController as? (NSViewController & InspectorTabUpdating)
  }

  init() {
    let window = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 450, height: 480),
      styleMask: [.titled, .closable, .hudWindow, .utilityWindow, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = NSLocalizedString("inspector.window_title", comment: "Inspector")
    window.contentMinSize = NSSize(width: 450, height: 480)
    // Same autosave name the old xib-based window used, so this also restores a position saved by that version.
    window.setFrameAutosaveName("IINAInspectorPanel")

    super.init(window: window)
    window.delegate = self

    let toolbar = NSToolbar(identifier: "InspectorToolbar")
    toolbar.allowsUserCustomization = false
    toolbar.displayMode = .iconOnly
    toolbar.delegate = self
    window.toolbar = toolbar
    window.toolbarStyle = .unifiedCompact

    window.contentViewController = InspectorTabController()
  }

  @objc private func toolbarSegmentChanged(_ sender: NSSegmentedControl) {
    guard let tabController else { return }
    tabController.selectedTabViewItemIndex = sender.selectedSegment
    selectedTabVC?.updateInfo(dynamic: false)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func showWindow(_ sender: Any?) {
    selectedTabVC?.updateInfo(dynamic: false)

    removeTimerAndListeners()
    updateTimer = Timer.scheduledTimer(timeInterval: TimeInterval(1), target: self, selector: #selector(dynamicUpdate), userInfo: nil, repeats: true)

    observers.append(NotificationCenter.default.addObserver(forName: .iinaFileLoaded, object: nil, queue: .main, using: fileLoaded))
    observers.append(NotificationCenter.default.addObserver(forName: .iinaMainWindowChanged, object: nil, queue: .main, using: fileLoaded))

    super.showWindow(sender)
  }

  func windowWillClose(_ notification: Notification) {
    removeTimerAndListeners()
  }

  private func removeTimerAndListeners() {
    updateTimer?.invalidate()
    updateTimer = nil
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
  }

  private func fileLoaded(_ notification: Notification) {
    selectedTabVC?.updateInfo(dynamic: false)
  }

  @objc private func dynamicUpdate() {
    selectedTabVC?.updateInfo(dynamic: true)
  }
}

extension InspectorWindowController: NSToolbarDelegate {
  private static let tabs = NSToolbarItem.Identifier("Clear")
  private static let toolbarItems = [tabs]

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    Self.toolbarItems
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    Self.toolbarItems
  }

  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
    let item = NSToolbarItem(itemIdentifier: itemIdentifier)
    let labelKeys = ["General", "Tracks", "File", "Status"]
    let labels = labelKeys.map { NSLocalizedString($0, comment: $0) }
    let segmentedControl = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: self, action: #selector(toolbarSegmentChanged(_:)))
    segmentedControl.selectedSegment = 0
    item.view = segmentedControl
    return item
  }
}

class InspectorTabController: NSTabViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    tabStyle = .unspecified

    addTabViewItem(NSTabViewItem(viewController: GeneralVC()))
    addTabViewItem(NSTabViewItem(viewController: TracksVC()))
    addTabViewItem(NSTabViewItem(viewController: FileVC()))
    addTabViewItem(NSTabViewItem(viewController: StatusVC()))
  }
}

class CommonField: NSTextField {
  enum Style {
    case header
    case prompt
    case value
  }

  convenience init(_ text: String = "", style: Style) {
    self.init(labelWithString: text)
    translatesAutoresizingMaskIntoConstraints = false
    isEditable = false
    switch style {
    case .header:
      font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    case .prompt:
      font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
    case .value:
      font = .systemFont(ofSize: NSFont.smallSystemFontSize)
      tag = 1
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var stringValue: String {
    get { super.stringValue }
    set {
      let hasValue = !newValue.isEmpty
      super.stringValue = hasValue ? newValue : NSLocalizedString("general.na", comment: "N/A")
      if tag == 1 {
        isSelectable = hasValue
        setColor(by: hasValue)
      }
    }
  }

  override var attributedStringValue: NSAttributedString {
    didSet {
      isSelectable = true
      setColor(by: true)
    }
  }

  func setColor(by state: Bool) {
    textColor = state ? .labelColor : .disabledControlTextColor
  }
}

class GeneralVC: NSViewController, InspectorTabUpdating {
  let videoFormat = CommonField(style: .value)
  let videoCodec = CommonField(style: .value)
  let videoDecoder = CommonField(style: .value)
  let videoPrimaries = CommonField(style: .value)
  let videoColorspace = CommonField(style: .value)
  let videoPixelFormat = CommonField(style: .value)
  let videoDriver = CommonField(style: .value)
  let videoSize = CommonField(style: .value)
  let videoBitRate = CommonField(style: .value)
  let videoFPS = CommonField(style: .value)

  let audioFormat = CommonField(style: .value)
  let audioCodec = CommonField(style: .value)
  let audioDriver = CommonField(style: .value)
  let audioChannels = CommonField(style: .value)
  let audioBitRate = CommonField(style: .value)
  let audioSampleRate = CommonField(style: .value)

  override func loadView() {
    let view = NSView()
    self.view = view

    let videoSectionHeader = CommonField(NSLocalizedString("inspector.video_section", comment: "VIDEO"), style: .header)
    view.addSubview(videoSectionHeader)
    videoSectionHeader.padding(topPadding, leadingPadding)

    let videoGridView = NSGridView()
    videoGridView.translatesAutoresizingMaskIntoConstraints = false
    videoGridView.columnSpacing = gridColumnSpacing
    videoGridView.addRow(with: [CommonField(NSLocalizedString("inspector.video_format", comment: "Format"), style: .prompt), videoFormat])
    videoGridView.addRow(with: [CommonField(NSLocalizedString("inspector.video_codec", comment: "Codec"), style: .prompt), videoCodec])
    videoGridView.addRow(with: [CommonField(NSLocalizedString("inspector.video_hw_decoder", comment: "Hw Decoder"), style: .prompt), videoDecoder])
    videoGridView.addRow(with: [CommonField(NSLocalizedString("inspector.video_primaries", comment: "Primaries"), style: .prompt), videoPrimaries])
    videoGridView.addRow(with: [CommonField(NSLocalizedString("inspector.video_colorspace", comment: "Colorspace"), style: .prompt), videoColorspace])
    videoGridView.addRow(with: [CommonField(NSLocalizedString("inspector.video_pixel_format", comment: "Pixel Format"), style: .prompt), videoPixelFormat])
    videoGridView.addRow(with: [CommonField(NSLocalizedString("inspector.video_driver", comment: "Driver"), style: .prompt), videoDriver])
    videoGridView.addRow(with: [CommonField(NSLocalizedString("inspector.video_size", comment: "Size"), style: .prompt), videoSize])
    videoGridView.addRow(with: [CommonField(NSLocalizedString("inspector.video_bitrate", comment: "Bit Rate"), style: .prompt), videoBitRate])
    videoGridView.addRow(with: [CommonField(NSLocalizedString("inspector.video_fps", comment: "FPS"), style: .prompt), videoFPS])

    view.addSubview(videoGridView)
    videoGridView.spacing(.top(12), to: videoSectionHeader)
    videoGridView.leadingAnchor.constraint(equalTo: videoSectionHeader.leadingAnchor).isActive = true

    let separator = NSBox()
    separator.boxType = .separator
    separator.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(separator)
    separator.spacing(saperatorPadding, to: videoGridView)
    separator.leadingAnchor.constraint(equalTo: videoSectionHeader.leadingAnchor).isActive = true
    separator.padding(trailingPadding)

    let audioSectionHeader = CommonField(NSLocalizedString("inspector.audio_section", comment: "AUDIO"), style: .header)
    view.addSubview(audioSectionHeader)
    audioSectionHeader.spacing(saperatorPadding, to: separator)
    audioSectionHeader.leadingAnchor.constraint(equalTo: videoSectionHeader.leadingAnchor).isActive = true

    let audioGridView = NSGridView()
    audioGridView.translatesAutoresizingMaskIntoConstraints = false
    audioGridView.columnSpacing = gridColumnSpacing
    audioGridView.addRow(with: [CommonField(NSLocalizedString("inspector.audio_format", comment: "Format"), style: .prompt), audioFormat])
    audioGridView.addRow(with: [CommonField(NSLocalizedString("inspector.audio_codec", comment: "Codec"), style: .prompt), audioCodec])
    audioGridView.addRow(with: [CommonField(NSLocalizedString("inspector.audio_driver", comment: "Driver"), style: .prompt), audioDriver])
    audioGridView.addRow(with: [CommonField(NSLocalizedString("inspector.audio_channels", comment: "Channels"), style: .prompt), audioChannels])
    audioGridView.addRow(with: [CommonField(NSLocalizedString("inspector.audio_bitrate", comment: "Bit Rate"), style: .prompt), audioBitRate])
    audioGridView.addRow(with: [CommonField(NSLocalizedString("inspector.audio_sample_rate", comment: "Sample Rate"), style: .prompt), audioSampleRate])

    view.addSubview(audioGridView)
    audioGridView.spacing(.top(12), to: audioSectionHeader)
    audioGridView.leadingAnchor.constraint(equalTo: videoSectionHeader.leadingAnchor).isActive = true
  }

  func updateInfo(dynamic: Bool) {
    let player = PlayerCore.lastActive
    guard player.info.state.active, let controller = player.mpv else { return }

    DispatchQueue.main.async { [self] in
      if !dynamic {
        let strProperties: [String: NSTextField] = [
          // in mpv 0.38, video-codec-name is an alias of current-tracks/video/codec, etc
          MPVProperty.currentTracksVideoCodec: videoFormat,
          MPVProperty.currentTracksVideoCodecDesc: videoCodec,
          MPVProperty.containerFps: videoFPS,
          MPVProperty.currentVo: videoDriver,
          MPVProperty.currentTracksAudioCodecDesc: audioCodec,
          MPVProperty.audioParamsFormat: audioFormat,
          MPVProperty.audioParamsChannels: audioChannels,
          MPVProperty.audioParamsSamplerate: audioSampleRate,
        ]

        for (k, v) in strProperties {
          let value = controller.getString(k)
          v.stringValue = value ?? ""
        }

        let vwidth = controller.getInt(MPVProperty.width)
        let vheight = controller.getInt(MPVProperty.height)
        videoSize.stringValue = "\(vwidth)\u{d7}\(vheight)"
      }

      let vbitrate = controller.getInt(MPVProperty.videoBitrate)
      videoBitRate.stringValue = FloatingPointByteCountFormatter.string(fromByteCount: vbitrate) + "bps"

      let abitrate = controller.getInt(MPVProperty.audioBitrate)
      audioBitRate.stringValue = FloatingPointByteCountFormatter.string(fromByteCount: abitrate) + "bps"

      let dynamicStrProperties: [String: NSTextField] = [
        // At any point in time while the video is playing hardware decoding may fail causing a fall
        // back to software decoding.
        MPVProperty.hwdecCurrent: videoDecoder,
        MPVProperty.currentAo: audioDriver,
      ]

      for (k, v) in dynamicStrProperties {
        let value = controller.getString(k)
        v.stringValue = value ?? ""
      }

      let sigPeak = controller.getDouble(MPVProperty.videoParamsSigPeak)
      videoPrimaries.stringValue = sigPeak > 0
        ? "\(controller.getString(MPVProperty.videoParamsPrimaries) ?? "?") / \(controller.getString(MPVProperty.videoParamsGamma) ?? "?") (\(sigPeak > 1 ? "H" : "S")DR)"
        : ""

      let player = PlayerCore.lastActive
      if player.mainWindow.loaded && player.info.state.loaded {
        if let colorspace = player.mainWindow.videoView.videoLayer.colorspace {
          let screenColorSpace = player.mainWindow.window?.screen?.colorSpace
          let sdrColorSpace = screenColorSpace?.cgColorSpace ?? VideoView.SRGB
          let isHdr = colorspace != sdrColorSpace
          // Prefer the name of the CGColorSpace of the layer. If the CGColorSpace does not have a
          // name then if the layer is set to the color space of the screen then fall back to the
          // localized name on the NSColorSpace, if present. Otherwise report it as unspecified.
          let name: String = {
            if let name = colorspace.name { return name as String }
            if let screenColorSpace, colorspace == screenColorSpace.cgColorSpace,
               let name = screenColorSpace.localizedName { return name }
            return "Unspecified"
          }()
          videoColorspace.stringValue = "\(name) (\(isHdr ? "H" : "S")DR)"
        } else {
          videoColorspace.stringValue = "Unspecified (SDR)"
        }
      } else {
        videoColorspace.stringValue = ""
      }
      videoColorspace.setColor(by: player.info.state.loaded)

      if player.mainWindow.loaded && player.info.state.loaded {
        if let hwPf = controller.getString(MPVProperty.videoParamsHwPixelformat) {
          videoPixelFormat.stringValue = "\(hwPf) (HW)"
        } else if let swPf = controller.getString(MPVProperty.videoParamsPixelformat) {
          videoPixelFormat.stringValue = "\(swPf) (SW)"
        } else {
          videoPixelFormat.stringValue = ""
        }
      }
      videoPixelFormat.setColor(by: player.info.state.loaded)
    }
  }
}

class TracksVC: NSViewController, InspectorTabUpdating {
  let trackPopup = NSPopUpButton()

  let trackId = CommonField(style: .value)
  let trackSourceId = CommonField(style: .value)
  let trackTitle = CommonField(style: .value)
  let trackLanguage = CommonField(style: .value)
  let trackFilePath = CommonField(style: .value)
  let trackCodec = CommonField(style: .value)
  let trackDecoder = CommonField(style: .value)
  let trackFPS = CommonField(style: .value)
  let trackChannels = CommonField(style: .value)
  let trackSampleRate = CommonField(style: .value)

  override func loadView() {
    let view = NSView()
    self.view = view

    trackPopup.translatesAutoresizingMaskIntoConstraints = false
    trackPopup.target = self
    trackPopup.action = #selector(trackSwitched(_:))
    let trackLabel = CommonField(NSLocalizedString("inspector.track_label", comment: "Track"), style: .prompt)
    view.addSubview(trackLabel)
    view.addSubview(trackPopup)
    trackLabel.padding(leadingPadding)
    trackPopup.padding(topPadding, trailingPadding)
    trackPopup.spacing(.leading(12), to: trackLabel)
    trackPopup.firstBaselineAnchor.constraint(equalTo: trackLabel.firstBaselineAnchor).isActive = true

    let separator = NSBox()
    separator.boxType = .separator
    separator.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(separator)
    separator.spacing(saperatorPadding, to: trackPopup)
    separator.leadingAnchor.constraint(equalTo: trackLabel.leadingAnchor).isActive = true
    separator.padding(trailingPadding)

    let gridView = NSGridView()
    gridView.translatesAutoresizingMaskIntoConstraints = false
    gridView.columnSpacing = gridColumnSpacing
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.track_id", comment: "ID"), style: .prompt), trackId])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.track_properties", comment: "Properties"), style: .prompt)])
    // todo: add properties view
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.track_source_id", comment: "Source ID"), style: .prompt), trackSourceId])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.track_title", comment: "Title"), style: .prompt), trackTitle])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.track_language", comment: "Language"), style: .prompt), trackLanguage])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.track_file_path", comment: "File Path"), style: .prompt), trackFilePath])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.track_codec", comment: "Codec"), style: .prompt), trackCodec])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.track_decoder", comment: "Decoder"), style: .prompt), trackDecoder])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.track_fps", comment: "FPS"), style: .prompt), trackFPS])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.track_channels", comment: "Channels"), style: .prompt), trackChannels])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.track_sample_rate", comment: "Sample Rate"), style: .prompt), trackSampleRate])

    view.addSubview(gridView)
    gridView.spacing(saperatorPadding, to: separator)
    gridView.leadingAnchor.constraint(equalTo: trackLabel.leadingAnchor).isActive = true
  }

  func updateInfo(dynamic: Bool) {
    guard !dynamic else { return }
    let player = PlayerCore.lastActive
    guard player.info.state.active else { return }
    let info = player.info

    DispatchQueue.main.async { [self] in
      trackPopup.removeAllItems()
      var needSeparator = false
      for track in info.videoTracks {
        trackPopup.menu?.addItem(withTitle: NSLocalizedString("track.video", comment: "Video") + track.readableTitle,
                                 action: nil, tag: nil, obj: track, stateOn: false)
        needSeparator = true
      }
      if needSeparator && !info.audioTracks.isEmpty {
        trackPopup.menu?.addItem(NSMenuItem.separator())
      }
      for track in info.audioTracks {
        trackPopup.menu?.addItem(withTitle: NSLocalizedString("track.audio", comment: "Audio") + track.readableTitle,
                                 action: nil, tag: nil, obj: track, stateOn: false)
        needSeparator = true
      }
      if needSeparator && !info.subTracks.isEmpty {
        trackPopup.menu?.addItem(NSMenuItem.separator())
      }
      for track in info.subTracks {
        trackPopup.menu?.addItem(withTitle: NSLocalizedString("track.sub", comment: "Subtitle") + track.readableTitle,
                                 action: nil, tag: nil, obj: track, stateOn: false)
      }
      trackPopup.selectItem(at: 0)
      updateTrack()
    }
  }

  @objc private func trackSwitched(_ sender: AnyObject) {
    updateTrack()
  }

  private func updateTrack() {
    guard let track = trackPopup.selectedItem?.representedObject as? MPVTrack else { return }

    trackId.stringValue = "\(track.id)"

    let strProperties: [(String?, NSTextField)] = [
      (track.srcId?.description, trackSourceId),
      (track.title, trackTitle),
      (track.readableLanguage, trackLanguage),
      (track.externalFilename, trackFilePath),
      (track.codec, trackCodec),
      (track.decoderDesc, trackDecoder),
      (track.demuxFps?.description, trackFPS),
      (track.demuxChannels, trackChannels),
      (track.demuxSamplerate?.description, trackSampleRate),
    ]

    for (str, field) in strProperties {
      field.stringValue = str ?? ""
    }
  }
}

class FileVC: NSViewController, InspectorTabUpdating {
  let filePath = CommonField(style: .value)

  let fileTitle = CommonField(style: .value)
  let fileComment = CommonField(style: .value)
  let fileSize = CommonField(style: .value)
  let fileFormat = CommonField(style: .value)
  let fileDuration = CommonField(style: .value)
  let fileChapters = CommonField(style: .value)
  let fileEditions = CommonField(style: .value)

  override func loadView() {
    let view = NSView()
    self.view = view

    let filePathLabel = CommonField(NSLocalizedString("inspector.file_path", comment: "File Path"), style: .prompt)
    view.addSubview(filePathLabel)
    filePathLabel.padding(leadingPadding, topPadding)
    view.addSubview(filePath)
    filePath.leadingAnchor.constraint(equalTo: filePathLabel.leadingAnchor).isActive = true
    filePath.spacing(.top(4), to: filePathLabel)

    let separator = NSBox()
    separator.boxType = .separator
    separator.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(separator)
    separator.spacing(saperatorPadding, to: filePath)
    separator.leadingAnchor.constraint(equalTo: filePathLabel.leadingAnchor).isActive = true
    separator.padding(trailingPadding)

    let gridView = NSGridView()
    gridView.translatesAutoresizingMaskIntoConstraints = false
    gridView.columnSpacing = gridColumnSpacing
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.file_title", comment: "Title"), style: .prompt), fileTitle])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.file_comment", comment: "Comment"), style: .prompt), fileComment])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.file_size", comment: "Size"), style: .prompt), fileSize])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.file_format", comment: "Format"), style: .prompt), fileFormat])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.file_duration", comment: "Duration"), style: .prompt), fileDuration])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.file_chapters", comment: "Chapters"), style: .prompt), fileChapters])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.file_editions", comment: "Editions"), style: .prompt), fileEditions])

    view.addSubview(gridView)
    gridView.spacing(saperatorPadding, to: separator)
    gridView.leadingAnchor.constraint(equalTo: filePathLabel.leadingAnchor).isActive = true
  }

  func updateInfo(dynamic: Bool) {
    guard !dynamic else { return }
    let player = PlayerCore.lastActive
    guard player.info.state.active else { return }
    let controller = player.mpv!

    DispatchQueue.main.async { [self] in
      let commentKey = MPVProperty.metadata + "/by-key/comment"

      let strProperties: [String: NSTextField] = [
        MPVProperty.path: filePath,
        MPVProperty.fileFormat: fileFormat,
        MPVProperty.chapters: fileChapters,
        MPVProperty.editions: fileEditions,
        MPVProperty.mediaTitle: fileTitle,
        commentKey: fileComment,
      ]

      for (k, v) in strProperties {
        var value = controller.getString(k)
        if value == "" { value = nil }
        // If the video does not have a title then mpv returns the filename. If that is the case
        // then clear the value. The filename is already being displayed in the path.
        if k == MPVProperty.mediaTitle, let filename = controller.getString(MPVProperty.filename),
           value == filename {
          value = nil
        }
        // The value of these properties may contain links, if so make them clickable.
        if k == MPVProperty.path || k == commentKey, let value, let link = formLink(value) {
          v.attributedStringValue = link
          // Must enable this for the link to be clickable.
          v.allowsEditingTextAttributes = true
        } else {
          v.stringValue = value ?? ""
          v.allowsEditingTextAttributes = false
        }
      }

      let duration = controller.getDouble(MPVProperty.duration)
      fileDuration.stringValue = VideoTime(duration).stringRepresentation

      let fileSize = controller.getInt(MPVProperty.fileSize)
      self.fileSize.stringValue = "\(FloatingPointByteCountFormatter.string(fromByteCount: fileSize))B"
    }
  }
}

class StatusVC: NSViewController, NSTableViewDelegate, NSTableViewDataSource, InspectorTabUpdating {
  let avSyncDiff = CommonField(style: .value)
  let totalAVSync = CommonField(style: .value)
  let droppedFrames = CommonField(style: .value)
  let mistimedFrames = CommonField(style: .value)
  let displayFPS = CommonField(style: .value)
  let estimatedOutputFPS = CommonField(style: .value)
  let estimatedDisplayFPS = CommonField(style: .value)

  var watchProperties: [String] = []
  let watchTableView = NSTableView()
  let deleteButton = NSButton()
  private let tableContainerView = NSView()

  override func loadView() {
    let view = NSView()
    self.view = view

    let gridView = NSGridView()
    gridView.translatesAutoresizingMaskIntoConstraints = false
    gridView.columnSpacing = gridColumnSpacing
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.status_avsync_diff", comment: "A/V Sync Diff"), style: .prompt), avSyncDiff])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.status_total_avsync", comment: "Total A/V Sync"), style: .prompt), totalAVSync])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.status_dropped_frames", comment: "Dropped Frames"), style: .prompt), droppedFrames])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.status_mistimed_frames", comment: "Mistimed Frames"), style: .prompt), mistimedFrames])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.status_display_fps", comment: "Display FPS"), style: .prompt), displayFPS])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.status_estimated_output_fps", comment: "Estimated Output FPS"), style: .prompt), estimatedOutputFPS])
    gridView.addRow(with: [CommonField(NSLocalizedString("inspector.status_estimated_display_fps", comment: "Estimated Disp FPS"), style: .prompt), estimatedDisplayFPS])

    view.addSubview(gridView)
    gridView.padding(topPadding, leadingPadding)

    let separator = NSBox()
    separator.boxType = .separator
    separator.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(separator)
    separator.spacing(saperatorPadding, to: gridView)
    separator.leadingAnchor.constraint(equalTo: gridView.leadingAnchor).isActive = true
    separator.padding(trailingPadding)

    let watchLabel = CommonField(NSLocalizedString("inspector.status_watch", comment: "Watch"), style: .prompt)
    view.addSubview(watchLabel)
    watchLabel.spacing(saperatorPadding, to: separator)
    watchLabel.leadingAnchor.constraint(equalTo: gridView.leadingAnchor).isActive = true

    // MARK: Watch table

    watchProperties = Preference.array(for: .watchProperties) as! [String]

    let keyColumn = NSTableColumn(identifier: .key)
    keyColumn.title = NSLocalizedString("inspector.watch_column_name", comment: "Name")
    keyColumn.minWidth = 120
    keyColumn.width = 180
    keyColumn.maxWidth = 1000

    let valueColumn = NSTableColumn(identifier: .value)
    valueColumn.title = NSLocalizedString("inspector.watch_column_value", comment: "Value")
    valueColumn.minWidth = 120
    valueColumn.width = 228
    valueColumn.maxWidth = 10000

    watchTableView.addTableColumn(keyColumn)
    watchTableView.addTableColumn(valueColumn)
    watchTableView.style = .plain
    watchTableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    watchTableView.focusRingType = .none
    watchTableView.allowsColumnReordering = false
    watchTableView.autosaveName = "InspectorWatchTable"
    watchTableView.delegate = self
    watchTableView.dataSource = self

    let headerFont = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
    for column in watchTableView.tableColumns {
      let headerCell = WatchTableColumnHeaderCell()
      // Use the localized title we just set on the column
      let title = column.headerCell.title
      // Use small bold system font
      headerCell.attributedStringValue = NSMutableAttributedString(string: title, attributes: [.font: headerFont])
      column.headerCell = headerCell
    }

    watchTableView.backgroundColor = .clear

    let scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.documentView = watchTableView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.drawsBackground = false

    tableContainerView.translatesAutoresizingMaskIntoConstraints = false
    tableContainerView.wantsLayer = true
    tableContainerView.layer?.backgroundColor = watchTableBackgroundColor.cgColor
    tableContainerView.addSubview(scrollView)
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: tableContainerView.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: tableContainerView.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: tableContainerView.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: tableContainerView.bottomAnchor),
    ])

    view.addSubview(tableContainerView)
    tableContainerView.spacing(saperatorPadding, to: watchLabel)
    tableContainerView.leadingAnchor.constraint(equalTo: gridView.leadingAnchor).isActive = true
    tableContainerView.padding(trailingPadding)

    tableContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true

    let addButton = NSButton(image: NSImage(named: NSImage.addTemplateName)!, target: self, action: #selector(addWatchAction(_:)))
    addButton.isBordered = false
    addButton.imagePosition = .imageOnly
    addButton.translatesAutoresizingMaskIntoConstraints = false

    deleteButton.image = NSImage(named: NSImage.removeTemplateName)
    deleteButton.target = self
    deleteButton.action = #selector(removeWatchAction(_:))
    deleteButton.isBordered = false
    deleteButton.imagePosition = .imageOnly
    deleteButton.translatesAutoresizingMaskIntoConstraints = false
    deleteButton.isEnabled = false

    view.addSubview(addButton)
    view.addSubview(deleteButton)

    NSLayoutConstraint.activate([
      addButton.widthAnchor.constraint(equalTo: addButton.heightAnchor),
      addButton.heightAnchor.constraint(equalToConstant: 16),
      deleteButton.widthAnchor.constraint(equalTo: deleteButton.heightAnchor),
      deleteButton.heightAnchor.constraint(equalToConstant: 16),
      deleteButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor),
      deleteButton.topAnchor.constraint(equalTo: addButton.topAnchor),
    ])
    addButton.spacing(saperatorPadding, to: tableContainerView)
    addButton.leadingAnchor.constraint(equalTo: gridView.leadingAnchor).isActive = true
    addButton.padding(bottomPadding)

    watchTableView.scrollRowToVisible(0)
  }

  // MARK: - NSTableView

  func numberOfRows(in tableView: NSTableView) -> Int {
    return watchProperties.count
  }

  private static func makeCellView(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
    let cellView = NSTableCellView()
    cellView.identifier = identifier
    let textField = NSTextField(labelWithString: "")
    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.lineBreakMode = .byTruncatingTail
    cellView.addSubview(textField)
    cellView.textField = textField
    NSLayoutConstraint.activate([
      textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
      textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
    ])
    return cellView
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let identifier = tableColumn?.identifier else { return nil }
    let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? Self.makeCellView(identifier: identifier)
    guard let property = watchProperties[at: row] else { return nil }

    switch identifier {
    case .key:
      if let textField = cell.textField {
        textField.stringValue = property
      }
      return cell
    case .value:
      let player = PlayerCore.lastActive

      if let textField = cell.textField {
        textField.allowsEditingTextAttributes = false
        if player.info.state.active, let value = player.mpv.getString(property) {
          if let link = formLink(value) {
            textField.attributedStringValue = link
            // Must enable this for the link to be clickable.
            textField.allowsEditingTextAttributes = true
          } else {
            textField.stringValue = value
          }
          textField.isSelectable = true
          textField.textColor = .labelColor
        } else {
          let errorString = NSLocalizedString("inspector.error", comment: "Error")

          let italicDescriptor: NSFontDescriptor = textField.font!.fontDescriptor.withSymbolicTraits(NSFontDescriptor.SymbolicTraits.italic)
          let errorFont = NSFont(descriptor: italicDescriptor, size: textField.font!.pointSize)

          textField.attributedStringValue = NSMutableAttributedString(string: errorString, attributes: [.font: errorFont!])
          textField.isSelectable = false
          textField.textColor = .disabledControlTextColor
        }
      }
      return cell
    default:
      Logger.log("Unrecognized column: '\(identifier.rawValue)'", level: .error, subsystem: subsystem)
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

  @objc func addWatchAction(_ sender: AnyObject) {
    Utility.quickPromptPanel("add_watch", sheetWindow: view.window) { [self] str in
      watchProperties.append(str)
      saveWatchList()

      // Append row to end of table, with animation if preferred
      let insertIndexSet = IndexSet(integer: watchTableView.numberOfRows)
      watchTableView.insertRows(at: insertIndexSet, withAnimation: AccessibilityPreferences.motionReductionEnabled ? [] : .slideDown)
      watchTableView.selectRowIndexes(insertIndexSet, byExtendingSelection: false)
    }
  }

  @objc func removeWatchAction(_ sender: AnyObject) {
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
  }

  private func saveWatchList() {
    Preference.set(watchProperties, for: .watchProperties)
  }

  func updateInfo(dynamic: Bool) {
    let player = PlayerCore.lastActive
    guard player.info.state.active else { return }
    let controller = player.mpv!

    DispatchQueue.main.async { [self] in
      let dynamicStrProperties: [String: NSTextField] = [
        MPVProperty.avsync: avSyncDiff,
        MPVProperty.totalAvsyncChange: totalAVSync,
        MPVProperty.frameDropCount: droppedFrames,
        MPVProperty.mistimedFrameCount: mistimedFrames,
        MPVProperty.displayFps: displayFPS,
        MPVProperty.estimatedVfFps: estimatedOutputFPS,
        MPVProperty.estimatedDisplayFps: estimatedDisplayFPS,
      ]

      for (k, v) in dynamicStrProperties {
        let value = controller.getString(k)
        v.stringValue = value ?? ""
      }

      /// Do not call `reloadData()` (no arg version) because it will clear the selection. Also, because we know the number of rows will not change,
      /// calling `reloadData(forRowIndexes:)` will get the same result but much more efficiently
      watchTableView.reloadData(forRowIndexes: IndexSet(0..<watchTableView.numberOfRows), columnIndexes: IndexSet(0..<watchTableView.numberOfColumns))
    }
  }
}

class WatchTableColumnHeaderCell: NSTableHeaderCell {
  override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
    // Override background color
    drawsBackground = false
    watchTableColumnHeaderColor.set()
    cellFrame.fill(using: .sourceOver)

    super.draw(withFrame: cellFrame, in: controlView)
  }
}
