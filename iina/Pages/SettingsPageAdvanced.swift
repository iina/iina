//
//  SettingsPageAdvanced.swift
//  iina
//
//  Created by Hechen Li on 2026-02-02.
//  Copyright © 2026 lhc. All rights reserved.
//

class SettingsPageAdvanced: SettingsPage {
  override var title: String {
    return NSLocalizedString("preference.advanced", comment: "Advanced")
  }
  
  override var image: NSImage {
    return makeSymbol("flask", fallbackImage: "pref_advanced")
  }
  
  override var localizationTable: String {
    "SettingsAdvancedLocalizable"
  }
  
  private lazy var fileChooseView: SettingsAccessory.FileChooserView = .init(.userDefinedConfDir)

  override func content() -> NSView {
    return sections {
      sectionEnableAdvanced()
      sectionLogging()
      sectionMPV()
    }
  }
  
  private func sectionEnableAdvanced() -> [NSView] {
    return section {
      SettingsListView() {
        SettingsItem.Switch()
          .bindTo(.enableAdvancedSettings)
          .image(name: ["flask"])
          .hasDescription()
          .withHelpLink(AppData.wikiLink.appending("/MPV-Options-and-Properties"))
      }
    }
  }

  private func sectionLogging() -> [NSView] {
    return section {
      SettingsListView(title: .text_Logging) {
        SettingsItem.PopupButton()
          .bindTo(.logLevel, ofType: Logger.Level.self)
          .image(name: "cylinder.split.1x2")
        SettingsItem.Switch()
          .bindTo(.enableLogging)
      }
    }
  }
  
  private func sectionMPV() -> [NSView] {
    return section {
      SettingsListView(title: .text_MPVSettings) {
        SettingsItem.Switch()
          .bindTo(.useMpvOsd)
          .image(name: "ellipsis.bubble")
      }
      SettingsListView {
        SettingsItem.Switch()
          .image(name: ["folder.badge.gearshape", "folder.badge.gear"])
          .bindTo(.useUserDefinedConfDir)
          .extraViews(fileChooseView.textField, fileChooseView.chooseButton)
      }
    }
  }
}
