//
//  SettingsPageGeneral.swift
//  iina
//
//  Created by Hechen Li on 6/22/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

class SettingsPageGeneral: SettingsPage {
  override var localizationTable: String {
    "SettingsGeneralLocalizable"
  }

  override func content() -> NSView {
    let views: [NSView] = sectionBehavior()
    + sectionHistory()
    + sectionPlayList()
    + sectionScreenshots()

    let stackView = NSStackView(views: views)
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .vertical
    stackView.spacing = 16
    views.forEach {
      $0.padding(.horizontal)
      stackView.setVisibilityPriority(.mustHold, for: $0)
    }
    return stackView
  }

  private func sectionBehavior() -> [NSView] {
    return [
      SettingsListView(title: "Behavior", [
        SettingsItem.PopupButton()
          .image(name: "restart.circle")
          .bindTo(.actionAfterLaunch, ofType: Preference.ActionAfterLaunch.self),
        SettingsItem.General(title: .text_WhenMediaIsOpened)
          .withExpandingDetailView(SettingsSubListView([
            SettingsItem.Switch()
              .bindTo(.pauseWhenOpen),
            SettingsItem.Switch()
              .bindTo(.fullScreenWhenOpen),
          ])),
        SettingsItem.General(title: .text_PauseresumeWhen)
          .withExpandingDetailView(SettingsSubListView([
            SettingsItem.Switch()
              .bindTo(.pauseWhenMinimized),
            SettingsItem.Switch()
              .bindTo(.pauseWhenInactive),
            SettingsItem.Switch()
              .bindTo(.playWhenEnteringFullScreen),
            SettingsItem.Switch()
              .bindTo(.pauseWhenLeavingFullScreen),
            SettingsItem.Switch()
              .bindTo(.pauseWhenGoesToSleep),
          ])),
      ]).container,

      SettingsListView([
        SettingsItem.Switch()
          .image(name: "macwindow.badge.plus")
          .bindTo(.alwaysOpenInNewWindow),
        SettingsItem.Switch()
          .bindTo(.quitWhenNoOpenedWindow),
        SettingsItem.Switch()
          .bindTo(.keepOpenOnFileEnd),
      ]).container,

      SettingsListView([
        SettingsItem.Switch()
          .image(name: "rectangle.expand.diagonal")
          .bindTo(.useLegacyFullScreen),
        SettingsItem.Switch()
          .image(name: "lock.display")
          .bindTo(.blackOutMonitor),
        SettingsItem.Switch()
          .bindTo(.preventScreenSaver)
          .withDetailView(SettingsSubListView([
            SettingsItem.Switch()
              .hasDescription()
              .bindTo(.allowScreenSaverForAudio)
          ]))
      ]).container,

      SettingsListView([
        SettingsItem.Switch()
          .image(name: "music.note.list")
          .bindTo(.autoSwitchToMusicMode),
      ]).container,

      SettingsListView([
        SettingsItem.SwitchWithPopupButton(title: .text_CheckForUpdates)
          .image(name: "arrowshape.up.circle")
          .bindSwitchToCustom {
            $0.bind(.value, to: NSApplication.shared, withKeyPath: "delegate.updaterController.updater.automaticallyChecksForUpdates")
          }
          .bindPopupToCustom(type: Preference.SparkleInterval.self) {
            $0.bind(.selectedTag, to: NSApplication.shared, withKeyPath: "delegate.updaterController.updater.updateCheckInterval")
          }
          .withDetailView(SettingsSubListView([
            SettingsItem.Switch()
              .bindTo(.receiveBetaUpdate),
          ])),
      ]).container,
    ]
  }

  private func sectionHistory() -> [NSView] {
    return [
      SettingsListView(title: "History", [
        SettingsItem.Switch()
          .image(name: "timer")
          .bindTo(.resumeLastPosition),
        SettingsItem.Switch()
          .image(name: "list.clipboard")
          .bindTo(.recordPlaybackHistory),
        SettingsItem.Switch()
          .image(name: "menucard")
          .bindTo(.recordRecentFiles)
          .withDetailView(SettingsSubListView([
            SettingsItem.Switch()
              .hasDescription()
              .bindTo(.trackAllFilesInRecentOpenMenu)
          ]))
      ]).container
    ]
  }

  private func sectionPlayList() -> [NSView] {
    return [
      SettingsListView(title: "Playlist", [
        SettingsItem.Switch()
          .image(name: "list.and.film")
          .bindTo(.playlistAutoAdd),
        SettingsItem.Switch()
          .image(name: "play.circle")
          .bindTo(.playlistAutoPlayNext),
        SettingsItem.Switch()
          .image(name: "music.microphone")
          .bindTo(.playlistShowMetadata)
          .withDetailView(SettingsSubListView([
            SettingsItem.Switch()
              .bindTo(.playlistShowMetadataInMusicMode)
          ])),
        SettingsItem.SwitchWithPopupButton()
          .image(name: "repeat")
          .labelKey(.autoRepeat)
          .bindSwitchTo(.autoRepeat)
          .bindPopupTo(.defaultRepeatMode, ofType: Preference.DefaultRepeatMode.self)
      ]).container
    ]
  }

  private func sectionScreenshots() -> [NSView] {
    return [
      SettingsListView(title: "Screenshots", [
        SettingsItem.Switch()
          .image(name: "camera.on.rectangle")
          .bindTo(.screenshotSaveToFile),
        SettingsItem.PopupButton()
          .bindTo(.screenshotFormat, ofType: Preference.ScreenshotFormat.self),
        SettingsItem.Switch()
          .bindTo(.screenshotCopyToClipboard),
        SettingsItem.Switch()
          .image(name: "captions.bubble")
          .bindTo(.screenshotIncludeSubtitle),
        SettingsItem.Switch()
          .image(name: "photo.on.rectangle.angled")
          .bindTo(.screenshotShowPreview)
      ]).container
    ]
  }
}


fileprivate class SparkleSettingsView: NSView {
  init() {
    super.init(frame: NSRect())
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
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
