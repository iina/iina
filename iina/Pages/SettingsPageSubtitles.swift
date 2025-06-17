//
//  SettingsPageSubtitles.swift
//  iina
//
//  Created by Hechen Li on 6/16/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Foundation

class SettingsPageSubtitles: SettingsPage {
  override var title: String {
    return NSLocalizedString("preference.subtitle", comment: "Subtitles")
  }

  override var image: NSImage {
    return makeSymbol("captions.bubble", fallbackImage: "pref_sub")
  }

  override var localizationTable: String {
    "SettingsSubtitesLocalizable"
  }

  override func content() -> NSView {
    return sections {
      sectionAutoLoad()
      sectionASS()
      sectionText()
      sectionPosition()
    }
  }

  private func sectionAutoLoad() -> [NSView] {
    return section {
      SettingsListView(title: .text_AutoLoad) {
        SettingsItem.PopupButton()
          .image(name: ["bolt.badge.automatic", "bolt.badge.a"])
          .bindTo(.subAutoLoadIINA, ofType: Preference.IINAAutoLoadAction.self)
        SettingsItem.General(title: .text_Advanced)
          .withExpandingDetailView {
            SettingsItem.General(title: .text_SubtitlesHavePriorityWhenFilename)
            SettingsItem.General(title: .text_AlsoSearchSubtitlesInFollowing)
          }
      }
    }
  }

  private func sectionASS() -> [NSView] {
    return section {

    }
  }

  private func sectionText() -> [NSView] {
    return section {

    }
  }

  private func sectionPosition() -> [NSView] {
    return section {

    }
  }
}
