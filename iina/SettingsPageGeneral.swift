//
//  SettingsPageGeneral.swift
//  iina
//
//  Created by Hechen Li on 6/22/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

class SettingsPageGeneral: SettingsPage {
  private lazy var fileChooseView: SettingsAccessory.FileChooserView = .init(.screenshotFolder)

  override var identifier: String {
    "general"
  }

  override var title: String {
    return NSLocalizedString("preference.general", comment: "General")
  }

  override var image: NSImage {
    return .sf("gear", withConfiguration: symbolConfiguration)!
  }

  override var localizationTable: String {
    "SettingsGeneralLocalizable"
  }

  override func content() -> [SettingsSection] {
    return sections {
      sectionBehavior()
      sectionHistory()
      sectionPlayList()
      sectionScreenshots()
    }
  }

  private func sectionBehavior() -> SettingsSection {
    return section {
      SettingsList(title: .text_Behavior) {
        SettingsItem.PopupButton()
          .image(name: "custom.menubar.rectangle.badge.sparkles")
          .bindTo(.actionAfterLaunch, ofType: Preference.ActionAfterLaunch.self)
        SettingsItem.General(title: .text_WhenMediaIsOpened)
          .image(name: "custom.document.badge.play")
          .withExpandingDetailView {
            SettingsItem.Switch()
              .bindTo(.pauseWhenOpen)
            SettingsItem.Switch()
              .bindTo(.fullScreenWhenOpen)
          }
        SettingsItem.General(title: .pauseresumeWhen)
          .image(name: "custom.playpause.arrow.trianglehead.clockwise")
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

      SettingsList {
        SettingsItem.Switch()
          .image(name: "macwindow.on.rectangle")
          .bindTo(.alwaysOpenInNewWindow)
          .withDetailView {
            SettingsItem.Switch()
              .bindTo(.groupSimultaneousOpensInPlaylist)
            SettingsItem.Switch()
              .bindTo(.allowDuplicatePlayers)
          }
        SettingsItem.Switch()
          .image(name: "custom.macwindow.badge.xmark")
          .bindTo(.quitWhenNoOpenedWindow)
        SettingsItem.Switch()
          .image(name: "custom.macwindow.badge.pause")
          .bindTo(.keepOpenOnFileEnd)
      }

      SettingsList {
        SettingsItem.Switch()
          .image(name: ["arrow.up.left.and.arrow.down.right.rectangle", "rectangle.expand.diagonal"])
          .bindTo(.useLegacyFullScreen)
        SettingsItem.Switch()
          .image(name: "lock.display")
          .bindTo(.blackOutMonitor)
        SettingsItem.Switch()
          .image(name: "custom.photo.tv.slash")
          .bindTo(.preventScreenSaver)
          .withDetailView {
            SettingsItem.Switch()
              .hasDescription()
              .bindTo(.allowScreenSaverForAudio)
          }
      }

      SettingsList {
        SettingsItem.Switch()
          .image(name: "music.note.list")
          .bindTo(.autoSwitchToMusicMode)
      }

      SettingsList {
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

  private func sectionHistory() -> SettingsSection {
    return section {
      SettingsList(title: .text_History) {
        SettingsItem.Switch()
          .image(name: "custom.arrow.clockwise.badge.clock")
          .bindTo(.resumeLastPosition)
        SettingsItem.Switch()
          .image(name: "custom.play.rectangle.badge.clock")
          .bindTo(.recordPlaybackHistory)
        SettingsItem.Switch()
          .image(name: "custom.filemenu.and.selection.badge.clock")
          .bindTo(.recordRecentFiles)
          .withDetailView {
            SettingsItem.Switch()
              .hasDescription()
              .bindTo(.trackAllFilesInRecentOpenMenu)
          }
      }
    }
  }

  private func sectionPlayList() -> SettingsSection {
    return section {
      SettingsList(title: .text_Playlist) {
        SettingsItem.Switch()
          .image(name: "custom.list.bullet.badge.plus")
          .bindTo(.playlistAutoAdd)
        SettingsItem.Switch()
          .image(name: "custom.list.bullet.badge.play")
          .bindTo(.playlistAutoPlayNext)
        SettingsItem.Switch()
          .image(name: "custom.music.microphone.badge.person.crop")
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

  private func sectionScreenshots() -> SettingsSection {
    return section {
      SettingsList(title: .text_Screenshots) {
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
          .image(name: "custom.photo.badge.eye")
          .bindTo(.screenshotShowPreview)
      }
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

    var description: String {
      switch self {
      case .hourly: "hourly"
      case .daily: "daily"
      case .weekly: "weekly"
      case .monthly: "monthly"
      }
    }
  }
}
