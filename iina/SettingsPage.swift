//
//  SettingsPage.swift
//  iina
//
//  Created by Hechen Li on 6/22/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Cocoa


@resultBuilder
struct SettingsViewsBuilder {
  static func buildBlock(_ components: NSView...) -> [NSView] {
    return components
  }

  static func buildBlock(_ components: [NSView]...) -> [NSView] {
    components.flatMap { $0 }
  }
}

@resultBuilder
struct SettingsItemsBuilder {
  static func buildBlock(_ components: SettingsItem.Base...) -> [SettingsItem.Base] {
    return components
  }
}

@resultBuilder
struct SettingsSubItemsBuilder {
  static func buildBlock(_ components: SettingsItem.Base...) -> [SettingsItem.Base] {
    for c in components {
      c.controlSize = .small
    }
    return components
  }
}

@resultBuilder
struct SettingsSubListBuilder {
  static func buildBlock(_ components: SettingsItem.Base...) -> SettingsSubListView {
    return SettingsSubListView(components)
  }
}

@resultBuilder
struct SettingsSectionBuilder {
  static func buildBlock(_ components: SettingsContainer...) -> [NSView] {
    return components.map { $0.getContainer() }
  }
}

protocol SettingsContainer {
  func getContainer() -> NSView
}

class SettingsPage {
  var identifier: String { "" }
  var title: String { "" }
  var localizationTable: String { "" }
  var image: NSImage { NSImage() }

  lazy var localizationContext: SettingsLocalization.Context = {
    SettingsLocalization.Context(tableName: localizationTable)
  }()

  final func getContent() -> NSView {
    let view = content()
    // inject l10n context
    SettingsLocalization.injectContext(view, localizationContext)

    let containerView = NSView()
    containerView.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(view)
    view.padding(.horizontal(4), .bottom(8), .top)
    return containerView
  }

  func content() -> NSView {
    return NSView()
  }

  final func section(@SettingsSectionBuilder _ containers: () -> [NSView]) -> [NSView] {
    return containers()
  }

  final func sections(@SettingsViewsBuilder _ sections: () -> [NSView]) -> NSStackView {
    let views: [NSView] = sections()
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

  func makeSymbol(_ name: String, fallbackImage: NSImage.Name) -> NSImage {
    guard #available(macOS 14, *) else { return NSImage(named: fallbackImage)! }
    let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .bold)
    return NSImage.findSFSymbol([name], withConfiguration: configuration)
  }
}


class SettingsListView: NSBox, SettingsContainer, WithSettingsLocalizationContext {
  var container: Container!

  var titleKey: SettingsLocalization.Key?
  var listTitle: String?
  var l10n: SettingsLocalization.Context!

  static private let SMALL_TITLE = false

  class Container: NSView, WithSettingsLocalizationContext {
    var l10n: SettingsLocalization.Context!
    let listView: SettingsListView
    var titleKey: SettingsLocalization.Key?

    init(_ listView: SettingsListView, titleKey: SettingsLocalization.Key? = nil) {
      self.listView = listView
      super.init(frame: NSRect())

      self.titleKey = titleKey
      self.translatesAutoresizingMaskIntoConstraints = false
      self.addSubview(listView)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
      if let key = titleKey {
        let title = l10n.localized(key)
        let titleField: NSTextField
        if (SMALL_TITLE) {
          titleField = NSTextField(labelWithString: title.localizedUppercase)
          titleField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .bold)
        } else {
          titleField = NSTextField(labelWithString: title)
          titleField.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        }
        titleField.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(titleField)
        titleField.padding(.top, .horizontal(8))
        titleField.textColor = NSColor.secondaryLabelColor
        listView.spacing(to: titleField, .top(SMALL_TITLE ? 8 : 12))
        listView.padding(.bottom, .horizontal(8))
      } else {
        listView.padding(.vertical, .horizontal(8))
      }
    }
  }

  init(title: SettingsLocalization.Key? = nil, _ items: [SettingsItem.Base]? = nil) {
    super.init(frame: NSRect())
    self.translatesAutoresizingMaskIntoConstraints = false

    self.titleKey = title
    self.container = Container(self, titleKey: title)
    self.titlePosition = .noTitle
    self.contentViewMargins = NSSize(width: 0, height: 0)

    if let items = items {
      addItems(items)
    }
  }

  convenience init(title: SettingsLocalization.Key? = nil, @SettingsItemsBuilder _ items: () -> [SettingsItem.Base]) {
    self.init(title: title, items())
  }

  func getContainer() -> NSView {
    return container
  }

  private func addItems(_ subItems: [SettingsItem.Base]) {
    subItems.forEach {
      self.contentView!.addSubview($0)
      $0.padding(.horizontal)
    }
    subItems.first?.padding(.top(0))
    subItems.first?.isFirstItem = true
    subItems.last?.padding(.bottom)
    subItems.last?.isLastItem = true
    zip(subItems.dropFirst(), subItems.dropLast()).forEach { (bottomItem, topItem) in
      bottomItem.spacing(to: topItem, .top)
      let separator = NSBox()
      separator.translatesAutoresizingMaskIntoConstraints = false
      separator.boxType = .separator
      separator.titlePosition = .noTitle
      self.contentView!.addSubview(separator)
      separator.padding(to: topItem, .bottom, .leading(32), .trailing)
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidMoveToWindow() {
    self.listTitle = titleKey.map(l10n.localized(_:))
  }
}


class SettingsSubListView: SettingsListView {
  static let padding: CGFloat = 28

  init(_ items: [SettingsItem.Base]? = nil) {
    super.init(items)

    self.fillColor = .clear
    self.boxType = .custom
    self.borderWidth = 0

    let separator = NSBox()
    separator.translatesAutoresizingMaskIntoConstraints = false
    separator.boxType = .separator
    separator.titlePosition = .noTitle
    self.contentView!.addSubview(separator)
    separator.padding(.top, .leading(32), .trailing)

    items?.forEach { $0.controlSize = .small }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

