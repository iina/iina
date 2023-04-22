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

  var preferenceTabTitle: String {
    view.layoutSubtreeIfNeeded()
    return NSLocalizedString("preference.advanced", comment: "Advanced")
  }

  var preferenceTabImage: NSImage {
    return NSImage(named: NSImage.Name("pref_advanced"))!
  }

  var preferenceContentIsScrollable: Bool {
    return false
  }

  var hasResizableWidth: Bool = false

  var options: [[String]] = []

  override var sectionViews: [NSView] {
    return [headerView, loggingSettingsView, mpvSettingsView]
  }

  @IBOutlet var headerView: NSView!
  @IBOutlet var loggingSettingsView: NSView!
  @IBOutlet var mpvSettingsView: NSView!

  @IBOutlet weak var enableAdvancedSettingsBtn: Switch!
  @IBOutlet weak var optionsTableView: NSTableView!
  @IBOutlet weak var useAnotherConfigDirBtn: NSButton!
  @IBOutlet weak var chooseConfigDirBtn: NSButton!
  @IBOutlet weak var removeButton: NSButton!

  override func viewDidLoad() {
    super.viewDidLoad()

    guard let op = Preference.value(for: .userOptions) as? [[String]] else {
      Utility.showAlert("extra_option.cannot_read", sheetWindow: view.window)
      return
    }
    options = op

    optionsTableView.dataSource = self
    optionsTableView.delegate = self
    optionsTableView.sizeLastColumnToFit()
    AccessibilityPreferences.adjustElasticityInSuperviews(optionsTableView)
    removeButton.isEnabled = false

    enableAdvancedSettingsBtn.checked = Preference.bool(for: .enableAdvancedSettings)
    enableAdvancedSettingsBtn.action = {
      Preference.set($0, for: .enableAdvancedSettings)
    }
  }

  func saveToUserDefaults() {
    Preference.set(options, for: .userOptions)
    UserDefaults.standard.synchronize()
  }

  // MARK: - IBAction

  @IBAction func openLogDir(_ sender: AnyObject) {
    NSWorkspace.shared.open(Logger.logDirectory)
  }
  
  @IBAction func showLogWindow(_ sender: AnyObject) {
    (NSApp.delegate as! AppDelegate).logWindow.showWindow(self)
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
    NSWorkspace.shared.open(URL(string: AppData.wikiLink)!.appendingPathComponent("MPV-Options-and-Properties"))
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
      Utility.showAlert("extra_option.empty", sheetWindow: view.window)
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
