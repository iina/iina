//
//  SettingsPageAudio.swift
//  iina
//
//  Created by Hechen Li on 6/15/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Foundation

class SettingsPageAudio: SettingsPage {
  private lazy var audioOutputDeviceView: AudioOutputDeviceView = AudioOutputDeviceView()

  override var identifier: String {
    "audio"
  }

  override var title: String {
    return NSLocalizedString("preference.audio", comment: "Audio")
  }

  override var image: NSImage {
    return .sf("waveform", withConfiguration: symbolConfiguration)!
  }

  override var localizationTable: String {
    "SettingsAudioLocalizable"
  }

  override func content() -> [SettingsSection] {
    return sections {
      sectionHardware()
      sectionVolume()
      sectionOther()
    }
  }

  private func sectionHardware() -> SettingsSection {
    return section {
      SettingsList(title: .text_Hardware) {
        SettingsItem.Input(title: .videoThreadsLabel)
          .image(name: "number")
          .bindTo(.audioThreads)
          .hasDescription(content: .videoThreadsDesc)
        SettingsItem.General(title: .audioDriverEnableAVFoundationLabel)
          .image(name: "waveform")
          .withHelpLink(AppData.audioDriverHellpLink)
          .withDetailView(
            SettingsAccessory.Selection()
              .bindTo(.audioDriverEnableAVFoundation, ofType: AudioDriver.self)
              .customTransformer(({ $0 == 1 }, { val in
                if let val = val as? Bool, val {
                  return 1
                }
                return 0
              }))
          )
      }

      SettingsList {
        SettingsItem.General(title: .preferredAudioDeviceLabel)
          .image(name: "hifispeaker.and.homepod")
          .withDetailView(audioOutputDeviceView)
        SettingsItem.General(title: .text_SPDIFOutput)
          .image(name: "audio.jack.stereo")
          .withExpandingDetailView {
            SettingsItem.Switch()
              .bindTo(.spdifAC3)
            SettingsItem.Switch()
              .bindTo(.spdifDTS)
            SettingsItem.Switch()
              .bindTo(.spdifDTSHD)
          }
      }
    }
  }

  private func sectionVolume() -> SettingsSection {
    return section {
      SettingsList(title: .text_Volume) {
        SettingsItem.SwitchWithInput()
          .image(name: "speaker.wave.3")
          .labelKey(.enableInitialVolume)
          .bindInputTo(.initialVolume)
          .bindSwitchTo(.enableInitialVolume)
        SettingsItem.Input()
          .bindTo(.maxVolume)
          .hasDescription()
      }

      SettingsList {
        SettingsItem.PopupButton()
          .image(name: "speaker.plus")
          .bindTo(.replayGain, ofType: Preference.ReplayGainOption.self)
          .disableSubListOnTag(0)
          .hasDescription()
          .withHelpLink(AppData.gainAdjustmentHelpLink)
          .withDetailView {
            SettingsItem.Input()
              .bindTo(.replayGainPreamp)
              .trailingLabel(.text_dB)
              .hasDescription()
            SettingsItem.Switch()
              .bindTo(.replayGainClip)
              .hasDescription()
          }
        SettingsItem.Input()
          .image(name: "square.dotted")
          .bindTo(.replayGainFallback)
          .trailingLabel(.text_dB)
          .hasDescription()
      }
    }
  }

  private func sectionOther() -> SettingsSection {
    return section {
      SettingsList(title: .text_AudioOther) {
        SettingsItem.General(title: .gaplessAudioLabel)
          .image(name: "custom.waveform.2.arrow.trianglehead.2.clockwise.rotate.90")
          .withHelpLink(AppData.gaplessAudioHelpLink)
          .withDetailView(
            SettingsAccessory.Selection()
              .bindTo(.gaplessAudio, ofType: Preference.GaplessAudioOption.self)
          )
      }

      SettingsList {
        SettingsItem.General(title: .text_PreferredLanguage)
          .image(name: "character.book.closed")
          .withDetailView(
            SettingsAccessory.LanguageSelector()
              .bind(to: .audioLanguage)
          )
      }
    }
  }
}


fileprivate enum AudioDriver: Int, InitializingFromKey, CaseIterable {
  case coreAudio = 0
  case avFoundation

  static var defaultValue = AudioDriver.coreAudio

  init?(key: Preference.Key) {
    self.init(rawValue: Preference.integer(for: key))
  }

  var description: String {
    switch self {
    case .coreAudio: "coreAudio"
    case .avFoundation: "avFoundation"
    }
  }
}


fileprivate class AudioOutputDeviceView: SettingsContainer {
  lazy var itemID = SettingsContainerUUID.next()

  let view: NSView
  let audioDevicePopUp: NSPopUpButton

  init() {
    self.view = NSView()
    self.audioDevicePopUp = NSPopUpButton()
  }

  func makeView(context: SettingsLocalization.Context) -> NSView {
    let l10n = context
    let ui = SettingsUIHelper(l10n)
    audioDevicePopUp.translatesAutoresizingMaskIntoConstraints = false
    audioDevicePopUp.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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

    audioDevicePopUp.target = self
    audioDevicePopUp.action = #selector(audioDeviceAction)

    view.addSubview(audioDevicePopUp)
    audioDevicePopUp.padding(.top(topConstraintOffset), .bottom(8), .leading(SettingsSubList.indent), .trailing(8))

    return view
  }

  @objc func audioDeviceAction(_ sender: Any) {
    let device = audioDevicePopUp.selectedItem!.representedObject as! MPVAudioDevice
    Preference.set(device.name, for: .audioDevice)
    Preference.set(device.desc, for: .audioDeviceDesc)
  }
}
