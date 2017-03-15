//
//  PrefCodecViewController.swift
//  iina
//
//  Created by lhc on 27/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class PrefCodecViewController: NSViewController {

  override var nibName: String? {
    return "PrefCodecViewController"
  }

  override var identifier: String? {
    get {
      return "codec"
    }
    set {
      super.identifier = newValue
    }
  }

  var toolbarItemImage: NSImage {
    return NSImage(named: "toolbar_codec")!
  }

  var toolbarItemLabel: String {
    view.layoutSubtreeIfNeeded()
    return NSLocalizedString("preference.codec", comment: "Codec")
  }

  var hasResizableWidth: Bool = false
  var hasResizableHeight: Bool = false

  @IBOutlet weak var spdifAC3Btn: NSButton!
  @IBOutlet weak var spdifDTSBtn: NSButton!
  @IBOutlet weak var spdifDTSHDBtn: NSButton!

  @IBOutlet weak var videoThreadsTextField: NSTextField!
  @IBOutlet weak var audioThreadsTextField: NSTextField!
  @IBOutlet weak var maximumVolumeTextField: NSTextField!

  override func viewDidLoad() {
    super.viewDidLoad()

    let spdif = (PlayerCore.shared.mpvController.getString(MPVOption.Audio.audioSpdif) ?? "").components(separatedBy: ",")
    spdifAC3Btn.state = spdif.contains("ac3") ? NSOnState : NSOffState
    spdifDTSBtn.state = spdif.contains("dts") ? NSOnState : NSOffState
    spdifDTSHDBtn.state = spdif.contains("dts-hd") ? NSOnState : NSOffState

    videoThreadsTextField.formatter = RestrictedNumberFormatter(0, max: nil, isDecimal: false)
    audioThreadsTextField.formatter = RestrictedNumberFormatter(0, max: nil, isDecimal: false)
    maximumVolumeTextField.formatter = RestrictedNumberFormatter(100, max: 1000, isDecimal: false)
  }

  @IBAction func spdifBtnAction(_ sender: AnyObject) {
    var spdif: [String] = []
    if spdifAC3Btn.state == NSOnState { spdif.append("ac3") }
    if spdifDTSBtn.state == NSOnState { spdif.append("dts") }
    if spdifDTSHDBtn.state == NSOnState { spdif.append("dts-hd") }
    PlayerCore.shared.mpvController.setString(MPVOption.Audio.audioSpdif, spdif.joined(separator: ","))
  }

}
