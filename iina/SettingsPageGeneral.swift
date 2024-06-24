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
    let views: [NSView] = [
      SettingsListView(title: "Behavior", [
        SettingsItem.PopupButton()
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
        SettingsItem.Switch()
          .bindTo(.alwaysOpenInNewWindow),
        SettingsItem.Switch()
          .bindTo(.quitWhenNoOpenedWindow),
        SettingsItem.Switch()
          .bindTo(.keepOpenOnFileEnd),
        SettingsItem.Switch()
          .bindTo(.resumeLastPosition),
      ]).container,
      // ====================================================
      SettingsListView([
        SettingsItem.Switch()
          .bindTo(.useLegacyFullScreen),
        SettingsItem.Switch()
          .bindTo(.blackOutMonitor),
      ]).container,
      // ====================================================
      SettingsListView([
        SettingsItem.Switch()
          .bindTo(.autoSwitchToMusicMode),
      ]).container,
    ]

    let stackView = NSStackView(views: views)
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .vertical
    views.forEach {
      $0.padding(.horizontal)
      stackView.setVisibilityPriority(.mustHold, for: $0)
    }
    return stackView
  }
}
