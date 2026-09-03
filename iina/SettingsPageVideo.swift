//
//  SettingsPageVideo.swift
//  iina
//
//  Created by Hechen Li on 6/15/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Foundation

class SettingsPageVideo: SettingsPage {
  override var identifier: String {
    "video"
  }

  override var title: String {
    return NSLocalizedString("sidebar.video", comment: "Video")
  }

  override var image: NSImage {
    return .sf("photo.tv", withConfiguration: symbolConfiguration)!
  }

  override var localizationTable: String {
    "SettingsVideoLocalizable"
  }

  override func content() -> [SettingsSection] {
    return sections {
      sectionDecoding()
      if Preference.isLiveTextAvailable {
        sectionLiveText()
      }
      sectionColor()
    }
  }

  private func sectionDecoding() -> SettingsSection {
    return section {
      SettingsList(title: .text_Decoding) {
        SettingsItem.Input()
          .image(name: "number")
          .bindTo(.videoThreads)
          .range(0...Double(Int.max))
          .hasDescription()
        SettingsItem.General(title: .hardwareDecoderLabel)
          .image(name: "cpu")
          .withDetailView(
            SettingsAccessory.Selection()
              .bindTo(.hardwareDecoder, ofType: Preference.HardwareDecoderOption.self)
          )
        SettingsItem.Switch()
          .bindTo(.forceDedicatedGPU)
          .hasDescription()
      }
    }
  }

  private func sectionLiveText() -> SettingsSection {
    return section {
      SettingsList(title: .text_LiveText) {
        SettingsItem.Switch()
          .image(name: "text.viewfinder")
          .bindTo(.enableLiveText)
          .hasDescription()
      }
    }
  }

  private func sectionColor() -> SettingsSection {
    return section {
      SettingsList(title: .text_ColorHDR) {
        SettingsItem.Switch()
          .image(name: ["document.badge.gearshape", "doc.badge.gearshape"])
          .bindTo(.loadIccProfile)
          .hasDescription()
      }

      SettingsList {
        SettingsItem.Switch()
          .image(name: ["sun.lefthalf.filled", "sun.max"])
          .bindTo(.enableHdrSupport)
          .hasDescription()
      }

      SettingsList {
        SettingsItem.Switch()
          .image(name: "chart.xyaxis.line")
          .bindTo(.enableToneMapping)
          .withHelpLink(AppData.toneMappingHelpLink)
          .withDetailView {
            SettingsItem.SwitchWithInput()
              .labelKey(.toneMappingTargetPeak)
              .bindInputTo(.toneMappingTargetPeakOverride)
              .bindSwitchTo(.enableToneMappingTargetPeakOverride)
              .range(10...10000)  // mpv option is "auto" or 10...10000.
              .trailingLabel(.text_nits)
              .hasDescription()
              .withHelpLink(AppData.mpvManualLink.appending("/#options-target-peak"))
            SettingsItem.PopupButton()
              .bindTo(.toneMappingAlgorithm, ofType: Preference.ToneMappingAlgorithmOption.self)
              .withHelpLink(AppData.mpvManualLink.appending("/#options-tone-mapping"))
          }
      }
    }
  }
}
