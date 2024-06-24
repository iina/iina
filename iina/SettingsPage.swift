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

    let containerView = NSView()
    containerView.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(view)
    view.padding(.horizontal(4), .vertical)
    return containerView
  }

  func content() -> NSView {
    return NSView()
  }
}


class SettingsListView: NSBox, WithSettingsLocalizationContext {
  var container: Container!

  var listTitle: String?
  var l10n: SettingsLocalization.Context!

  class Container: NSView {
    init(_ listView: SettingsListView, title: String? = nil) {
      super.init(frame: NSRect())

      self.translatesAutoresizingMaskIntoConstraints = false
      self.addSubview(listView)
      if let title = title {
        let titleField = NSTextField(labelWithString: title.localizedUppercase)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(titleField)
        titleField.padding(.top, .horizontal(8))
        titleField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .bold)
        titleField.textColor = NSColor.secondaryLabelColor
        listView.spacing(to: titleField, .top(4))
        listView.padding(.bottom, .horizontal(8))
      } else {
        listView.padding(.vertical, .horizontal(8))
      }
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }

  init(title: String? = nil, _ items: [SettingsItem.General]? = nil) {
    super.init(frame: NSRect())
    self.translatesAutoresizingMaskIntoConstraints = false

    self.container = Container(self, title: title)
    self.listTitle = title
    self.titlePosition = .noTitle
    self.contentViewMargins = NSSize(width: 0, height: 0)

    if let items = items {
      addItems(items)
    }
  }

  func addItems(_ items: [SettingsItem.General]) {
    items.forEach {
      self.contentView!.addSubview($0)
      $0.padding(.horizontal)
    }
    items.first?.padding(.top(0))
    items.first?.isFirstItem = true
    items.last?.padding(.bottom)
    items.last?.isLastItem = true
    zip(items.dropFirst(), items.dropLast()).forEach { (bottomItem, topItem) in
      bottomItem.spacing(to: topItem, .top)
      let separator = NSBox()
      separator.translatesAutoresizingMaskIntoConstraints = false
      separator.boxType = .separator
      separator.titlePosition = .noTitle
      self.contentView!.addSubview(separator)
      separator.padding(to: topItem, .bottom, .leading(16), .trailing)
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}


class SettingsSubListView: SettingsListView {
  init(_ items: [SettingsItem.General]? = nil) {
    super.init(items)

    self.fillColor = .clear
    self.boxType = .custom
    self.borderWidth = 0

    let separator = NSBox()
    separator.translatesAutoresizingMaskIntoConstraints = false
    separator.boxType = .separator
    separator.titlePosition = .noTitle
    self.contentView!.addSubview(separator)
    separator.padding(.top, .leading(16), .trailing)

    items?.forEach { $0.controlSize = .small }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

