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
    return makeSymbol("play.rectangle.on.rectangle", fallbackImage: "pref_av")
  }

  override var sectionViews: [NSView] {
    return [sectionVideoView, sectionAudioView, sectionReplayGainView]
  }

  @IBOutlet var sectionVideoView: NSView!
  @IBOutlet var sectionAudioView: NSView!
  @IBOutlet var sectionReplayGainView: NSView!
  
  @IBOutlet weak var audioDriverExperimentalIndicator: NSImageView!

  @IBOutlet weak var spdifAC3Btn: NSButton!
  @IBOutlet weak var spdifDTSBtn: NSButton!
  @IBOutlet weak var spdifDTSHDBtn: NSButton!
  @IBOutlet weak var hwdecDescriptionTextField: NSTextField!
  @IBOutlet weak var audioLangTokenField: LanguageTokenField!

  @IBOutlet weak var audioDevicePopUp: NSPopUpButton!

  @IBOutlet weak var enableToneMappingBtn: NSButton!
  @IBOutlet weak var toneMappingTargetPeakTextField: NSTextField!
  @IBOutlet weak var toneMappingAlgorithmPopUpBtn: NSPopUpButton!

  override func viewDidLoad() {
    super.viewDidLoad()
    audioLangTokenField.commaSeparatedValues = Preference.string(for: .audioLanguage) ?? ""
    updateHwdecDescription()
    updateToneMappingUI()
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    
    if #available(macOS 14.0, *) {
      audioDriverExperimentalIndicator.image = NSImage.findSFSymbol(["flask.fill"])
    }

    updateAudioDevicePopUp()

    // The list of audio devices changes based on the audio driver setting.
    UserDefaults.standard.addObserver(self, forKeyPath: PK.audioDriverEnableAVFoundation.rawValue,
                                      options: .new, context: nil)
  }

  @IBAction func audioDeviceAction(_ sender: Any) {
    let device = audioDevicePopUp.selectedItem!.representedObject as! MPVAudioDevice
    Preference.set(device.name, for: .audioDevice)
    Preference.set(device.desc, for: .audioDeviceDesc)
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
    let csv = sender.commaSeparatedValues
    if Preference.string(for: .audioLanguage) != csv {
      Logger.log("Saving \(Preference.Key.audioLanguage.rawValue): \"\(csv)\"", level: .verbose)
      Preference.set(csv, for: .audioLanguage)
    }
  }

  /// Update the list of audio devices.
  ///
  /// The list needs to be updated whenever the configured audio output driver changes as mpv audio devices are tied to a specific
  /// audio output driver. The selected audio device may need to be updated to one using the currently configured audio output driver.
  private func updateAudioDevicePopUp() {
    audioDevicePopUp.removeAllItems()
    let audioDevices = PlayerCore.active.getAudioDevices()
    let audioDevice = Preference.string(for: .audioDevice)!
    var selected = false
    audioDevices.forEach { device in
      audioDevicePopUp.addItem(withTitle: device.description)
      audioDevicePopUp.lastItem!.representedObject = device
      if device.name == audioDevice {
        audioDevicePopUp.select(audioDevicePopUp.lastItem!)
        selected = true
      }
    }
    if !selected {
      // The configured audio device may not have been found because the configured audio output
      // driver was changed. Try and find the same audio device but with the currently configured
      // audio output driver.
      let description = Preference.string(for: .audioDeviceDesc)!
      let device = MPVAudioDevice(desc: description, name: audioDevice)
      let avfoundationEnabled = Preference.bool(for: PK.audioDriverEnableAVFoundation)
      let invalid = avfoundationEnabled ? "coreaudio" : "avfoundation"
      if device.driver == invalid {
        // The configured audio device is not for the currently configured audio output driver. Try
        // and find the same device with the configured driver.
        let driver = avfoundationEnabled ? "avfoundation" : "coreaudio"
        let replacement = MPVAudioDevice(device, driver)
        let index = audioDevicePopUp.indexOfItem(withTitle: String(describing: replacement))
        if index != -1 {
          // Update the audio device configured in settings with the corresponding device that is
          // for the currently configured audio output driver.
          Logger.log("""
              Audio output driver changed to \(driver), changing audio device setting
                from: \(audioDevice)
                to: \(replacement.name)
              """)
          audioDevicePopUp.selectItem(at: index)
          Preference.set(replacement.name, for: .audioDevice)
          selected = true
        }
      }
    }
    if !selected {
      let device = MPVAudioDevice(desc: Preference.string(for: .audioDeviceDesc)!,
                                  name: audioDevice, isMissing: true)
      audioDevicePopUp.addItem(withTitle: String(describing: device))
      audioDevicePopUp.lastItem!.representedObject = device
      audioDevicePopUp.select(audioDevicePopUp.lastItem!)
    }
  }

  private func updateHwdecDescription() {
    let hwdec: Preference.HardwareDecoderOption = Preference.enum(for: .hardwareDecoder)
    hwdecDescriptionTextField.stringValue = hwdec.localizedDescription
  }

  // Prefs → UI
  private func updateToneMappingUI() {
    toneMappingTargetPeakTextField.integerValue = Preference.integer(for: .toneMappingTargetPeak)
  }

  @IBAction func toneMappingTargetPeakAction(_ sender: NSTextField) {
    defer {
      updateToneMappingUI()
    }
    let newValue = sender.integerValue
    // constrain to valid mpv values
    let isValueValid = newValue == 0 || (newValue >= 10 && newValue <= 10000)
    guard isValueValid else {
      Utility.showAlert("target_peak.bad_value", arguments: [String(newValue)], sheetWindow: view.window)
      sender.integerValue = Preference.integer(for: .toneMappingTargetPeak)
      return
    }
    Preference.set(newValue, for: .toneMappingTargetPeak)
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                             change: [NSKeyValueChangeKey : Any]?,
                             context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath else { return }
    switch keyPath {
    case PK.audioDriverEnableAVFoundation.rawValue:
      updateAudioDevicePopUp()
    default:
      return
    }
  }

  @IBAction func toneMappingHelpAction(_ sender: Any) {
    NSWorkspace.shared.open(URL(string: AppData.toneMappingHelpLink)!)
  }

  @IBAction func targetPeakHelpAction(_ sender: Any) {
    NSWorkspace.shared.open(URL(string: AppData.targetPeakHelpLink)!)
  }

  @IBAction func algorithmHelpAction(_ sender: Any) {
    NSWorkspace.shared.open(URL(string: AppData.algorithmHelpLink)!)
  }

  @IBAction func gainAdjustmentHelpAction(_ sender: Any) {
    NSWorkspace.shared.open(URL(string: AppData.gainAdjustmentHelpLink)!)
  }

  @IBAction func audioDriverHelpAction(_ sender: Any) {
    NSWorkspace.shared.open(URL(string: AppData.audioDriverHellpLink)!)
  }
}
