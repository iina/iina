//
//  InspectorWindowController.swift
//  iina
//
//  Created by lhc on 21/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class InspectorWindowController: NSWindowController, NSTableViewDelegate, NSTableViewDataSource {

  override var windowNibName: NSNib.Name {
    return NSNib.Name("InspectorWindowController")
  }

  var updateTimer: Timer?

  var watchProperties: [String] = []

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


  override func windowDidLoad() {
    super.windowDidLoad()
    window?.appearance = NSAppearance(named: .vibrantDark)

    watchProperties = Preference.array(for: .watchProperties) as! [String]
    watchTableView.delegate = self
    watchTableView.dataSource = self

    updateInfo()

    updateTimer = Timer.scheduledTimer(timeInterval: TimeInterval(1), target: self, selector: #selector(dynamicUpdate), userInfo: nil, repeats: true)

    NotificationCenter.default.addObserver(self, selector: #selector(fileLoaded), name: Constants.Noti.fileLoaded, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(fileLoaded), name: Constants.Noti.mainWindowChanged, object: nil)
  }

  deinit {
    ObjcUtils.silenced {
      NotificationCenter.default.removeObserver(self)
    }
  }

  func updateInfo(dynamic: Bool = false) {
    let controller = PlayerCore.lastActive.mpv!
    let info = PlayerCore.lastActive.info

    if !dynamic {

      // string properties

      let strProperties: [String: NSTextField] = [
        MPVProperty.path: pathField,
        MPVProperty.fileFormat: fileFormatField,
        MPVProperty.chapters: chaptersField,
        MPVProperty.editions: editionsField,

        MPVProperty.videoFormat: vformatField,
        MPVProperty.videoCodec: vcodecField,
        MPVProperty.hwdecCurrent: vdecoderField,
        MPVProperty.containerFps: vfpsField,
        MPVProperty.currentVo: voField,
        MPVProperty.audioCodec: acodecField,
        MPVProperty.currentAo: aoField,
        MPVProperty.audioParamsFormat: aformatField,
        MPVProperty.audioParamsChannels: achannelsField,
        MPVProperty.audioBitrate: abitrateField,
        MPVProperty.audioParamsSamplerate: asamplerateField
      ]

      for (k, v) in strProperties {
        let value = controller.getString(k)
        v.stringValue = value ?? "N/A"
        setLabelColor(v, by: value != nil)
      }

      // other properties

      let duration = controller.getDouble(MPVProperty.duration)
      durationField.stringValue = VideoTime(duration).stringRepresentation

      let vwidth = controller.getInt(MPVProperty.width)
      let vheight = controller.getInt(MPVProperty.height)
      vsizeField.stringValue = "\(vwidth)\u{d7}\(vheight)"

      let fileSize = controller.getInt(MPVProperty.fileSize)
      fileSizeField.stringValue = FileSize.format(fileSize, unit: .b)

      // track list

      trackPopup.removeAllItems()
      for track in info.videoTracks {
        trackPopup.menu?.addItem(withTitle: "Video" + track.readableTitle,
                                 action: nil, tag: nil, obj: track, stateOn: false)
      }
      trackPopup.menu?.addItem(NSMenuItem.separator())
      for track in info.audioTracks {
        trackPopup.menu?.addItem(withTitle: "Audio" + track.readableTitle,
                                 action: nil, tag: nil, obj: track, stateOn: false)
      }
      trackPopup.menu?.addItem(NSMenuItem.separator())
      for track in info.subTracks {
        trackPopup.menu?.addItem(withTitle: "Sub" + track.readableTitle,
                                 action: nil, tag: nil, obj: track, stateOn: false)
      }
      trackPopup.selectItem(at: 0)
      updateTrack()

    }

    let vbitrate = controller.getInt(MPVProperty.videoBitrate)
    vbitrateField.stringValue = FileSize.format(vbitrate, unit: .b) + "bps"

    let abitrate = controller.getInt(MPVProperty.audioBitrate)
    abitrateField.stringValue = FileSize.format(abitrate, unit: .b) + "bps"

    let dynamicStrProperties: [String: NSTextField] = [
      MPVProperty.avsync: avsyncField,
      MPVProperty.totalAvsyncChange: totalAvsyncField,
      MPVProperty.frameDropCount: droppedFramesField,
      MPVProperty.mistimedFrameCount: mistimedFramesField,
      MPVProperty.displayFps: displayFPSField,
      MPVProperty.estimatedVfFps: voFPSField,
      MPVProperty.estimatedDisplayFps: edispFPSField
    ]

    for (k, v) in dynamicStrProperties {
      let value = controller.getString(k)
      v.stringValue = value ?? "N/A"
      setLabelColor(v, by: value != nil)
    }

  }

  @objc func fileLoaded() {
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
      (track.srcId?.toStr(), trackSourceIdField),
      (track.title, trackTitleField),
      (track.lang, trackLangField),
      (track.externalFilename, trackFilePathField),
      (track.codec, trackCodecField),
      (track.decoderDesc, trackDecoderField),
      (track.demuxFps?.toStr(), trackFPSField),
      (track.demuxChannels, trackChannelsField),
      (track.demuxSamplerate?.toStr(), trackSampleRateField)
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

    guard let property = watchProperties.at(row) else { return nil }
    if identifier == .key {
      return property
    } else if identifier == .value {
      return PlayerCore.active.mpv.getString(property) ?? "<Error>"
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

  @IBAction func addWatchAction(_ sender: AnyObject) {
    let _ = Utility.quickPromptPanel("add_watch") { str in
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
