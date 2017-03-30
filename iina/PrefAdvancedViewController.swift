//
//  PrefAdvancedViewController.swift
//  iina
//
//  Created by lhc on 14/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import MASPreferences

class PrefAdvancedViewController: NSViewController, MASPreferencesViewController {

  override var nibName: String? {
    return "PrefAdvancedViewController"
  }

  override var identifier: String? {
    get {
      return "advanced"
    }
    set {
      super.identifier = newValue
    }
  }

  var toolbarItemImage: NSImage {
    return NSImage(named: NSImageNameAdvanced)!
  }

  var toolbarItemLabel: String {
    view.layoutSubtreeIfNeeded()
    return NSLocalizedString("preference.advanced", comment: "Advanced")
  }

  var hasResizableWidth: Bool = false

  var options: [[String]] = []


  @IBOutlet weak var enableSettingsBtn: NSButton!
  @IBOutlet weak var settingsView: NSView!
  @IBOutlet weak var optionsTableView: NSTableView!
  @IBOutlet weak var useAnotherConfigDirBtn: NSButton!
  @IBOutlet weak var chooseConfigDirBtn: NSButton!
  @IBOutlet weak var userConfigLocLabel: NSTextField!


  override func viewDidLoad() {
    super.viewDidLoad()
    updateControlStatus(self)

    guard let op = UserDefaults.standard.value(forKey: Preference.Key.userOptions) as? [[String]] else {
      Utility.showAlert("extra_option.cannot_read")
      return
    }
    options = op

    optionsTableView.dataSource = self
    optionsTableView.delegate = self
  }

  func saveToUserDefaults() {
    UserDefaults.standard.set(options, forKey: Preference.Key.userOptions)
    UserDefaults.standard.synchronize()
  }

  // MARK: - IBAction

  @IBAction func updateControlStatus(_ sender: AnyObject) {
    let enable = enableSettingsBtn.state == NSOnState
    settingsView.subviews.forEach { view in
      if let control = view as? NSControl {
        control.isEnabled = enable
      }
    }
  }

  @IBAction func revealLogDir(_ sender: AnyObject) {
    NSWorkspace.shared().open(Utility.logDirURL)
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
    let _ = Utility.quickOpenPanel(title: "Choose config directory", isDir: true) { url in
      UserDefaults.standard.set(url.path, forKey: Preference.Key.userDefinedConfDir)
      UserDefaults.standard.synchronize()
    }
  }

  @IBAction func helpBtnAction(_ sender: AnyObject) {
    NSWorkspace.shared().open(URL(string: AppData.websiteLink)!.appendingPathComponent("documentation"))
  }
}

extension PrefAdvancedViewController: NSTableViewDelegate, NSTableViewDataSource {

  override func controlTextDidEndEditing(_ obj: Notification) {
    saveToUserDefaults()
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    return options.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    if tableColumn?.identifier == Constants.Identifier.key {
      return options[row][0]
    } else if tableColumn?.identifier == Constants.Identifier.value {
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
    if identifier == Constants.Identifier.key {
      options[row][0] = value
    } else if identifier == Constants.Identifier.value {
      options[row][1] = value
    }
    saveToUserDefaults()
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    if optionsTableView.selectedRowIndexes.count == 0 {
      optionsTableView.reloadData()
    }
  }

}
