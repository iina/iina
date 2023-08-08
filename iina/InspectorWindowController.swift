//
//  InspectorWindowController.swift
//  iina
//
//  Created by lhc on 21/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class InspectorWindowController: NSWindowController, NSWindowDelegate, NSTableViewDelegate, NSTableViewDataSource {

  override var windowNibName: NSNib.Name {
    return NSNib.Name("InspectorWindowController")
  }

  var updateTimer: Timer?

  var watchProperties: [String] = []

  private var observers: [NSObjectProtocol] = []

  @IBOutlet weak var tabView: NSTabView!
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

  // MARK: - Window Delegate

  override func windowDidLoad() {
    super.windowDidLoad()

    watchProperties = Preference.array(for: .watchProperties) as! [String]
    watchTableView.delegate = self
    watchTableView.dataSource = self

    deleteButton.isEnabled = false

    if #available(macOS 10.14, *) {} else {
      window?.appearance = NSAppearance(named: .vibrantDark)
    }

    updateInfo()
  }

  override func showWindow(_ sender: Any?) {
    Logger.log("Showing Inspector window", level: .verbose)

    guard let _ = self.window else { return }  // trigger lazy load if not loaded

    updateInfo()

    removeTimerAndListeners()
    updateTimer = Timer.scheduledTimer(timeInterval: TimeInterval(1), target: self, selector: #selector(dynamicUpdate), userInfo: nil, repeats: true)

    observers.append(NotificationCenter.default.addObserver(forName: .iinaFileLoaded, object: nil, queue: .main, using: self.fileLoaded))
    observers.append(NotificationCenter.default.addObserver(forName: .iinaMainWindowChanged, object: nil, queue: .main, using: self.fileLoaded))

    super.showWindow(sender)
  }

  func windowWillClose(_ notification: Notification) {
    Logger.log("Closing Inspector window", level: .verbose)
    // Remove timer & listeners to conserve resources
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

  func fileLoaded(_ notification: Notification) {
    updateInfo()
  }

  @objc func dynamicUpdate() {
    updateInfo(dynamic: true)
    watchTableView.reloadData()
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

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    guard let identifier = tableColumn?.identifier else { return nil }

    guard let property = watchProperties[at: row] else { return nil }
    if identifier == .key {
      return property
    } else if identifier == .value {
      return PlayerCore.lastActive.mpv.getString(property) ?? "<Error>"
    }
    return ""
  }

  func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
    guard let value = object as? String,
      let identifier = tableColumn?.identifier else { return }
    if identifier == .key {
      watchProperties[row] = value
    }
    saveWatchList()
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    deleteButton.isEnabled = (watchTableView.selectedRow != -1)
  }

  @IBAction func addWatchAction(_ sender: AnyObject) {
    Utility.quickPromptPanel("add_watch", sheetWindow: window) { str in
      self.watchProperties.append(str)
      self.watchTableView.reloadData()
      self.saveWatchList()
    }
  }

  @IBAction func removeWatchAction(_ sender: AnyObject) {
    if watchTableView.selectedRow >= 0 {
      watchProperties.remove(at: watchTableView.selectedRow)
      watchTableView.reloadData()
    }
    saveWatchList()
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

}
