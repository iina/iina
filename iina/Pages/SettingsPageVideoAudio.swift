//
//  SettingsPageVideoAudio.swift
//  iina
//
//  Created by Hechen Li on 6/15/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Foundation

class SettingsPageVideoAudio: SettingsPage {
  private lazy var audioOutputDeviceView: AudioOutputDeviceView = AudioOutputDeviceView(l10n: localizationContext)

  override var title: String {
    return NSLocalizedString("preference.video_audio", comment: "Codec")
  }

  override var image: NSImage {
    return makeSymbol("play.rectangle.on.rectangle", fallbackImage: "pref_av")
  }

  override var localizationTable: String {
    "SettingsVideoAudioLocalizable"
  }

  override func content() -> NSView {
    return sections {
      sectionVideo()
      sectionAudio()
      sectionReplayGain()
    }
  }

  private func sectionVideo() -> [NSView] {
    return section {
      SettingsListView(title: .text_Video) {
        SettingsItem.Input()
          .image(name: "number")
          .bindTo(.videoThreads)
          .hasDescription()
        SettingsItem.General(title: .text_HardwareDecoder)
          .image(name: "cpu")
          .withDetailView(
            SettingsAccessory.Selection()
              .bindTo(.hardwareDecoder, ofType: Preference.HardwareDecoderOption.self)
          )
        SettingsItem.Switch()
          .bindTo(.forceDedicatedGPU)
          .hasDescription()
      }

      SettingsListView {
        SettingsItem.Switch()
          .image(name: ["document.badge.gearshape", "doc.badge.gearshape"])
          .bindTo(.loadIccProfile)
          .hasDescription()
      }

      SettingsListView {
        SettingsItem.Switch()
          .image(name: ["sun.lefthalf.filled", "sun.max"])
          .bindTo(.enableHdrSupport)
          .hasDescription()
        SettingsItem.Switch()
          .image(name: "chart.xyaxis.line")
          .bindTo(.enableToneMapping)
          .withHelpLink(AppData.toneMappingHelpLink)
          .withDetailView {
            SettingsItem.Input()
              .bindTo(.toneMappingTargetPeak)
              .trailingLabel(.text_nits)
              .hasDescription()
              .withHelpLink(AppData.targetPeakHelpLink)
            SettingsItem.PopupButton()
              .bindTo(.toneMappingAlgorithm, ofType: Preference.ToneMappingAlgorithmOption.self)
              .withHelpLink(AppData.algorithmHelpLink)
          }
      }
    }
  }

  private func sectionAudio() -> [NSView] {
    return section {
      SettingsListView(title: .text_Audio) {
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
        SettingsItem.Input(title: .videoThreadsLabel)
          .image(name: "number")
          .bindTo(.audioThreads)
          .hasDescription(content: .videoThreadsDesc)
      }

      SettingsListView {
        SettingsItem.SwitchWithInput()
          .image(name: "speaker.wave.3")
          .labelKey(.enableInitialVolume)
          .bindInputTo(.initialVolume)
          .bindSwitchTo(.enableInitialVolume)
        SettingsItem.Input()
          .bindTo(.maxVolume)
          .hasDescription()
      }

      SettingsListView {
        SettingsItem.General(title: .text_PreferredAudioDevice)
          .image(name: "hifispeaker.and.homepod")
          .withDetailView(audioOutputDeviceView.view)
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

      SettingsListView {
        SettingsItem.General(title: .text_PreferredLanguage)
          .image(name: "character.book.closed")
          .withDetailView(
            SettingsAccessory.LanguageSelector()
              .bind(to: .audioLanguage)
          )
      }
    }
  }

  private func sectionReplayGain() -> [NSView] {
    return section {
      SettingsListView(title: .text_ReplayGain) {
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


fileprivate class AudioOutputDeviceView: WithSettingsLocalizationContext {
  var l10n: SettingsLocalization.Context!
  lazy var ui: SettingsUIHelper = SettingsUIHelper(l10n)

  let view: NSView
  let audioDevicePopUp: NSPopUpButton

  init(l10n: SettingsLocalization.Context) {
    self.l10n = l10n
    self.view = NSView()
    self.audioDevicePopUp = NSPopUpButton()

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
    audioDevicePopUp.padding(.top(-4), .bottom(8), .leading(SettingsSubListView.padding), .trailing(8))
  }

  @objc func audioDeviceAction(_ sender: Any) {
    let device = audioDevicePopUp.selectedItem!.representedObject as! MPVAudioDevice
    Preference.set(device.name, for: .audioDevice)
    Preference.set(device.desc, for: .audioDeviceDesc)
  }
}
