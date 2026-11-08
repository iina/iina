//
//  QuickSettingViewController.swift
//  iina
//
//  Created by lhc on 12/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate let ui = UIHelper.shared


extension SidebarViewController.TabType {
  static let layout = SidebarViewController.TabType(0, "layout", .sf("paintbrush.fill")!)
  static let video = SidebarViewController.TabType(1, "video", .sf("photo")!)
  static let audio = SidebarViewController.TabType(2, "audio", .sf("waveform")!)
  static let sub = SidebarViewController.TabType(3, "sub", .sf("captions.bubble.fill")!)
}


class QuickSettingViewController: SidebarViewController {
  override var sidebarType: SidebarController.ViewType {
    .settings
  }
  override var leadingPrefKey: Preference.Key {
    .sidebarSettingsDisplayAtLeading
  }

  override var allTabs: [TabType] {
    [.layout, .video, .audio, .sub]
  }
  override var defaultTab: TabType { .video }

  override func setupTabs() {
    super.setupTabs()
    tabButtonsSegmentControl.segmentDistribution = .fillEqually
    for tab in allTabs {
      let label = NSLocalizedString("sidebar.\(tab.name)", comment: tab.name)
      tabButtonsSegmentControl.setToolTip(label, forSegment: tab.tag)
    }
  }

  override func updateTabActiveStatus() {
    tabButtonsSegmentControl.selectedSegment = currentTab.tag
  }

  override func updateTabButtonSize() {
    super.updateTabButtonSize()
    for tab in allTabs {
      let label = NSLocalizedString("sidebar.\(tab.name)", comment: tab.name)
      if let image = tabButtonsSegmentControl.image(forSegment: tab.tag)?.copy() as? NSImage {
        image.accessibilityDescription = label
        tabButtonsSegmentControl.setImage(image, forSegment: tab.tag)
      }
    }
  }

  override func getTabView(for tab: SidebarViewController.TabType) -> SidebarPane {
    return switch tab {
    case .layout: SidebarLayoutPane(player: player)
    case .video: SidebarVideoPane(player: player)
    case .audio: SidebarAudioPane(player: player)
    case .sub: SidebarSubtitlesPane(player: player)
    default: fatalError()
    }
  }
}
