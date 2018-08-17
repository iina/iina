//
//  PrefAdvancedViewController.swift
//  iina
//
//  Created by lhc on 14/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

@objcMembers
class PrefAdvancedViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefAdvancedViewController")
  }

  var viewIdentifier: String = "PrefAdvancedViewController"

  var toolbarItemImage: NSImage? {
    return NSImage(named: NSImage.advancedName)!
  }

  var preferenceTabTitle: String {
    view.layoutSubtreeIfNeeded()
    return NSLocalizedString("preference.advanced", comment: "Advanced")
  }

  var hasResizableWidth: Bool = false

  var options: [[String]] = []

  override var sectionViews: [NSView] {
    return [headerView, settingsView]
  }

  @IBOutlet var headerView: NSView!
  @IBOutlet var settingsView: NSView!

  @IBOutlet weak var enableSettingsBtn: NSButton!
  @IBOutlet weak var optionsTableView: NSTableView!
  @IBOutlet weak var useAnotherConfigDirBtn: NSButton!
  @IBOutlet weak var chooseConfigDirBtn: NSButton!
  @IBOutlet weak var removeButton: NSButton!

  override func viewDidLoad() {
    super.viewDidLoad()
    updateControlStatus(self)

    guard let op = Preference.value(for: .userOptions) as? [[String]] else {
      Utility.showAlert("extra_option.cannot_read")
      return
    }
    options = op

    optionsTableView.dataSource = self
    optionsTableView.delegate = self
    removeButton.isEnabled = false
  }

  func saveToUserDefaults() {
    Preference.set(options, for: .userOptions)
    UserDefaults.standard.synchronize()
  }

  // MARK: - IBAction

  @IBAction func updateControlStatus(_ sender: AnyObject) {
    let enable = enableSettingsBtn.state == .on
    settingsView.subviews.forEach { view in
      if let control = view as? NSControl {
        control.isEnabled = enable
      }
    }
  }

  @IBAction func revealLogDir(_ sender: AnyObject) {
    NSWorkspace.shared.open(Utility.logDirURL)
  }

  @IBAction func addOptionBtnAction(_ sender: AnyObject) {
    options.append(["name", "value"])
    optionsTableView.reloadData()
    optionsTableView.selectRowIndexes(IndexSet(integer: options.count - 1), byExtendingSelection: false)
    saveToUserDefaults()
  }

  @IBAction func removeOptionBtnAction(_ sender: AnyObject) {
    if optionsTableView.selectedRow >= 0 {
      options.remove(at: optionsTableView.selectedRow)
      optionsTableView.reloadData()
      saveToUserDefaults()
    }
  }

  @IBAction func chooseDirBtnAction(_ sender: AnyObject) {
    Utility.quickOpenPanel(title: "Choose config directory", chooseDir: true, sheetWindow: view.window) { url in
      Preference.set(url.path, for: .userDefinedConfDir)
      UserDefaults.standard.synchronize()
    }
  }

  @IBAction func helpBtnAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.websiteLink)!.appendingPathComponent("documentation"))
  }
}

extension PrefAdvancedViewController: NSTableViewDelegate, NSTableViewDataSource, NSControlTextEditingDelegate {

  func controlTextDidEndEditing(_ obj: Notification) {
    saveToUserDefaults()
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    return options.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    guard options.count > row else { return nil }
    if tableColumn?.identifier == .key {
      return options[row][0]
    } else if tableColumn?.identifier == .value {
      return options[row][1]
    }
    return nil
  }

  func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
    guard let value = object as? String,
      let identifier = tableColumn?.identifier else { return }
    guard !value.isEmpty else {
      Utility.showAlert("extra_option.empty")
      return
    }
    guard options.count > row else { return }
    if identifier == .key {
      options[row][0] = value
    } else if identifier == .value {
      options[row][1] = value
    }
    saveToUserDefaults()
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    if optionsTableView.selectedRowIndexes.count == 0 {
      optionsTableView.reloadData()
    }
    removeButton.isEnabled = optionsTableView.selectedRow != -1
  }

}
