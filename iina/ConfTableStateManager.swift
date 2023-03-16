//
//  ConfTableStateManager.swift
//  iina
//
//  Created by Matt Svoboda on 11/16/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

fileprivate let changeSelectedConfActionName: String = "Change Active Config"

/*
 Responsible for changing the state of the Key Bindings Configuration ("Conf") table by building new versions of `ConfTableState`.
 For the most part, methods in this class should only be directly called by `ConfTableState`; but only this class will read & write
 the associated preferences, and handle undo & redo on the Conf table. 'ConfTableStateManager' can be thought of as a repository
 for the Conf table, and `ConfTableState` as a single revision of its data.
 */
class ConfTableStateManager: NSObject {
  private var undoHelper = PrefsWindowUndoHelper()
  private var observers: [NSObjectProtocol] = []

  private unowned var fileCache = InputConfFile.cache

  override init() {
    super.init()
    Logger.log("ConfTableStateManager init", level: .verbose)

    // This will notify that a pref has changed, even if it was changed by another instance of IINA:
    for key in [Preference.Key.currentInputConfigName, Preference.Key.inputConfigs] {
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }
  }

  // Should not be called until the init() methods of all major components have completed
  func startUp() {
    _ = loadSelectedConfBindingsIntoAppConfig()

    DispatchQueue.global(qos: .utility).async {
      Logger.log("Loading \(AppData.defaultConfs.count) builtin conf files into cache")
      for (confName, filePath) in AppData.defaultConfs {
        self.fileCache.getOrLoadConfFile(at: filePath, isReadOnly: true, confName: confName)
      }
      
      let currentState = ConfTableState.current
      Logger.log("Loading \(currentState.userConfDict.count) user conf files into cache")
      for (confName, filePath) in currentState.userConfDict {
        self.fileCache.getOrLoadConfFile(at: filePath, isReadOnly: false, confName: confName)
      }
    }
  }

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []

    // Remove observers for IINA preferences.
    ObjcUtils.silenced {
      for key in [Preference.Key.currentInputConfigName, Preference.Key.inputConfigs] {
        UserDefaults.standard.removeObserver(self, forKeyPath: key.rawValue)
      }
    }
  }

  static func initialState() -> ConfTableState {
    let selectedConfName: String
    if let selectedConf = Preference.string(for: .currentInputConfigName) {
      selectedConfName = selectedConf
    } else {
      Logger.log("Could not get pref: \(Preference.Key.currentInputConfigName.rawValue.quoted): will use default (\(defaultConfName.quoted))", level: .warning)
      selectedConfName = defaultConfName
    }

    let userConfDict: [String: String]
    if let prefDict = Preference.dictionary(for: .inputConfigs), let userConfigStringDict = prefDict as? [String: String] {
      userConfDict = userConfigStringDict
    } else {
      Logger.log("Could not get pref: \(Preference.Key.inputConfigs.rawValue): will use default empty dictionary", level: .warning)
      userConfDict = [:]
    }

    return ConfTableState(userConfDict: userConfDict, selectedConfName: selectedConfName, specialState: .none)
  }

  static var defaultConfName: String {
    AppData.defaultConfNamesSorted[0]
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath, let change = change else { return }

    DispatchQueue.main.async {  // had some issues with race conditions
      let curr = ConfTableState.current

      switch keyPath {

        case Preference.Key.currentInputConfigName.rawValue:
          guard let selectedConfNameNew = change[.newKey] as? String, !selectedConfNameNew.equalsIgnoreCase(curr.selectedConfName) else { return }
          guard curr.specialState != .fallBackToDefaultConf else {
            // Avoids infinite loop if two or more instances are running at the same time
            Logger.log("Already in error state; ignoring pref update for selectedConf: \(selectedConfNameNew.quoted)", level: .verbose)
            return
          }
          Logger.log("Detected pref update for selectedConf: \(selectedConfNameNew.quoted)", level: .verbose)
          // Update the UI in case the update came from an external source. Make sure not to update prefs,
          // as this can cause a runaway chain reaction of back-and-forth updates if two or more instances are open!
          ConfTableState.current.changeSelectedConf(selectedConfNameNew, skipSaveToPrefs: true)
        case Preference.Key.inputConfigs.rawValue:
          guard let userConfDictNew = change[.newKey] as? [String: String] else { return }
          if !userConfDictNew.keys.sorted().elementsEqual(curr.userConfDict.keys.sorted()) {
            Logger.log("Detected pref update for inputConfigs", level: .verbose)
            self.changeState(userConfDictNew, selectedConfName: curr.selectedConfName, skipSaveToPrefs: true)
          }
        default:
          return
      }
    }
  }

  // MARK: State updates

  // This one is a little different, but it doesn't fit anywhere else. Appends bindings to a file in the table which is not the
  // current selection. Also handles the undo of the append. Does not alter anything visible in the UI.
  // Creates an undo which will fully undo its changes.
  func appendBindingsToUserConfFile(_ mappingsToAppend: [KeyMapping], targetConfName: String) {
    guard targetConfName != ConfTableState.current.selectedConfName else {
      // Should use BindingTableState instead
      Logger.log("appendBindingsToUserConfFile() should not be called for appending to the currently selected conf (\(targetConfName.quoted))!", level: .verbose)
      return
    }

    guard let inputConfFile = fileCache.getConfFile(confName: targetConfName), !inputConfFile.failedToLoad else {
      Logger.log("Cannot append to conf: \(targetConfName.quoted): file was not loaded properly!", level: .error)
      return
    }

    let actionName = Utility.format(.keyBinding, mappingsToAppend.count, .copyToFile)
    let fileMappingsOrig = inputConfFile.parseMappings()
    let fileMappingsAppended = [fileMappingsOrig, mappingsToAppend].flatMap { $0 }

    // Set up animation to flash row of changed conf (for undo/redo)
    let tableUIChange = TableUIChange(.none)
    if let targetConfIndex = ConfTableState.current.confTableRows.firstIndex(of: targetConfName) {
      tableUIChange.flashAfter = IndexSet(integer: targetConfIndex)
    }

    let doAction = {
      Logger.log("Appending to conf: \(targetConfName.quoted), prevCount: \(fileMappingsOrig.count), newCount: \(fileMappingsAppended.count)")
      inputConfFile.overwriteFile(with: fileMappingsAppended)
    }

    let undoAction = {
      Logger.log("Un-appending \(mappingsToAppend.count) bindings of conf: \(targetConfName.quoted) (newCount: \(fileMappingsOrig.count))")
      inputConfFile.overwriteFile(with: fileMappingsOrig)
      self.updateTableUI(tableUIChange)
    }

    let redoAction = {
      doAction()
      self.updateTableUI(tableUIChange)
    }

    doAction()
    undoHelper.register(actionName, undo: undoAction, redo: redoAction)
  }

  fileprivate struct UndoData {
    var userConfDict: [String:String]?
    var selectedConfName: String?
    var filesRemovedByLastAction: [String:InputConfFile]?
  }

  func changeState(_ userConfDict: [String:String]? = nil, selectedConfName: String? = nil,
                   specialState: ConfTableState.SpecialState = .none, skipSaveToPrefs: Bool = false,
                   completionHandler: TableUIChange.CompletionHandler? = nil) {

    let selectedConfOverride = specialState == .fallBackToDefaultConf ? ConfTableStateManager.defaultConfName : selectedConfName
    let undoData = UndoData(userConfDict: userConfDict, selectedConfName: selectedConfOverride)

    self.doAction(undoData, specialState: specialState, skipSaveToPrefs: skipSaveToPrefs, completionHandler: completionHandler)
  }

  // May be called for do, undo, or redo of an action which changes the table contents or selection
  private func doAction(_ newData: UndoData, specialState: ConfTableState.SpecialState = .none,
                        skipSaveToPrefs: Bool = false,
                        completionHandler: TableUIChange.CompletionHandler? = nil) {

    let tableStateOld = ConfTableState.current
    var oldData = UndoData(userConfDict: tableStateOld.userConfDict, selectedConfName: tableStateOld.selectedConfName)

    // Action label for Undo (or Redo) menu item, if applicable
    var actionName: String? = nil
    var hasConfListChange = false
    if let userConfDictNew = newData.userConfDict {
      // Figure out which of the 3 basic types of file operations was done by doing a basic diff.
      // This is a lot easier because Move is only allowed on 1 file at a time.
      let newUserConfs = Set(userConfDictNew.keys)
      let oldUserConfs = Set(tableStateOld.userConfDict.keys)

      let addedConfs = newUserConfs.subtracting(oldUserConfs)
      let removedConfs = oldUserConfs.subtracting(newUserConfs)

      if !addedConfs.isEmpty || !removedConfs.isEmpty {
        hasConfListChange = true
        Logger.log("Found in state change: \(addedConfs.count) added & \(removedConfs.count) removed confs", level: .verbose)
      }

      // Apply conf file disk operations before updating the stored prefs or the UI.
      // Almost all operations on conf files are performed here. It can handle anything needed by "undo"
      // and "redo". For the initial "do", it will handle the file operations for "rename" and "remove",
      // but for "add" types (create/import/duplicate), it's expected that the caller already successfully
      // created the new file(s) before getting here.
      if let oldConfName = removedConfs.first, let newConfName = addedConfs.first {
        actionName = "Rename Config"
        if addedConfs.count != 1 || removedConfs.count != 1 {
          // This shouldn't be possible. Make sure we catch it if it is
          Logger.fatal("Can't rename more than 1 InputConfig file at a time! (Added: \(addedConfs); Removed: \(removedConfs))")
        }
        fileCache.renameConfFile(oldConfName: oldConfName, newConfName: newConfName)

      } else if !removedConfs.isEmpty {
        // File(s) removedConfs (This can be more than one if we're undoing a multi-file import)
        actionName = Utility.format(.config, removedConfs.count, .delete)
        oldData.filesRemovedByLastAction = fileCache.removeConfFiles(confNamesToRemove: removedConfs)

      } else if !addedConfs.isEmpty {
        // Files(s) duplicated, created, or imported.
        // Too many different cases and fancy logic: let the UI controller handle the file stuff...
        actionName = Utility.format(.config, addedConfs.count, .add)
        if let filesRemovedByLastAction = newData.filesRemovedByLastAction {
          // ...UNLESS we are in an undo (if `removedConfsFilesForUndo` != nil): then this class must restore deleted files
          fileCache.restoreRemovedConfFiles(addedConfs, filesRemovedByLastAction)
        } else {  // Must be in an initial "do"
          for addedConfName in addedConfs {
            // Assume files were created elsewhere. Just need to load them into memory cache.
            // Once in memory this call should never fail, so this should never fail for undo/redo.
            let confFile = loadConfFile(withConfName: addedConfName)
            guard !confFile.failedToLoad else {
              self.sendErrorAlert(key: "error_finding_file", args: ["config"])
              return
            }
          }
        }
      }
    }

    let tableStateNew = ConfTableState(userConfDict: newData.userConfDict ?? tableStateOld.userConfDict,
                                       selectedConfName: newData.selectedConfName ?? tableStateOld.selectedConfName,
                                       specialState: specialState)

    ConfTableState.current = tableStateNew

    // Update userConfDict pref if changed
    if hasConfListChange {
      if skipSaveToPrefs {
        Logger.log("Skipping pref save for inputConfigs=\(tableStateNew.userConfDict)", level: .verbose)
      } else {
        Logger.log("Saving pref: inputConfigs=\(tableStateNew.userConfDict)", level: .verbose)
        Preference.set(tableStateNew.userConfDict, for: .inputConfigs)
      }
    }

    // Update selectedConfName and load new file if changed
    let hasSelectionChange = !tableStateOld.selectedConfName.equalsIgnoreCase(tableStateNew.selectedConfName)
    if hasSelectionChange {
      if !loadSelectedConfBindingsIntoAppConfig() {
        return
      }
      if skipSaveToPrefs || Preference.string(for: .currentInputConfigName) == tableStateNew.selectedConfName {
        Logger.log("Skipping pref save for 'currentInputConfigName': \(tableStateOld.selectedConfName.quoted) -> \(tableStateNew.selectedConfName.quoted) (current pref val: \(Preference.string(for: .currentInputConfigName)?.quoted ?? "nil"); skip=\(skipSaveToPrefs))", level: .verbose)
      } else {
        Logger.log("Saving pref 'currentInputConfigName': \(tableStateOld.selectedConfName.quoted) -> \(tableStateNew.selectedConfName.quoted)", level: .verbose)
        Preference.set(tableStateNew.selectedConfName, for: .currentInputConfigName)
      }
    }

    let hasUndoableChange: Bool = hasSelectionChange || hasConfListChange
    if hasUndoableChange {
      undoHelper.register(actionName ?? changeSelectedConfActionName, undo: {
        // Get rid of empty editor before it gets in the way:
        if ConfTableState.current.isAddingNewConfInline {
          ConfTableState.current.cancelInlineAdd()
        }

        self.doAction(oldData)  // Recursive call: implicitly registers redo
      })
    }

    let specialStateChanged = tableStateOld.specialState != tableStateNew.specialState
    if specialStateChanged {
      Logger.log("ConfTable specialState is changing: \(tableStateOld.specialState) -> \(tableStateNew.specialState)", level: .verbose)
    }

    guard hasUndoableChange || specialStateChanged || completionHandler != nil else {
      Logger.log("ConfTable doAction(): looks like nothing to do. Will skip update to table UI", level: .verbose)
      return
    }

    updateTableUI(old: tableStateOld, new: tableStateNew, completionHandler: completionHandler)
  }

  // Assembles a `TableUIChange` based on the differences between states, then sends it to the UI for updating
  private func updateTableUI(old: ConfTableState, new: ConfTableState, completionHandler: TableUIChange.CompletionHandler?) {

    let tableUIChange = TableUIChangeBuilder.buildDiff(oldRows: old.confTableRows, newRows: new.confTableRows,
                                                       completionHandler: completionHandler, overrideSingleRowMove: true)
    tableUIChange.reloadAllExistingRows = true
    if self.undoHelper.isUndoingOrRedoing() {
      tableUIChange.setUpFlashForChangedRows()
    }

    switch new.specialState {
      case .addingNewInline:  // special case: creating an all-new config
        // Select the new blank row, which will be the last one:
        tableUIChange.newSelectedRowIndexes = IndexSet(integer: new.confTableRows.count - 1)
      case .none, .fallBackToDefaultConf:
        // Always keep the current config selected
        if let selectedConfIndex = new.confTableRows.firstIndex(of: new.selectedConfName) {
          Logger.log("Will change Conf Table selection index to \(selectedConfIndex) (\(new.selectedConfName.quoted))", level: .verbose)
          tableUIChange.newSelectedRowIndexes = IndexSet(integer: selectedConfIndex)
        } else {
          Logger.log("Failed to find selection index for \(new.selectedConfName.quoted) in new Conf Table state!", level: .error)
        }
    }
    // Finally, fire notification. This covers row selection too
    updateTableUI(tableUIChange)
  }

  private func updateTableUI(_ tableUIChange: TableUIChange) {
    let notification = Notification(name: .iinaPendingUIChangeForConfTable, object: tableUIChange)
    Logger.log("ConfTableStateManager: posting \(notification.name.rawValue.quoted) notification", level: .verbose)
    NotificationCenter.default.post(notification)
  }

  // Utility function: show error popup to user
  private func sendErrorAlert(key alertKey: String, args: [String]) {
    let alertInfo = Utility.AlertInfo(key: alertKey, args: args)
    NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
  }

  // MARK: Conf File Disk Operations

  // If `confName` not provided, defaults to currently selected conf.
  // Uses cached copy first, then reads from disk if not found (faster & more reliable this way than always reading disk).
  // If it fails to find the file or read it, an error will be shown to user & written to log, but the caller needs to check
  // if `inputConfFile.failedToLoad` is false before continuing.
  func loadConfFile(withConfName confName: String? = nil) -> InputConfFile {
    let currentState = ConfTableState.current
    let targetConfName = confName ?? currentState.selectedConfName
    let isReadOnly = ConfTableState.isBuiltinConf(targetConfName)
    let confFilePath = currentState.getFilePath(forConfName: targetConfName)

    Logger.log("Loading inputConfFile for \(targetConfName.quoted)")
    return fileCache.getOrLoadConfFile(at: confFilePath, isReadOnly: isReadOnly, confName: targetConfName)
  }

  // Conf File load. Triggered any time `selectedConfName` is changed (ignoring case).
  // Returns `true` if load was successful; `false` otherwise.
  private func loadSelectedConfBindingsIntoAppConfig() -> Bool {
    let inputConfFile = loadConfFile()
    guard !inputConfFile.failedToLoad else {
      Logger.log("Cannot get bindings from \(inputConfFile.confName.quoted) because it failed to load", level: .error)
      let fileName = URL(fileURLWithPath: inputConfFile.filePath).lastPathComponent
      let alertInfo = Utility.AlertInfo(key: "keybinding_config.error", args: [fileName])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
      ConfTableState.current.fallBackToDefaultConf()
      return false
    }

    var userData: [BindingTableStateManager.Key: Any] = [BindingTableStateManager.Key.confFile: inputConfFile]

    // Key Bindings table will reload after it receives new data from AppInputConfig.
    // It will default to an animated transition based on calculated diff.
    // To disable animation, specify type .reloadAll explicitly.
    if !Preference.bool(for: .animateKeyBindingTableReloadAll) {
      userData[BindingTableStateManager.Key.tableUIChange] = TableUIChange(.reloadAll)
    }

    // Send down the pipeline
    let userConfMappingsNew = inputConfFile.parseMappings()
    AppInputConfig.replaceUserConfSectionMappings(with: userConfMappingsNew, attaching: userData)

    return true
  }
}
