//
//  SettingsPage.swift
//  iina
//
//  Created by Hechen Li on 6/22/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Cocoa


protocol SettingsContainer {
  var itemID: Int { get }
  func makeView(context: SettingsLocalization.Context) -> NSView
  func getChildren() -> [any SettingsContainer]
  func registerSearchEntry(context: SettingsSearch.Context)
}

extension SettingsContainer {
  func getChildren() -> [any SettingsContainer] { [] }
  func registerSearchEntry(context: SettingsSearch.Context) { }

  func find(where predicate: (any SettingsContainer) -> Bool) -> SettingsContainer? {
    if predicate(self) {
      return self
    }
    for item in getChildren() {
      if let res = item.find(where: predicate) {
        return res
      }
    }
    return nil
  }
}


enum SettingsContainerUUID {
  static private var counter: Int = 70000
  static func next() -> Int {
    counter += 1
    return counter
  }
}


class SettingsView: NSView {
  private var tag_: Int

  override var tag: Int {
    get { tag_ }
    set { tag_ = newValue }
  }

  init(tag: Int) {
    self.tag_ = tag
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}


@resultBuilder
struct SettingsViewsBuilder {
  static func buildBlock(_ components: SettingsSection...) -> [SettingsSection] {
    return components
  }

  static func buildBlock(_ components: [SettingsSection]...) -> [SettingsSection] {
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
    for component in components {
      component.controlSize = .small
    }
    return components
  }
}

@resultBuilder
struct SettingsSubListBuilder {
  static func buildBlock(_ components: SettingsItem.Base...) -> SettingsSubList {
    return SettingsSubList(components)
  }
}

@resultBuilder
struct SettingsSectionBuilder {
  static func buildBlock(_ components: SettingsContainer...) -> [SettingsContainer] {
    return components
  }
}


class SettingsPage {
  var identifier: String { "" }
  var title: String { "" }
  var localizationTable: String { "" }
  var image: NSImage { NSImage() }
  var sectionSpacing: CGFloat { 16 }

  let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .bold)

  static var corderRadius: CGFloat = {
    if #available(macOS 26, *) {
      12
    } else {
      4
    }
  }()

  lazy var localizationContext: SettingsLocalization.Context = {
    SettingsLocalization.Context(tableName: localizationTable)
  }()

  lazy var builtSections: [SettingsSection] = {
    content()
  }()

  func pageLoaded() {}

  final func getView() -> NSView {
    let view = makeContentView()

    let containerView = NSView()
    containerView.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(view)
    view.padding(.horizontal(4), .bottom(8), .top, from: containerView)
    return containerView
  }

  func content() -> [SettingsSection] {
    return []
  }

  final func section(@SettingsSectionBuilder _ containers: () -> [SettingsContainer]) -> SettingsSection {
    SettingsSection(spacing: sectionSpacing, containers())
  }

  final func sections(@SettingsViewsBuilder _ sections: () -> [SettingsSection]) -> [SettingsSection] {
    sections()
  }

  private func makeContentView() -> NSView {
    let views = builtSections.map {
      $0.makeView(context: localizationContext)
    }
    let stackView = NSStackView(views: views)
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .vertical
    stackView.spacing = self.sectionSpacing
    views.forEach {
      $0.padding(.horizontal, from: stackView)
      stackView.setVisibilityPriority(.mustHold, for: $0)
    }
    return stackView
  }

  func registerSearchEntries() {
    let context = SettingsSearch.Context(l10n: localizationContext, page: identifier, section: nil, parent: nil)
    builtSections.forEach { $0.registerSearchEntry(context: context) }
  }
}


class SettingsSection: SettingsContainer {
  lazy var itemID = SettingsContainerUUID.next()
  let spacing: CGFloat
  var titleKey: SettingsLocalization.Key?
  let children: [SettingsContainer]

  init(titleKey: SettingsLocalization.Key? = nil, spacing: CGFloat, _ children: [SettingsContainer]) {
    self.spacing = spacing
    self.titleKey = titleKey
    self.children = children

    if self.titleKey == nil,
       let firstList = children.first as? SettingsList,
       let titleKey = firstList.titleKey
    {
      self.titleKey = titleKey
      firstList.titleKey = nil
    }
  }

  func getChildren() -> [any SettingsContainer] {
    children
  }

  func makeView(context: SettingsLocalization.Context) -> NSView {
    let view = View()
    let childViews = children.map { $0.makeView(context: context) }
    let stackView = NSStackView(views: childViews)
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .vertical
    stackView.spacing = spacing
    childViews.forEach {
      $0.padding(.horizontal, from: stackView)
      stackView.setVisibilityPriority(.mustHold, for: $0)
    }
    view.addSubview(stackView)

    if let titleKey {
      let title = context.localized(titleKey)
      view.sectionTitle = title
      let titleField = NSTextField(labelWithString: title)
      titleField.font = NSFont.systemFont(ofSize: 14, weight: .bold)
      titleField.translatesAutoresizingMaskIntoConstraints = false
      titleField.textColor = NSColor.secondaryLabelColor
      view.titleField = titleField
      view.addSubview(titleField)
      titleField.padding(.top, .leading(16), .trailing(8), from: view)
      stackView.spacing(.top(12), to: titleField).padding(.leading, .trailing, .bottom, from: view)
    } else {
      stackView.padding(.all, from: view)
    }

    return view
  }

  func registerSearchEntry(context: SettingsSearch.Context) {
    let context = context.with(section: titleKey.map { context.l10n.localized($0) })
    return children.forEach { $0.registerSearchEntry(context: context) }
  }

  class View: NSView {
    var sectionTitle: String?
    var titleField: NSTextField?
  }
}


class SettingsList: SettingsContainer {
  lazy var itemID = SettingsContainerUUID.next()
  var titleKey: SettingsLocalization.Key?
  var items: [SettingsItem.Base]
  var horizontalPadding: CGFloat { 8 }

  static private let SMALL_TITLE = false

  init(title: SettingsLocalization.Key? = nil, _ items: [SettingsItem.Base]? = nil) {
    self.titleKey = title
    self.items = items ?? []
  }

  convenience init(title: SettingsLocalization.Key? = nil, @SettingsItemsBuilder _ items: () -> [SettingsItem.Base]) {
    self.init(title: title, items())
  }

  func getChildren() -> [any SettingsContainer] {
    items
  }

  func makeView(context: SettingsLocalization.Context) -> NSView {
    let listView = makeListView(context: context)
    let container = ContainerView(listView: listView)
    container.addSubview(listView)

    guard let titleKey else {
      listView.padding(.vertical, .horizontal(horizontalPadding), from: container)
      return container
    }

    let title = context.localized(titleKey)
    let titleField = NSTextField(labelWithString: SettingsList.SMALL_TITLE ? title.localizedUppercase : title)
    titleField.font = SettingsList.SMALL_TITLE ?
      NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .bold) :
      NSFont.systemFont(ofSize: 14, weight: .bold)
    titleField.translatesAutoresizingMaskIntoConstraints = false
    titleField.textColor = NSColor.secondaryLabelColor
    container.titleField = titleField
    container.addSubview(titleField)
    titleField.padding(.top, .leading(16), .trailing(8), from: container)
    listView.spacing(.top(SettingsList.SMALL_TITLE ? 8 : 12), to: titleField)
    listView.padding(.bottom, .horizontal(8), from: container)
    return container
  }

  func registerSearchEntry(context: SettingsSearch.Context) {
    items.forEach { $0.registerSearchEntry(context: context) }
  }

  func makeListView(context: SettingsLocalization.Context) -> View {
    let listView = View()
    addItems(to: listView, context: context)
    return listView
  }

  func addItems(to listView: View, context: SettingsLocalization.Context) {
    items.forEach {
      $0.isFirstItem = false
      $0.isLastItem = false
    }
    items.first?.isFirstItem = true
    items.last?.isLastItem = true

    let itemViews = items.map { item -> NSView in
      item.makeView(context: context)
    }
    itemViews.forEach {
      listView.contentView!.addSubview($0)
      $0.padding(.horizontal, from: listView.contentView)
    }
    itemViews.first?.padding(.top(0), from: listView.contentView)
    itemViews.last?.padding(.bottom, from: listView.contentView)
    zip(itemViews.dropFirst(), itemViews.dropLast()).forEach { (bottomItem, topItem) in
      bottomItem.spacing(.top, to: topItem)
      let separator = NSBox()
      separator.translatesAutoresizingMaskIntoConstraints = false
      separator.boxType = .separator
      separator.titlePosition = .noTitle
      listView.contentView!.addSubview(separator)
      separator.padding(.bottom, .leading(36), .trailing, from: topItem)
    }
  }

  /// A container view for displaying the list with a title.
  class ContainerView: NSView {
    let listView: SettingsList.View
    var titleField: NSTextField?

    init(listView: SettingsList.View) {
      self.listView = listView
      super.init(frame: NSRect())
      self.translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }

  class View: NSBox {
    init() {
      super.init(frame: NSRect())
      self.translatesAutoresizingMaskIntoConstraints = false
      self.titlePosition = .noTitle
      self.contentViewMargins = NSSize(width: 0, height: 0)

      if #available(macOS 26, *) {
        self.boxType = .custom
        self.cornerRadius = SettingsPage.corderRadius
      }
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
      guard window != nil else { return }
      viewDidChangeEffectiveAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
      if #available(macOS 26, *) {
        if effectiveAppearance.isDark {
          self.borderColor = .separatorColor
          self.fillColor = .underPageBackgroundColor
        } else {
          self.borderColor = .black.withAlphaComponent(0.05)
          self.fillColor = .black.withAlphaComponent(0.02)
        }
      }
    }
  }
}


class SettingsSubList: SettingsList {
  static let indent: CGFloat = 28
  override var horizontalPadding: CGFloat { 0 }

  override func makeListView(context: SettingsLocalization.Context) -> View {
    items.forEach { $0.controlSize = .small }

    let listView = View()
    addItems(to: listView, context: context)

    let separator = NSBox()
    separator.translatesAutoresizingMaskIntoConstraints = false
    separator.boxType = .separator
    separator.titlePosition = .noTitle
    listView.contentView!.addSubview(separator)
    separator.padding(.top, .leading(36), .trailing, from: listView.contentView)
    return listView
  }

  class View: SettingsList.View {
    override init() {
      super.init()
      self.fillColor = .clear
      self.boxType = .custom
      self.borderWidth = 0
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
      return
    }
  }
}
