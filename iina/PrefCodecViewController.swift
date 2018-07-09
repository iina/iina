//
//  PrefCodecViewController.swift
//  iina
//
//  Created by lhc on 27/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

@objcMembers
class PrefCodecViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefCodecViewController")
  }

  var viewIdentifier: String = "PrefCodecViewController"

  var toolbarItemImage: NSImage {
    return #imageLiteral(resourceName: "toolbar_codec")
  }

  var preferenceTabTitle: String {
    view.layoutSubtreeIfNeeded()
    return NSLocalizedString("preference.video_audio", comment: "Codec")
  }

  override var sectionViews: [NSView] {
    return [sectionVideoView, sectionAudioView]
  }

  @IBOutlet var sectionVideoView: NSView!
  @IBOutlet var sectionAudioView: NSView!

  @IBOutlet weak var spdifAC3Btn: NSButton!
  @IBOutlet weak var spdifDTSBtn: NSButton!
  @IBOutlet weak var spdifDTSHDBtn: NSButton!
  @IBOutlet weak var hwdecDescriptionTextField: NSTextField!


  override func viewDidLoad() {
    super.viewDidLoad()
    updateHwdecDescription()
  }

  @IBAction func spdifBtnAction(_ sender: AnyObject) {
    var spdif: [String] = []
    if spdifAC3Btn.state == .on { spdif.append("ac3") }
    if spdifDTSBtn.state == .on { spdif.append("dts") }
    if spdifDTSHDBtn.state == .on { spdif.append("dts-hd") }
    let spdifString = spdif.joined(separator: ",")
    PlayerCore.playerCores.forEach { $0.mpv.setString(MPVOption.Audio.audioSpdif, spdifString) }
  }

  @IBAction func hwdecAction(_ sender: AnyObject) {
    updateHwdecDescription()
  }

  private func updateHwdecDescription() {
    let hwdec: Preference.HardwareDecoderOption = Preference.enum(for: .hardwareDecoder)
    hwdecDescriptionTextField.stringValue = hwdec.localizedDescription
  }

}
