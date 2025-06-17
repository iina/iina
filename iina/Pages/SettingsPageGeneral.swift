//
//  SettingsPageGeneral.swift
//  iina
//
//  Created by Hechen Li on 6/22/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

class SettingsPageGeneral: SettingsPage {
  private lazy var fileChooseView: FileChooserView = FileChooserView()

  override var title: String {
    return NSLocalizedString("preference.general", comment: "General")
  }

  override var image: NSImage {
    return makeSymbol("gear", fallbackImage: "pref_general")
  }

  override var localizationTable: String {
    "SettingsGeneralLocalizable"
  }

  override func content() -> NSView {
    return sections {
      sectionBehavior()
      sectionHistory()
      sectionPlayList()
      sectionScreenshots()
    }
  }

  private func sectionBehavior() -> [NSView] {
    return section {
      SettingsListView(title: .text_Behavior) {
        SettingsItem.PopupButton()
          .image(name: "restart.circle")
          .bindTo(.actionAfterLaunch, ofType: Preference.ActionAfterLaunch.self)
        SettingsItem.General(title: .text_WhenMediaIsOpened)
          .withExpandingDetailView {
            SettingsItem.Switch()
              .bindTo(.pauseWhenOpen)
            SettingsItem.Switch()
              .bindTo(.fullScreenWhenOpen)
          }
        SettingsItem.General(title: .text_PauseresumeWhen)
          .withExpandingDetailView {
            SettingsItem.Switch()
              .bindTo(.pauseWhenMinimized)
            SettingsItem.Switch()
              .bindTo(.pauseWhenInactive)
            SettingsItem.Switch()
              .bindTo(.playWhenEnteringFullScreen)
            SettingsItem.Switch()
              .bindTo(.pauseWhenLeavingFullScreen)
            SettingsItem.Switch()
              .bindTo(.pauseWhenGoesToSleep)
          }
      }

      SettingsListView {
        SettingsItem.Switch()
          .image(name: "macwindow.badge.plus")
          .bindTo(.alwaysOpenInNewWindow)
        SettingsItem.Switch()
          .bindTo(.quitWhenNoOpenedWindow)
        SettingsItem.Switch()
          .bindTo(.keepOpenOnFileEnd)
      }

      SettingsListView {
        SettingsItem.Switch()
          .image(name: "rectangle.expand.diagonal")
          .bindTo(.useLegacyFullScreen)
        SettingsItem.Switch()
          .image(name: "lock.display")
          .bindTo(.blackOutMonitor)
        SettingsItem.Switch()
          .bindTo(.preventScreenSaver)
          .withDetailView {
            SettingsItem.Switch()
              .hasDescription()
              .bindTo(.allowScreenSaverForAudio)
          }
      }

      SettingsListView {
        SettingsItem.Switch()
          .image(name: "music.note.list")
          .bindTo(.autoSwitchToMusicMode)
      }

      SettingsListView {
        SettingsItem.SwitchWithPopupButton(title: .text_CheckForUpdates)
          .image(name: "arrowshape.up.circle")
          .bindSwitchToCustom {
            $0.bind(.value, to: NSApplication.shared, withKeyPath: "delegate.updaterController.updater.automaticallyChecksForUpdates")
          }
          .bindPopupToCustom(type: Preference.SparkleInterval.self) {
            $0.bind(.selectedTag, to: NSApplication.shared, withKeyPath: "delegate.updaterController.updater.updateCheckInterval")
          }
          .withDetailView {
            SettingsItem.Switch()
              .bindTo(.receiveBetaUpdate)
          }
      }
    }
  }

  private func sectionHistory() -> [NSView] {
    return section {
      SettingsListView(title: .text_History) {
        SettingsItem.Switch()
          .image(name: "timer")
          .bindTo(.resumeLastPosition)
        SettingsItem.Switch()
          .image(name: "list.clipboard")
          .bindTo(.recordPlaybackHistory)
        SettingsItem.Switch()
          .image(name: "menucard")
          .bindTo(.recordRecentFiles)
          .withDetailView {
            SettingsItem.Switch()
              .hasDescription()
              .bindTo(.trackAllFilesInRecentOpenMenu)
          }
      }
    }
  }

  private func sectionPlayList() -> [NSView] {
    return section {
      SettingsListView(title: .text_Playlist) {
        SettingsItem.Switch()
          .image(name: "list.and.film")
          .bindTo(.playlistAutoAdd)
        SettingsItem.Switch()
          .image(name: "play.circle")
          .bindTo(.playlistAutoPlayNext)
        SettingsItem.Switch()
          .image(name: "music.microphone")
          .bindTo(.playlistShowMetadata)
          .withDetailView {
            SettingsItem.Switch()
              .bindTo(.playlistShowMetadataInMusicMode)
          }
        SettingsItem.SwitchWithPopupButton()
          .image(name: "repeat")
          .labelKey(.autoRepeat)
          .bindSwitchTo(.autoRepeat)
          .bindPopupTo(.defaultRepeatMode, ofType: Preference.DefaultRepeatMode.self)
      }
    }
  }

  private func sectionScreenshots() -> [NSView] {
    return section {
      SettingsListView(title: .text_Screenshots) {
        SettingsItem.Switch()
          .image(name: "camera.on.rectangle")
          .bindTo(.screenshotSaveToFile)
          .extraViews(fileChooseView.textField, fileChooseView.chooseButton)
        SettingsItem.PopupButton()
          .bindTo(.screenshotFormat, ofType: Preference.ScreenshotFormat.self)
        SettingsItem.Switch()
          .image(name: "list.clipboard")
          .bindTo(.screenshotCopyToClipboard)
        SettingsItem.Switch()
          .image(name: "captions.bubble")
          .bindTo(.screenshotIncludeSubtitle)
        SettingsItem.Switch()
          .image(name: "photo.on.rectangle.angled")
          .bindTo(.screenshotShowPreview)
      }
    }
  }
}


fileprivate class FileChooserView {
  var textField: NSTextField
  var chooseButton: NSButton

  init() {
    textField = NSTextField(labelWithString: "")
    textField.bind(.value, to: UserDefaults.standard, withKeyPath: Preference.Key.screenshotFolder.rawValue)
    chooseButton = NSButton()
    chooseButton.image = .init(systemSymbolName: "folder.fill", accessibilityDescription: nil)!
    chooseButton.target = self
    chooseButton.action = #selector(chooseFolder)
  }

  @objc func chooseFolder(_ sender: AnyObject) {
    Utility.quickOpenPanel(title: "Choose screenshot save path", chooseDir: true, sheetWindow: chooseButton.window) { url in
      Preference.set(url.path, for: .screenshotFolder)
      UserDefaults.standard.synchronize()
    }
  }
}


fileprivate extension Preference {
  enum SparkleInterval: Int, InitializingFromKey, CaseIterable {
    case hourly = 3600
    case daily = 86400
    case weekly = 604800
    case monthly = 2629800

    static var defaultValue = SparkleInterval.daily

    init?(key: Preference.Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }
}
