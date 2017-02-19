//
//  InspectorWindowController.swift
//  iina
//
//  Created by lhc on 21/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class InspectorWindowController: NSWindowController {

  override var windowNibName: String {
    return "InspectorWindowController"
  }

  var updateTimer: Timer?

  @IBOutlet weak var tabView: NSTabView!
  @IBOutlet weak var trackPopup: NSPopUpButton!

  @IBOutlet weak var pathField: NSTextField!
  @IBOutlet weak var fileSizeField: NSTextField!
  @IBOutlet weak var fileFormatField: NSTextField!
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


  override func windowDidLoad() {
    super.windowDidLoad()
    window?.appearance = NSAppearance(named: NSAppearanceNameVibrantDark)

    updateInfo()

    updateTimer = Timer.scheduledTimer(timeInterval: TimeInterval(1), target: self, selector: #selector(dynamicUpdate), userInfo: nil, repeats: true)

    NotificationCenter.default.addObserver(self, selector: #selector(fileLoaded), name: Constants.Noti.fileLoaded, object: nil)
  }

  deinit {
    ObjcUtils.silenced {
      NotificationCenter.default.removeObserver(self)
    }
  }

  func updateInfo(dynamic: Bool = false) {
    let controller = PlayerCore.shared.mpvController
    let info = PlayerCore.shared.info

    if !dynamic {

      // string properties

      let strProperties: [String: NSTextField] = [
        MPVProperty.path: pathField,
        MPVProperty.fileFormat: fileFormatField,

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

  }

  func fileLoaded() {
    updateInfo()
  }

  func dynamicUpdate() {
    updateInfo(dynamic: true)
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

}
