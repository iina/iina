//
//  SettingsPageOSD.swift
//  iina
//
//  SPEC mpv-config-driven-refactor Phase 7: OSD options.
//

import Foundation

class SettingsPageOSD: SettingsPage {
  override var identifier: String {
    "osd"
  }

  override var title: String {
    return NSLocalizedString("preference.osd", comment: "OSD")
  }

  override var image: NSImage {
    return .sf("text.bubble", withConfiguration: symbolConfiguration)!
  }

  override var localizationTable: String {
    "SettingsOSDLocalizable"
  }

  override func content() -> [SettingsSection] {
    return sections {
      sectionFont()
      sectionDisplay()
      sectionBar()
    }
  }

  private func sectionFont() -> SettingsSection {
    return section {
      SettingsList(title: .text_OSDFont) {
        SettingsItem.LongInput()
          .image(name: ["textformat"])
          .bindTo(.osdFont)
          .mpvName("osd-font")
          .hasDescription()
      }
    }
  }

  private func sectionDisplay() -> SettingsSection {
    return section {
      SettingsList(title: .text_OSDDisplay) {
        SettingsItem.Input(title: .osdFontSizeLabel)
          .bindTo(.osdFontSize)
          .mpvName("osd-font-size")
          .hasDescription()
        SettingsItem.Input(title: .osdDurationLabel)
          .bindTo(.osdDuration)
          .mpvName("osd-duration")
          .hasDescription()
        SettingsItem.Input(title: .osdPlayingMsgDurationLabel)
          .bindTo(.osdPlayingMsgDuration)
          .mpvName("osd-playing-msg-duration")
          .hasDescription()
        SettingsItem.LongInput()
          .bindTo(.osdPlayingMsg)
          .mpvName("osd-playing-msg")
          .hasDescription()
        SettingsItem.LongInput()
          .bindTo(.osdOnSeek)
          .mpvName("osd-on-seek")
          .hasDescription()
        SettingsItem.PopupButton()
          .bindTo(.osc, ofType: Preference.OscOption.self)
          .mpvName("osc")
          .hasDescription()
      }
    }
  }

  private func sectionBar() -> SettingsSection {
    return section {
      SettingsList(title: .text_OSDBar) {
        SettingsItem.Input(title: .osdBarHLabel)
          .bindTo(.osdBarH)
          .mpvName("osd-bar-h")
          .hasDescription()
        SettingsItem.Input(title: .osdBarBorderSizeLabel)
          .bindTo(.osdBarBorderSize)
          .mpvName("osd-bar-border-size")
          .hasDescription()
        SettingsItem.Input(title: .osdBorderSizeLabel)
          .bindTo(.osdBorderSize)
          .mpvName("osd-border-size")
          .hasDescription()
        SettingsItem.Switch(title: .osdFractionsLabel)
          .bindTo(.osdFractions)
          .mpvName("osd-fractions")
      }
    }
  }
}
