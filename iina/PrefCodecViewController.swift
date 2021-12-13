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

  var preferenceTabTitle: String {
    return NSLocalizedString("preference.video_audio", comment: "Codec")
  }

  var preferenceTabImage: NSImage {
    return NSImage(named: NSImage.Name("pref_av"))!
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
  @IBOutlet weak var audioLangTokenField: LanguageTokenField!

  @IBOutlet weak var audioDevicePopUp: NSPopUpButton!


  override func viewDidLoad() {
    super.viewDidLoad()
    audioLangTokenField.stringValue = Preference.string(for: .audioLanguage) ?? ""
    updateHwdecDescription()
  }

  override func viewWillAppear() {
    super.viewWillAppear()

    audioDevicePopUp.removeAllItems()
    let audioDevices = PlayerCore.active.getAudioDevices()
    var selected = false
    audioDevices.forEach { device in
      audioDevicePopUp.addItem(withTitle: "[\(device["description"]!)] \(device["name"]!)")
      audioDevicePopUp.lastItem!.representedObject = device
      if device["name"] == Preference.string(for: .audioDevice) {
        audioDevicePopUp.select(audioDevicePopUp.lastItem!)
        selected = true
      }
    }
    if !selected {
      let device = ["name": Preference.string(for: .audioDevice)!,
                    "description": Preference.string(for: .audioDeviceDesc)!]
      audioDevicePopUp.addItem(withTitle: "[\(device["description"]!) (missing)] \(device["name"]!)")
      audioDevicePopUp.lastItem!.representedObject = device
      audioDevicePopUp.select(audioDevicePopUp.lastItem!)
    }
  }

  @IBAction func audioDeviceAction(_ sender: Any) {
    let device = audioDevicePopUp.selectedItem!.representedObject as! [String: String]
    Preference.set(device["name"]!, for: .audioDevice)
    Preference.set(device["description"]!, for: .audioDeviceDesc)
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

  @IBAction func preferredLanguageAction(_ sender: LanguageTokenField) {
    Preference.set(sender.stringValue, for: .audioLanguage)
  }

  private func updateHwdecDescription() {
    let hwdec: Preference.HardwareDecoderOption = Preference.enum(for: .hardwareDecoder)
    hwdecDescriptionTextField.stringValue = hwdec.localizedDescription
  }
}
