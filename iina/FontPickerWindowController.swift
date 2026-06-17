//
//  FontPickerWindowController.swift
//  iina
//
//  Created by lhc on 25/10/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import UniformTypeIdentifiers

class FontPickerWindowController: NSWindowController, NSTableViewDelegate, NSTableViewDataSource, NSTextFieldDelegate, NSControlTextEditingDelegate {

  struct FontInfo {
    var name: String
    var localizedName: String
  }

  @IBOutlet weak var familyTableView: NSTableView!
  @IBOutlet weak var faceTableView: NSTableView!
  @IBOutlet weak var previewField: NSTextField!
  /// "Type to filter"
  @IBOutlet weak var searchField: NSTextField!
  /// Font name manual entry
  @IBOutlet weak var otherField: NSTextField!

  var fontNames: [FontInfo] = []
  var filteredFontNames: [FontInfo] = []
  var isSearching = false

  /// Button that opens an `NSOpenPanel` for selecting a font *file* (`.otf` /
  /// `.ttf` / `.ttc`) from the bundled/materialized `mpv/fonts/` directory.
  /// Added programmatically to avoid fragile hand-edits to the xib.
  /// See SPEC `mpv-config-driven-refactor` Phase 6.
  private var fontFileButton: NSButton!

  private var chosenFontMembers: [[Any]] {
    guard familyTableView.selectedRow >= 0 else { return [] }
    let chosenFamily = isSearching ? filteredFontNames[familyTableView.selectedRow] : fontNames[familyTableView.selectedRow]
    return FixedFontManager.typefaces(forFontFamily: chosenFamily.name) as? [[Any]] ?? []
  }
  private var chosenFace: String {
    let typefaceIndex = faceTableView.selectedRow
    if typefaceIndex >= 0, let face = chosenFontMembers[faceTableView.selectedRow][0] as? String {
      return face
    }
    return ""
  }

  var finishedPicking: ((String) -> Void)?

  private var enableSelectionChangeListener = true

  override var windowNibName: NSNib.Name {
    get {
      return NSNib.Name("FontPickerWindowController")
    }
  }

  init() {
    super.init(window: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func windowDidLoad() {
    super.windowDidLoad()

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
    addFontFileButton()
    Logger.log("FontPickerWindow init done")
  }

  /// Adds a "Select font file…" button to the window's accessory view area
  /// that opens an `NSOpenPanel` restricted to the bundled/materialized
  /// `mpv/fonts/` directory. The selected file's basename is written to
  /// `otherField` so the existing OK path forwards it as the chosen value.
  /// See SPEC `mpv-config-driven-refactor` Phase 6 / requirement 11.
  private func addFontFileButton() {
    fontFileButton = NSButton(title: NSLocalizedString("menu.fontfile", value: "Select font file…", comment: ""), target: self, action: #selector(fontFileButtonClicked))
    fontFileButton.bezelStyle = .rounded
    fontFileButton.controlSize = .small
    fontFileButton.translatesAutoresizingMaskIntoConstraints = false
    guard let contentView = window?.contentView else { return }
    contentView.addSubview(fontFileButton)
    NSLayoutConstraint.activate([
      fontFileButton.trailingAnchor.constraint(equalTo: (otherField.superview ?? contentView).trailingAnchor, constant: 0),
      fontFileButton.bottomAnchor.constraint(equalTo: otherField.topAnchor, constant: -4),
    ])
  }

  @objc private func fontFileButtonClicked() {
    let panel = NSOpenPanel()
    panel.title = NSLocalizedString("title.fontfile", value: "Choose a font file", comment: "")
    let fontTypes: [UTType] = ["otf", "ttf", "ttc"].compactMap { UTType(filenameExtension: $0) }
    panel.allowedContentTypes = fontTypes.isEmpty ? [.font] : fontTypes
    panel.directoryURL = Utility.materializedMPVConfigDirURL.appendingPathComponent("fonts")
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.beginSheetModal(for: window!) { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      self?.otherField.stringValue = url.lastPathComponent
      self?.updatePreview()
    }
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
      let face = chosenFontMembers[row]
      return face[1]
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

  @IBAction func okBtnPressed(_ sender: AnyObject) {
    if let finishedPicking {
      let otherString = otherField.stringValue
      let selectedFont = otherString.isEmpty ? Constants.String.mpvDefaultFont : otherString
      finishedPicking(selectedFont)
      // remove the listener
      self.finishedPicking = nil
    }
    self.close()
  }

  @IBAction func cancelBtnPressed(_ sender: AnyObject) {
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
