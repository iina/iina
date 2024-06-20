//
//  SettingsPage.swift
//  iina
//
//  Created by Hechen Li on 6/22/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Cocoa

class SettingsPage {
  var identifier: String { "" }
  var localizationTable: String { "" }
  var localizationContext: SettingsLocalization.Context!

  func getContent() -> NSView {
    let view = content()
    // inject l10n context
    localizationContext = SettingsLocalization.Context(tableName: localizationTable)
    SettingsLocalization.injectContext(view, localizationContext)
    return view
  }

  func content() -> NSView {
    return NSView()
  }
}


class SettingsListView: NSBox, WithSettingsLocalizationContext {
  var container: Container!

  var l10n: SettingsLocalization.Context!

  class Container: NSView {
    init(_ listView: SettingsListView) {
      super.init(frame: NSRect())

      self.translatesAutoresizingMaskIntoConstraints = false
      self.addSubview(listView)
      listView.paddingToSuperView(top: 0, leading: 8, trailing: 8)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }

  init(_ items: [SettingsItem.General]? = nil) {
    super.init(frame: NSRect())
    self.translatesAutoresizingMaskIntoConstraints = false

    self.container = Container(self)
    self.titlePosition = .noTitle
    self.contentViewMargins = NSSize(width: 0, height: 0)

    if let items = items {
      addItems(items)
    }
  }

  func addItems(_ items: [SettingsItem.General]) {
    items.forEach {
      self.contentView!.addSubview($0)
      $0.paddingToSuperView(leading: 0, trailing: 0)
    }
    items.first?.paddingToSuperView(top: 0)
    items.first?.isFirstItem = true
    items.last?.paddingToSuperView(bottom: 0)
    items.last?.isLastItem = true
    zip(items.dropFirst(), items.dropLast()).forEach { (bottomItem, topItem) in
      bottomItem.spacingTo(view: topItem, top: 0)
      let separator = NSBox()
      separator.translatesAutoresizingMaskIntoConstraints = false
      separator.boxType = .separator
      separator.titlePosition = .noTitle
      self.contentView!.addSubview(separator)
      separator.paddingToView(topItem, bottom: 0, leading: 16, trailing: 0)
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}


class SettingsSubListView: SettingsListView {
  override init(_ items: [SettingsItem.General]? = nil) {
    super.init(items)

    self.fillColor = .clear
    self.boxType = .custom
    self.borderWidth = 0

    let separator = NSBox()
    separator.translatesAutoresizingMaskIntoConstraints = false
    separator.boxType = .separator
    separator.titlePosition = .noTitle
    self.contentView!.addSubview(separator)
    separator.paddingToSuperView(top: 0, leading: 16, trailing: 0)

    items?.forEach { $0.controlSize = .small }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

