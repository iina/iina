//
//  PrefKeyBindingViewController.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

@objcMembers
class PrefKeyBindingViewController: NSViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefKeyBindingViewController")
  }

  var preferenceTabTitle: String {
    return NSLocalizedString("preference.keybindings", comment: "Keybindings")
  }

  var preferenceTabImage: NSImage {
    return NSImage(named: NSImage.Name("pref_kb"))!
  }

  var preferenceContentIsScrollable: Bool {
    return false
  }

  private var confTableState: ConfTableState {
    return ConfTableState.current
  }

  private var bindingTableState: BindingTableState {
    return BindingTableState.current
  }

  private var confTableController: ConfTableViewController? = nil
  private var bindingTableController: BindingTableViewController? = nil

  private var observers: [NSObjectProtocol] = []

  // MARK: - Outlets

  @IBOutlet weak var confTableView: EditableTableView!
  @IBOutlet weak var bindingTableView: EditableTableView!
  @IBOutlet weak var confHintLabel: NSTextField!
  @IBOutlet weak var addBindingBtn: NSButton!
  @IBOutlet weak var removeBindingBtn: NSButton!
  @IBOutlet weak var showConfFileBtn: NSButton!
  @IBOutlet weak var deleteConfFileBtn: NSButton!
  @IBOutlet weak var newConfBtn: NSButton!
  @IBOutlet weak var duplicateConfBtn: NSButton!
  @IBOutlet weak var useMediaKeysButton: NSButton!
  @IBOutlet weak var bindingSearchField: NSSearchField!

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    let bindingTableController = BindingTableViewController(bindingTableView, selectionDidChangeHandler: updateRemoveButtonEnablement)
    self.bindingTableController = bindingTableController
    confTableController = ConfTableViewController(confTableView, bindingTableController)

    if #available(macOS 10.13, *) {
      useMediaKeysButton.title = NSLocalizedString("preference.system_media_control", comment: "Use system media control")
    }

    observers.append(NotificationCenter.default.addObserver(forName: .iinaPendingUIChangeForConfTable, object: nil, queue: .main) { _ in
      self.updateEditEnabledStatus()
    })

    observers.append(NotificationCenter.default.addObserver(forName: .iinaKeyBindingSearchFieldShouldUpdate, object: nil, queue: .main) { notification in
      guard let newStringValue = notification.object as? String else {
        Logger.log("Received \(notification.name.rawValue.quoted) with invalid object: \(type(of: notification.object))", level: .error)
        return
      }
      self.bindingSearchField.stringValue = newStringValue
    })

    confTableController?.selectCurrentConfRow()
    self.updateEditEnabledStatus()
  }

  // MARK: - IBActions

  @IBAction func addBindingBtnAction(_ sender: AnyObject) {
    bindingTableController?.addNewBinding()
  }

  @IBAction func removeBindingBtnAction(_ sender: AnyObject) {
    bindingTableController?.removeSelectedBindings()
  }

  @IBAction func newConfFileAction(_ sender: AnyObject) {
    confTableController?.createNewConf()
  }

  @IBAction func duplicateConfFileAction(_ sender: AnyObject) {
    confTableController?.duplicateConf(confTableState.selectedConfName)
  }

  @IBAction func showConfFileAction(_ sender: AnyObject) {
    confTableController?.showInFinder(confTableState.selectedConfName)
  }

  @IBAction func deleteConfFileAction(_ sender: AnyObject) {
    confTableController?.deleteConf(confTableState.selectedConfName)
  }

  @IBAction func importConfBtnAction(_ sender: Any) {
    Utility.quickOpenPanel(title: "Select Config File to Import", chooseDir: false, sheetWindow: view.window, allowedFileTypes: [AppData.confFileExtension]) { url in
      guard url.isFileURL, url.lastPathComponent.hasSuffix(AppData.confFileExtension) else { return }
      self.confTableController?.importConfFiles([url.lastPathComponent])
    }
  }

  @IBAction func displayRawValueAction(_ sender: NSButton) {
    bindingTableView.reloadExistingRows(reselectRowsAfter: true)
  }

  @IBAction func openKeyBindingsHelpAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.wikiLink.appending("/Manage-Key-Bindings"))!)
  }

  @IBAction func searchAction(_ sender: NSSearchField) {
    bindingTableState.applyFilter(sender.stringValue)
  }

  // MARK: - UI

  private func updateEditEnabledStatus() {
    let isSelectedConfReadOnly = confTableState.isSelectedConfReadOnly
    Logger.log("Updating editEnabledStatus to \(!isSelectedConfReadOnly)", level: .verbose)
    [showConfFileBtn, deleteConfFileBtn, addBindingBtn].forEach { btn in
      btn.isEnabled = !isSelectedConfReadOnly
    }
    confHintLabel.stringValue = NSLocalizedString("preference.key_binding_hint_\(isSelectedConfReadOnly ? "1" : "2")", comment: "preference.key_binding_hint")

    self.updateRemoveButtonEnablement()
  }

  private func updateRemoveButtonEnablement() {
    // re-evaluate this each time either table changed selection:
    removeBindingBtn.isEnabled = !confTableState.isSelectedConfReadOnly && bindingTableView.selectedRow != -1
  }
}
