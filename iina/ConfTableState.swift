//
//  InputConfPrefStore.swift
//  iina
//
//  Created by Matt Svoboda on 2022.07.04.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/*
 Provides a snapshot for the user's list of user input conf files and current selection.
 Used as a data store for the User Conf NSTableView, with CRUD operations and support for setting up
 animations, but instances of it are immutable. A new instance is created by ConfTableStateManager each
 time there is a change. Callers should not save references to instances of this class but instead should
 refer to ConfTableState.current each time for an up-to-date version.
 Tries to be model-focused and decoupled from UI code so that everything is cleaner.
 */
struct ConfTableState {
  static var current: ConfTableState = ConfTableStateManager.initialState()
  static let manager: ConfTableStateManager = ConfTableStateManager()

  enum SpecialState {
    case none

    // In this state, a blank "fake" row has been created which doesn't map to anything, and the normal
    // rules of the table are bent a little bit to accomodate it, until the user finishes naming it.
    // The blank row will also be selected, but `selectedConfName` should not change until the user submits or clicks on another row.
    case addingNewInline

    // An error in configuration occurred which caused the selected conf to be changed to the default rather than crashing or undefined behavior.
    case fallBackToDefaultConf
  }

  // MARK: State data

  let specialState: SpecialState

  // Combined with built-in conf
  let userConfDict: [String: String]

  let selectedConfName: String

  // MARK: Derived data (built from state data above + various constants & predictable logic)

  /*
   Contains names of all the default confs in pre-defined order, follwed by the names of all user confs in alphabetical order.
   Each name is unique within the Conf TableView and serve as identifiers.
   */
  let confTableRows: [String]

  // Looks up the selected conf, then searches for it first in the user confs, then the default confs,
  // then if still not found, just computes its expected value and returns it.
  var selectedConfFilePath: String {
    let selectedConf = selectedConfName

    if let filePath = userConfDict[selectedConf] {
      Logger.log("Found file path in user conf dict for \(selectedConf.quoted): \(filePath.quoted)", level: .verbose)
      if URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent != selectedConf {
        Logger.log("Conf's name \(selectedConf.quoted) does not match its filename: \(filePath.quoted)", level: .warning)
      }
      return filePath
    }
    if let filePath = AppData.defaultConfs[selectedConf] {
      Logger.log("Found file path for default conf \(selectedConf.quoted): \(filePath.quoted)", level: .verbose)
      return filePath
    }
    Logger.log("Cannot find file path for selected conf (\(selectedConf.quoted)). It is likely the preferences are corrupted. Will derive its file path from its name and the user conf directory path.", level: .warning)
    let filePath = Utility.buildConfFilePath(for: selectedConf)
    Logger.log("Computed path of conf \(selectedConf.quoted): \(filePath.quoted)")
    return filePath
  }

  var isAddingNewConfInline: Bool {
    return self.specialState == .addingNewInline
  }

  init(userConfDict: [String: String], selectedConfName: String, specialState: SpecialState) {
    self.userConfDict = userConfDict
    self.selectedConfName = selectedConfName
    self.specialState = specialState
    self.confTableRows = ConfTableState.buildConfTableRows(from: self.userConfDict,
                                                           isAddingNewConfInline: specialState == .addingNewInline)
  }

  // MARK: Non-mutating getters

  var isSelectedConfReadOnly: Bool {
    return ConfTableState.isBuiltinConf(selectedConfName)
  }

  static func isBuiltinConf(_ confName: String) -> Bool {
    return AppData.defaultConfs[confName] != nil
  }

  func getFilePath(forConfName confName: String) -> String {
    if let defaultConfPath = AppData.defaultConfs[confName] {
      return defaultConfPath
    }
    if let userConfPath = userConfDict[confName] {
      return userConfPath
    }

    return Utility.buildConfFilePath(for: confName)
  }

  // Returns the name of the user conf with the given path, or nil if no conf matches
  func getUserConfName(forFilePath filePath: String) -> String? {
    for (userConfName, userFilePath) in userConfDict {
      if userFilePath == filePath {
        return userConfName
      }
    }
    return nil
  }

  func getBuiltinConfName(forFilePath filePath: String) -> String? {
    let filePathLower = filePath.lowercased()
    for (builtinConfName, builtinFilePath) in AppData.defaultConfs {
      if builtinFilePath.lowercased() == filePathLower {
        return builtinConfName
      }
    }
    return nil
  }

  // Does a case-insensitive check to see if a row already exists in the table with the given name
  func isRow(_ confName: String) -> Bool {
    let confNameLower = confName.lowercased()
    for rowName in confTableRows {
      if rowName.lowercased() == confNameLower {
        return true
      }
    }
    return false
  }

  // Avoids hard program crash if index is invalid (which would happen for array dereference)
  func getConfName(at index: Int) -> String? {
    guard index >= 0 && index < confTableRows.count else {
      return nil
    }
    return confTableRows[index]
  }

  // Same as `getConfName()`, but only returns user confs. If a default conf is found instead, nil is returned.
  func getUserConfName(at index: Int) -> String? {
    if let confName = getConfName(at: index), !ConfTableState.isBuiltinConf(confName){
      return confName
    }
    return nil
  }

  func isBuiltinConf(at index: Int) -> Bool {
    if let confName = getConfName(at: index) {
      return ConfTableState.isBuiltinConf(confName)
    }
    return false
  }

  // MARK: Operations which change state

  // Adds (or updates) conf file with the given name into the user confs list preference, and sets it as the selected conf.
  // Posts update notification
  func addUserConf(confName: String, filePath: String, completionHandler: TableUIChange.CompletionHandler? = nil) {
    Logger.log("Adding user conf: \(confName.quoted) (filePath: \(filePath.quoted))")
    var userConfDictUpdated = userConfDict
    userConfDictUpdated[confName] = filePath
    ConfTableState.manager.changeState(userConfDictUpdated, selectedConfName: confName, completionHandler: completionHandler)
  }

  func addNewUserConfInline(completionHandler: TableUIChange.CompletionHandler? = nil) {
    guard !isAddingNewConfInline else {
      Logger.log("Already adding new user conf inline! Returning.", level: .verbose)
      return
    }

    Logger.log("Adding blank row to bottom of table for naming new user conf", level: .verbose)
    ConfTableState.manager.changeState(specialState: .addingNewInline, completionHandler: completionHandler)
  }

  func completeInlineAdd(confName: String, filePath: String,
                         completionHandler: TableUIChange.CompletionHandler? = nil) {
    guard isAddingNewConfInline else {
      Logger.log("completeInlineAdd() called but isAddingNewConfInline is false!", level: .error)
      return
    }

    Logger.log("Completing inline add of user conf: \(confName.quoted) (filePath: \(filePath.quoted))")
    var userConfDictUpdated = userConfDict
    userConfDictUpdated[confName] = filePath
    ConfTableState.manager.changeState(userConfDictUpdated, selectedConfName: confName, completionHandler: completionHandler)
  }

  func cancelInlineAdd(selectedConfNew: String? = nil) {
    guard isAddingNewConfInline else {
      Logger.log("cancelInlineAdd() called but isAddingNewConfInline is false!", level: .error)
      return
    }
    Logger.log("Cancelling inline add", level: .verbose)
    ConfTableState.manager.changeState(selectedConfName: selectedConfNew)
  }

  func addUserConfs(_ userConfsToAdd: [String: String]) {
    Logger.log("Adding user confs: \(userConfsToAdd)")
    guard let firstConf = userConfsToAdd.first else {
      return
    }
    var selectedConfNew = firstConf.key

    var userConfDictUpdated = userConfDict
    for (name, filePath) in userConfsToAdd {
      userConfDictUpdated[name] = filePath
      // We can only select one, even if multiple rows added.
      // Select the added conf with the last name in lowercase alphabetical order
      if selectedConfNew.localizedCompare(name) == .orderedAscending {
        selectedConfNew = name
      }
    }
    ConfTableState.manager.changeState(userConfDictUpdated, selectedConfName: selectedConfNew)
  }

  func removeConf(_ confName: String) {
    let isCurrentConf: Bool = confName == selectedConfName
    Logger.log("Removing conf: \(confName.quoted) (isCurrentConf: \(isCurrentConf))")

    var selectedConfNameNew = selectedConfName

    if isCurrentConf {
      guard let confIndex = confTableRows.firstIndex(of: confName) else {
        Logger.log("Cannot find \(confName.quoted) in table!", level: .error)
        return
      }
      // Are we the last entry? If so, after deletion the next entry up should be selected. If not, select the next one down
      selectedConfNameNew = confTableRows[(confIndex == confTableRows.count - 1) ? confIndex - 1 : confIndex + 1]
    }

    var userConfDictUpdated = userConfDict
    guard userConfDictUpdated.removeValue(forKey: confName) != nil else {
      Logger.log("Cannot remove conf \(confName.quoted): it is not a user conf!", level: .error)
      return
    }
    ConfTableState.manager.changeState(userConfDictUpdated, selectedConfName: selectedConfNameNew)
  }

  func renameSelectedConf(newName: String) -> Bool {
    var userConfDictUpdated = userConfDict
    Logger.log("Renaming conf in prefs: \(selectedConfName.quoted) -> \(newName.quoted)")
    guard !selectedConfName.equalsIgnoreCase(newName) else {
      Logger.log("Skipping rename: \(selectedConfName.quoted) and \(newName.quoted) are the same", level: .error)
      return false
    }

    guard userConfDictUpdated[newName] == nil else {
      Logger.log("Cannot rename selected conf: a conf already exists named: \(newName.quoted)", level: .error)
      return false
    }

    guard userConfDictUpdated.removeValue(forKey: selectedConfName) != nil else {
      Logger.log("Cannot rename selected conf \(selectedConfName.quoted): it is not a user conf!", level: .error)
      return false
    }

    let newFilePath = Utility.buildConfFilePath(for: newName)
    userConfDictUpdated[newName] = newFilePath

    ConfTableState.manager.changeState(userConfDictUpdated, selectedConfName: newName)
    return true
  }

  func appendBindingsToUserConfFile(_ bindings: [KeyMapping], targetConfName: String) {
    let isReadOnly = ConfTableState.isBuiltinConf(targetConfName)
    guard !isReadOnly else { return }

    if targetConfName == selectedConfName {
      // If conf is being displayed already, give data to BindingTableState. It will include animations and do a better job.
      BindingTableState.current.appendBindingsToUserConfSection(bindings)
    } else {
      ConfTableState.manager.appendBindingsToUserConfFile(bindings, targetConfName: targetConfName)
    }
  }

  // MARK: Change Selection

  func fallBackToDefaultConf() {
    Logger.log("Changing selected conf to default", level: .verbose)
    ConfTableState.manager.changeState(selectedConfName: ConfTableStateManager.defaultConfName, specialState: .fallBackToDefaultConf)
  }

  func changeSelectedConf(_ newIndex: Int) {
    Logger.log("Changing conf selection index to: \(newIndex)", level: .verbose)
    guard let selectedConfNew = getConfName(at: newIndex) else {
      Logger.log("Cannot change conf selection: invalid index: \(newIndex)", level: .error)
      return
    }
    if isAddingNewConfInline && selectedConfNew == "" {
      return
    }
    changeSelectedConf(selectedConfNew)
  }

  func changeSelectedConf(_ selectedConfNew: String, skipSaveToPrefs: Bool = false) {
    guard !selectedConfNew.equalsIgnoreCase(self.selectedConfName) else {
      return
    }

    guard isRow(selectedConfNew) else {
      Logger.log("Could not change selected conf to \(selectedConfNew.quoted) (not found in table); falling back to default conf", level: .error)
      fallBackToDefaultConf()
      return
    }

    Logger.log("Changing selected conf to: \(selectedConfNew.quoted)", level: .verbose)

    ConfTableState.manager.changeState(selectedConfName: selectedConfNew, skipSaveToPrefs: skipSaveToPrefs)
  }

  // Rebuilds & re-sorts the table names. Must not change the actual state of any member vars
  static private func buildConfTableRows(from userConfDict: [String: String],
                                         isAddingNewConfInline: Bool) -> [String] {
    var confTableRows: [String] = []

    // - default confs:
    confTableRows.append(contentsOf: AppData.defaultConfNamesSorted)

    // - user: explicitly sort (ignoring case)
    var userConfNameList: [String] = []
    userConfDict.forEach {
      userConfNameList.append($0.key)
    }
    userConfNameList.sort{$0.localizedCompare($1) == .orderedAscending}

    confTableRows.append(contentsOf: userConfNameList)

    if isAddingNewConfInline {
      // Add blank row to be edited to the end
      confTableRows.append("")
    }

    return confTableRows
  }

}
