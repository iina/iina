//
//  SettingsPageControl.swift
//  iina
//
//  Created by Hechen Li on 2026-02-01.
//  Copyright © 2026 lhc. All rights reserved.
//

class SettingsPageControl: SettingsPage {
  override var identifier: String {
    "control"
  }
  
  override var title: String {
    return NSLocalizedString("preference.control", comment: "control")
  }

  override var image: NSImage {
    return .sf("computermouse", "command", withConfiguration: symbolConfiguration)!
  }

  override var localizationTable: String {
    "SettingsControlLocalizable"
  }

  private lazy var sensSeek: SliderView = .init(l10n: localizationContext, key: .relativeSeekAmount)
  private lazy var sensVolume: SliderView = .init(l10n: localizationContext, key: .volumeScrollAmount)
  private lazy var sensSpeed: SliderView = .init(l10n: localizationContext, key: .playbackSpeedScrollAmount)

  override func content() -> [SettingsSection] {
    return sections {
      sectionTrackpad()
      sectionMouse()
    }
  }

  private func sectionTrackpad() -> SettingsSection {
    return section {
      SettingsList(title: .text_Trackpad) {
        SettingsItem.PopupButton()
          .bindTo(.pinchAction, ofType: Preference.PinchAction.self)
          .image(name: "rectangle.fill")
        SettingsItem.PopupButton()
          .bindTo(.forceTouchAction, ofType: Preference.MouseClickAction.self)
          .availableTags([0, 1, 2, 3])
      }
    }
  }

  private func sectionMouse() -> SettingsSection {
    return section {
      SettingsList(title: .text_Mouse) {
        SettingsItem.PopupButton()
          .bindTo(.singleClickAction, ofType: Preference.MouseClickAction.self)
          .availableTags([0, 2, 3])
          .image(name: ["pointer.arrow.click", "cursorarrow.click"])
        SettingsItem.PopupButton()
          .bindTo(.doubleClickAction, ofType: Preference.MouseClickAction.self)
          .availableTags([0, 1, 2, 4, 5, 6])
        SettingsItem.PopupButton()
          .bindTo(.rightClickAction, ofType: Preference.MouseClickAction.self)
          .availableTags([0, 2, 3, 4, 5, 6])
        SettingsItem.PopupButton()
          .bindTo(.middleClickAction, ofType: Preference.MouseClickAction.self)
        SettingsItem.Switch()
          .bindTo(.videoViewAcceptsFirstMouse)
          .image(name: ["macwindow.and.pointer.arrow", "macwindow.and.cursorarrow"])
      }
      SettingsList {
        SettingsItem.PopupButton()
          .bindTo(.verticalScrollAction, ofType: Preference.ScrollAction.self)
          .image(name: "magicmouse.fill")
        SettingsItem.PopupButton()
          .bindTo(.horizontalScrollAction, ofType: Preference.ScrollAction.self)
      }
      SettingsList {
        SettingsItem.PopupButton()
          .bindTo(.useExactSeek, ofType: Preference.SeekOption.self)
          .image(name: ["15.arrow.trianglehead.clockwise", "goforward.15"])
          .hasDescription()
        SettingsItem.Custom()
          .view(sensSeek.view)
        SettingsItem.Custom()
          .view(sensSpeed.view)
        SettingsItem.Custom()
          .view(sensVolume.view)
      }
    }
  }
}

fileprivate class SliderView: SettingsAccessory.Base {
  init(l10n: SettingsLocalization.Context, key: Preference.Key) {
    super.init(l10n: l10n)

    let label = NSTextField(labelWithString: l10n.localized(.init("\(key.rawValue).label")))
    label.translatesAutoresizingMaskIntoConstraints = false
    let slider = NSSlider()
    slider.translatesAutoresizingMaskIntoConstraints = false

    slider.allowsTickMarkValuesOnly = true
    slider.numberOfTickMarks = 4
    slider.minValue = 1
    slider.maxValue = 4
    slider.size(width: 100)
    slider.bind(.value, to: UserDefaults.standard, withKeyPath: key.rawValue)

    view.addSubview(label)
    view.addSubview(slider)

    label.padding(.leading(SettingsSubList.indent + 8), .vertical(12))
    slider.padding(.trailing(16))
      .center(.y, with: label)
      .flexibleSpacingTo(view: label)
  }
}
