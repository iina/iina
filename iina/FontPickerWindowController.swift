//
//  FontPickerWindowController.swift
//  iina
//
//  Created by lhc on 25/10/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate let ui = UIHelper(scope: "font_picker")

class FontPickerWindowController: NSWindowController, NSTableViewDelegate, NSTableViewDataSource, NSTextFieldDelegate, NSControlTextEditingDelegate {

  struct FontInfo {
    var name: String
    var localizedName: String
  }

  let familyTableView = NSTableView()
  let faceTableView = NSTableView()
  let previewField = NSTextField()
  /// "Type to filter"
  let searchField = NSTextField()
  /// Font name manual entry
  let otherField = NSTextField()

  var fontNames: [FontInfo] = []
  var filteredFontNames: [FontInfo] = []
  var isSearching = false

  private var chosenFontMembers: [[Any]] {
    guard familyTableView.selectedRow >= 0 else { return [] }
    let chosenFamily = isSearching ? filteredFontNames[familyTableView.selectedRow] : fontNames[familyTableView.selectedRow]
    return FixedFontManager.typefaces(forFontFamily: chosenFamily.name) as? [[Any]] ?? []
  }
  private var chosenFace: String {
    let typefaceIndex = faceTableView.selectedRow
    if typefaceIndex >= 0, let face = chosenFontMembers[at: faceTableView.selectedRow]?[0] as? String {
      return face
    }
    return ""
  }

  var finishedPicking: ((String) -> Void)?

  private var enableSelectionChangeListener = true

  init() {
    let window = CommonWindow(
      contentRect: NSRect(x: 0, y: 0, width: 458, height: 496),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = ui.localized("title")
    super.init(window: window)
    setupViews()
    window.center()
    window.setFrameAutosaveName("IINAFontPickerWindow")

    let manager = NSFontManager.shared

    fontNames = manager.availableFontFamilies
      .filter { !$0.hasPrefix(".") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
      .map { FontInfo(name: $0, localizedName: manager.localizedName(forFamily: $0, face: nil)) }
      .sorted { $0.localizedName < $1.localizedName }
    withAllTableViews { tv in
      tv.dataSource = self
      tv.delegate = self
    }
    otherField.placeholderString = Constants.String.mpvDefaultFont
    searchField.delegate = self
    faceTableView.doubleAction = #selector(okBtnPressed)
    Logger.log("FontPickerWindow init done")
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupViews() {
    guard let contentView = window?.contentView else { return }

    let chooseLabel = ui.label("choose", canCompress: false)
    contentView.addSubview(chooseLabel)
    chooseLabel.padding(.top(12), .leading(12), .trailing(greaterThan: 12))

    searchField.translatesAutoresizingMaskIntoConstraints = false
    searchField.controlSize = .large
    searchField.bezelStyle = .roundedBezel
    searchField.focusRingType = .none
    searchField.placeholderString = ui.localized("filter")
    contentView.addSubview(searchField)
    searchField.padding(.horizontal(12)).spacing(.top(8), to: chooseLabel)

    let familyScrollView = makeTableScrollView(familyTableView, title: ui.localized("family"))
    let faceScrollView = makeTableScrollView(faceTableView, title: ui.localized("typeface"))
    faceTableView.allowsEmptySelection = false
    contentView.addSubview(familyScrollView)
    contentView.addSubview(faceScrollView)
    familyScrollView.padding(.leading(12)).spacing(.top(8), to: searchField).size(height: 268)
    faceScrollView.padding(.trailing(12))
    NSLayoutConstraint.activate([
      faceScrollView.leadingAnchor.constraint(equalTo: familyScrollView.trailingAnchor, constant: -1),
      faceScrollView.widthAnchor.constraint(equalTo: familyScrollView.widthAnchor),
      faceScrollView.heightAnchor.constraint(equalTo: familyScrollView.heightAnchor),
      faceScrollView.centerYAnchor.constraint(equalTo: familyScrollView.centerYAnchor)
    ])

    previewField.translatesAutoresizingMaskIntoConstraints = false
    previewField.controlSize = .large
    previewField.focusRingType = .none
    previewField.alignment = .center
    previewField.lineBreakMode = .byTruncatingTail
    previewField.font = .systemFont(ofSize: 24)
    previewField.stringValue = ui.localized("test")
    contentView.addSubview(previewField)
    previewField.padding(.horizontal(12)).spacing(.top(8), to: familyScrollView)

    let previewLabel = ui.label("preview", isSmall: true, canCompress: false)
    previewLabel.textColor = .tertiaryLabelColor
    contentView.addSubview(previewLabel)
    previewLabel.padding(.leading(20), .trailing(greaterThan: 20)).spacing(.top(12), to: familyScrollView)

    let otherLabel = ui.label("other", canCompress: false)
    contentView.addSubview(otherLabel)
    otherLabel.padding(.leading(12), .trailing(greaterThan: 12)).spacing(.top(12), to: previewField)

    otherField.translatesAutoresizingMaskIntoConstraints = false
    otherField.controlSize = .large
    otherField.focusRingType = .none
    contentView.addSubview(otherField)
    otherField.padding(.horizontal(12)).spacing(.top(8), to: otherLabel)

    let cancelBtn = ui.button("cancel", target: self, action: #selector(cancelBtnPressed(_:)))
    cancelBtn.keyEquivalent = "\u{1b}"
    let okBtn = ui.button("ok", target: self, action: #selector(okBtnPressed(_:)))
    okBtn.keyEquivalent = "\r"
    for btn in [cancelBtn, okBtn] {
      btn.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
    }
    let buttonStack = ui.hStack(align: .firstBaseline, spacing: 12, cancelBtn, okBtn)
    contentView.addSubview(buttonStack)
    buttonStack.padding(.trailing(12), .bottom(12), .leading(greaterThan: 20)).spacing(.top(16), to: otherField)
  }

  private func makeTableScrollView(_ tableView: NSTableView, title: String) -> NSScrollView {
    let column = NSTableColumn()
    column.title = title
    column.isEditable = false
    column.width = 200
    column.minWidth = 200
    column.maxWidth = 200
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    tableView.style = .plain
    tableView.rowSizeStyle = .custom
    tableView.rowHeight = 17
    tableView.intercellSpacing = NSSize(width: 3, height: 2)
    tableView.focusRingType = .none
    tableView.columnAutoresizingStyle = .noColumnAutoresizing
    tableView.allowsColumnReordering = false
    tableView.allowsMultipleSelection = false
    tableView.allowsExpansionToolTips = true

    let scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.focusRingType = .none
    scrollView.borderType = .bezelBorder
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.documentView = tableView
    return scrollView
  }

  func select(_ fontString: String ) {
    Logger.log("FontPickerWindow selecting \(fontString.quoted) (searching=\(isSearching))")

    otherField.stringValue = fontString == Constants.String.mpvDefaultFont ? "" : fontString

    updateTablesFromOtherFieldValue()
  }

  /// Updates all other UI state from the `otherField` value (i.e., the manually entered typeface name).
  private func updateTablesFromOtherFieldValue() {
    let selectedFace = otherField.stringValue
    guard !selectedFace.isEmpty else {
      // Deselect any previous table selections
      familyTableView.selectRowIndexes(IndexSet(), byExtendingSelection: false)
      faceTableView.selectRowIndexes(IndexSet(), byExtendingSelection: false)
      return
    }

    // Search for font. Unfortunately this requires checking all typefaces in the system.
    // But it's still quite fast.
    // If there is a filter string already set don't try to change it, even if this means not finding a match.
    let fontNamesDisplayed = isSearching ? filteredFontNames : fontNames
    for (familyIndex, family) in fontNamesDisplayed.enumerated() {
      guard let typefaces = FixedFontManager.typefaces(forFontFamily: family.name) as? [[Any]] else { continue }
      for (typefaceIndex, typeface) in typefaces.enumerated() {
        guard let faceName = typeface[0] as? String, faceName == selectedFace else { continue }
        enableSelectionChangeListener = false

        familyTableView.selectRowIndexes(IndexSet(integer: familyIndex), byExtendingSelection: false)
        familyTableView.scrollRowToVisible(familyIndex)

        faceTableView.reloadData()
        faceTableView.selectRowIndexes(IndexSet(integer: typefaceIndex), byExtendingSelection: false)
        faceTableView.scrollRowToVisible(typefaceIndex)

        enableSelectionChangeListener = true
        updatePreview()
        return
      }
    }
  }

  // - MARK: NSTableView delegate and data source

  func numberOfRows(in tableView: NSTableView) -> Int {
    if tableView == familyTableView {
      return isSearching ? filteredFontNames.count : fontNames.count
    } else if tableView == faceTableView {
      return chosenFontMembers.count
    } else {
      return 0
    }
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    if tableView == familyTableView {
      return isSearching ? filteredFontNames[row].localizedName : fontNames[row].localizedName
    } else if tableView == faceTableView {
      if let face = chosenFontMembers[at: row] {
        return face[1]
      }
      return nil
    } else {
      return 0
    }
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard enableSelectionChangeListener else { return }
    guard let activeTv = notification.object as? NSTableView else { return }
    if activeTv == familyTableView {
      faceTableView.reloadData()
      faceTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    if !chosenFace.isEmpty {
      otherField.stringValue = chosenFace
    }
    updatePreview()
  }

  // - MARK: NSTextField delegate

  /// Type-to-filter updates
  func controlTextDidChange(_ notification: Notification) {
    familyTableView.deselectAll(searchField)
    let str = searchField.stringValue
    if str.isEmpty {
      isSearching = false
      familyTableView.reloadData()
      faceTableView.reloadData()
    } else {
      isSearching = true
      filteredFontNames = fontNames.filter { $0.localizedName.lowercased().contains(str.lowercased()) }
      familyTableView.reloadData()
      faceTableView.reloadData()
    }
    updateTablesFromOtherFieldValue()
  }

  @objc func okBtnPressed(_ sender: AnyObject) {
    if let finishedPicking {
      let otherString = otherField.stringValue
      let selectedFont = otherString.isEmpty ? Constants.String.mpvDefaultFont : otherString
      finishedPicking(selectedFont)
      // remove the listener
      self.finishedPicking = nil
    }
    self.close()
  }

  @objc func cancelBtnPressed(_ sender: AnyObject) {
    self.close()
  }


  // - MARK: Utils

  private func updatePreview() {
    let chosenFont = NSFont(name: chosenFace, size: 24)
    if let chosenFont {
      Logger.log("Previewing chosen typeface: \(chosenFont.fontName)")
    }
    let font = chosenFont ?? NSFont.systemFont(ofSize: 24)
    previewField.font = font
  }

  private func withAllTableViews (_ block: (NSTableView) -> Void) {
    block(familyTableView)
    block(faceTableView)
  }

}
