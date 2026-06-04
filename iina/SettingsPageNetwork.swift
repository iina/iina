//
//  SettingsPageNetwork.swift
//  iina
//
//  Created by Hechen Li on 2026-01-31.
//  Copyright © 2026 lhc. All rights reserved.
//

class SettingsPageNetwork: SettingsPage {
  override var identifier: String {
    "network"
  }
  
  override var title: String {
    return NSLocalizedString("preference.network", comment: "Network")
  }

  override var image: NSImage {
    return .sf("globe", withConfiguration: symbolConfiguration)!
  }

  override var localizationTable: String {
    "SettingsNetworkLocalizable"
  }

  override func content() -> [SettingsSection] {
    return sections {
      sectionCache()
      sectionNetwork()
      sectionYTDL()
    }
  }

  private func sectionCache() -> SettingsSection {
    return section {
      SettingsList(title: .text_Cache) {
        SettingsItem.Switch()
          .image(name: ["inset.filled.topthird.middlethird.bottomthird.rectangle", ""])
          .bindTo(.enableCache)
        SettingsItem.Input()
          .bindTo(.secPrefech)
          .hasDescription()
        SettingsItem.Input()
          .bindTo(.cacheBufferSize)
          .hasDescription()
        SettingsItem.Switch()
          .image(name: "custom.progress.indicator.rectangle")
          .bindTo(.showBufferingThrobber)
        SettingsItem.Switch()
          .bindTo(.showSeekingThrobber)
      }
    }
  }

  private func sectionNetwork() -> SettingsSection {
    return section {
      SettingsList(title: .text_Network) {
        SettingsItem.LongInput()
          .bindTo(.userAgent)
          .image(name: ["person.crop.circle"])
        SettingsItem.LongInput()
          .bindTo(.httpProxy)
          .image(name: ["rectangle.connected.to.line.below"])
          .hasDescription()
        SettingsItem.PopupButton()
          .bindTo(.transportRTSPThrough, ofType: Preference.RTSPTransportation.self)
      }
    }
  }

  private func sectionYTDL() -> SettingsSection {
    return section {
      SettingsList(title: .text_YTDL) {
        SettingsItem.General(title: .text_onlineMediaPluginAdvice)
          .image(name: "puzzlepiece.extension")
          .hasDescription(content: .text_ytdlWarning)
      }
      SettingsList {
        SettingsItem.Switch()
          .bindTo(.ytdlEnabled)
          .image(name: "square.and.arrow.down")
          .withHelpLink(AppData.ytdlHelpLink)
          .withDetailView {
            SettingsItem.LongInput()
              .bindTo(.ytdlSearchPath)
              .hasDescription()
            SettingsItem.LongInput()
              .bindTo(.ytdlRawOptions)
              .hasDescription()
          }
      }
    }
  }
}

