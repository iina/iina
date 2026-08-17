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
      sectionVR()
    }
  }

  private func sectionVR() -> SettingsSection {
    return section {
      SettingsList(title: .text_VRVideo) {
        SettingsItem.Switch()
          .image(name: ["view.3d", "cube"])
          .bindTo(.vr2dAutoDetect)
          .hasDescription()
        SettingsItem.Switch()
          .image(name: "questionmark.circle")
          .bindTo(.vr2dAggressiveDetection)
          .hasDescription()
      }

      SettingsList {
        SettingsItem.General(title: .vr2dEyeLabel)
          .image(name: "eye")
          .withDetailView(
            SettingsAccessory.Selection()
              .bindTo(.vr2dEye, ofType: Preference.VR2DEyeOption.self)
          )
      }

      SettingsList(title: .text_LookingAround) {
        SettingsItem.Input()
          .image(name: "field.of.view.wide")
          .bindTo(.vr2dStartHorizontalFov)
          .trailingLabel(.text_degrees)
          .hasDescription()
        SettingsItem.Input()
          .image(name: "hand.draw")
          .bindTo(.vr2dDragSensitivity)
          .hasDescription()
        SettingsItem.Switch()
          .image(name: "arrow.left.arrow.right")
          .bindTo(.vr2dInvertDrag)
        SettingsItem.Input()
          .image(name: "keyboard")
          .bindTo(.vr2dKeyboardStep)
          .trailingLabel(.text_degrees)
      }
    }
  }

  private func sectionDecoding() -> SettingsSection {
    return section {
      SettingsList(title: .text_Decoding) {
        SettingsItem.Input()
          .image(name: "number")
          .bindTo(.videoThreads)
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
}
