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
    let listView = SettingsListView([
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
    ])

    return listView.container
  }
}
