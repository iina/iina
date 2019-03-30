//
//  FontPickerWindowController.swift
//  iina
//
//  Created by lhc on 25/10/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class FontPickerWindowController: NSWindowController, NSTableViewDelegate, NSTableViewDataSource, NSTextFieldDelegate, NSControlTextEditingDelegate {

  struct FontInfo {
    var name: String
    var localizedName: String
  }

  @IBOutlet weak var familyTableView: NSTableView!
  @IBOutlet weak var faceTableView: NSTableView!
  @IBOutlet weak var previewField: NSTextField!
  @IBOutlet weak var searchField: NSTextField!
  @IBOutlet weak var otherField: NSTextField!

  var fontNames: [FontInfo] = []
  var filteredFontNames: [FontInfo] = []
  var isSearching = false
  var chosenFontMembers: [[Any]]?
  var chosenFamily: FontInfo?
  var chosenFace: String?

  var finishedPicking: ((String?) -> Void)?

  override var windowNibName: NSNib.Name {
    get {
      return NSNib.Name("FontPickerWindowController")
    }
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
    searchField.delegate = self
  }

  // - MARK: NSTableView delegate and data source

  func numberOfRows(in tableView: NSTableView) -> Int {
    if tableView == familyTableView {
      return isSearching ? filteredFontNames.count : fontNames.count
    } else if tableView == faceTableView {
      return chosenFontMembers?.count ?? 0
    } else {
      return 0
    }
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    if tableView == familyTableView {
      return isSearching ? filteredFontNames[row].localizedName : fontNames[row].localizedName
    } else if tableView == faceTableView {
      let face = chosenFontMembers?[row]
      return face?[1]
    } else {
      return 0
    }
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard let activeTv = notification.object as? NSTableView else { return }
    if activeTv == familyTableView {
      guard familyTableView.selectedRow >= 0 else { return }
      chosenFamily = isSearching ? filteredFontNames[familyTableView.selectedRow] : fontNames[familyTableView.selectedRow]
      if chosenFamily != nil {
        chosenFontMembers = FixedFontManager.typefaces(forFontFamily: chosenFamily!.name) as? [[Any]]
        faceTableView.reloadData()
        faceTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        updatePreview()
      }
    } else if activeTv == faceTableView {
      updatePreview()
    }
  }

  // - MARK: NSTextField delegate

  func controlTextDidChange(_ obj: Notification) {
    familyTableView.deselectAll(searchField)
    let str = searchField.stringValue
    if str.isEmpty {
      isSearching = false
      familyTableView.reloadData()
      faceTableView.reloadData()
    } else {
      isSearching = true
      filteredFontNames = fontNames.filter { $0.localizedName.lowercased().contains(str.lowercased()) }
      chosenFontMembers = nil
      familyTableView.reloadData()
      faceTableView.reloadData()
    }
  }

  @IBAction func okBtnPressed(_ sender: AnyObject) {
    if let block = finishedPicking {
      let otherString = otherField.stringValue
      if otherString.isEmpty {
        block(chosenFace)
      } else {
        block(otherString)
      }
      // remove the listener
      finishedPicking = nil
    }
    self.close()
  }

  @IBAction func cancelBtnPressed(_ sender: AnyObject) {
    self.close()
  }


  // - MARK: Utils

  private func updatePreview() {
    guard chosenFontMembers != nil else { return }
    chosenFace = (chosenFontMembers![faceTableView.selectedRow][0] as? String) ?? ""
    previewField.font = NSFont(name: chosenFace!, size: 24) ?? NSFont.systemFont(ofSize: 24)
  }

  private func withAllTableViews (_ block: (NSTableView) -> Void) {
    block(familyTableView)
    block(faceTableView)
  }

}
