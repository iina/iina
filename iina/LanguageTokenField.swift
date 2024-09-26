//
//  LanguageTokenField.swift
//  iina
//
//  Created by Collider LI on 12/4/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa

fileprivate let enableLookupLogging = false

// Data structure: LangToken
// A token suitable for use by an `NSTokenField`, which represents a single ISO639 language
fileprivate struct LangToken: Equatable, Hashable, CustomStringConvertible {
  // The 3-digit ISO639 language code, if a matching language was found:
  let code: String?
  // The `editingString` which shows up when a token is double-clicked.
  // Will be equivalent to `description` field of matching `ISO639Helper.Language`, if match was found.
  let editingString: String

  // As a displayed token, this is used as the displayString. When stored in prefs CSV, this is used as the V[alue]:
  var identifierString: String {
    code ?? normalizedEditingString
  }

  // For logging and debugging only. Not to be confused with `ISO639Helper.Language.description`
  var description: String {
    return "LangToken(code: \(code?.quoted ?? "nil"), editStr: \(editingString.quoted))"
  }

  // "Normalizes" the editingString so it can be serialized to CSV. Removes whitespace and commas.
  // Also makes lowercase, because it will be used as an case-agnostic identifier.
  private var normalizedEditingString: String {
    self.editingString.lowercased().replacingOccurrences(of: ",", with: ";").trimmingCharacters(in: .whitespaces)
  }

  // Need the following to prevent NSTokenField from doing an infinite loop

  func equalTo(_ rhs: LangToken) -> Bool {
    return self.editingString == rhs.editingString
  }

  static func ==(lhs: LangToken, rhs: LangToken) -> Bool {
    return lhs.equalTo(rhs)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(editingString)
  }

  // If code is valid, looks up its description and uses it for `editingString`.
  // If code not found, falls back to init from editingString.
  static func from(_ string: String) -> LangToken {
    let matchingLangs = ISO639Helper.languages.filter({ $0.code == string })
    if !matchingLangs.isEmpty {
      let langDescription = matchingLangs[0].description
      return LangToken(code: string, editingString: langDescription)
    }
    return LangToken(code: nil, editingString: string)
  }
}

// Data structure: LangSet
// A collection of unique languages (usually the field's entire contents)
fileprivate struct LangSet {
  let langTokens: [LangToken]

  init(langTokens: [LangToken]) {
    self.langTokens = langTokens
  }

  init(fromCSV csv: String) {
    self.init(langTokens: csv.isEmpty ? [] : csv.components(separatedBy: ",").map{ LangToken.from($0.trimmingCharacters(in: .whitespaces)) })
  }

  init(fromObjectValue objectValue: Any?) {
    self.init(langTokens: (objectValue as? NSArray)?.compactMap({ ($0 as? LangToken) }) ?? [])
  }

  func toCommaSeparatedValues() -> String {
    return langTokens.map{ $0.identifierString }.joined(separator: ",")
  }

  func toNewlineSeparatedValues() -> String {
    return langTokens.map{ $0.identifierString }.joined(separator: "\n")
  }
}

class LanguageTokenField: NSTokenField {
  private var layoutManager: NSLayoutManager?

  // Should match the value from the prefs.
  // Is only changed when `commaSeparatedValues` is set, and by `submitChanges()`.
  private var savedSet = LangSet(langTokens: [])

  // may include unsaved tokens from the edit session
  fileprivate var objectValueLangSet: LangSet {
    LangSet(fromObjectValue: self.objectValue)
  }

  var commaSeparatedValues: String {
    get {
      let csv = savedSet.toCommaSeparatedValues()
      Logger.log("LTF Generated CSV from savedSet: \(csv.quoted)", level: .verbose)
      return csv
    } set {
      Logger.log("LTF Setting savedSet from CSV: \(newValue.quoted)", level: .verbose)
      self.savedSet = LangSet(fromCSV: newValue)
      // Need to convert from CSV to newline-SV
      self.stringValue = self.savedSet.toNewlineSeparatedValues()
    }
  }

  override func awakeFromNib() {
    super.awakeFromNib()
    self.delegate = self
    self.tokenStyle = .rounded
    // Cannot use commas, because language descriptions are used as editing strings, and many of them contain commas, whitespace, quotes,
    // and NSTokenField will internally tokenize editing strings. We should be able to keep using CSV in the prefs
    self.tokenizingCharacterSet = .newlines
  }

  @objc func controlTextDidEndEditing(_ notification: Notification) {
    Logger.log("LTF Submitting changes from controlTextDidEndEditing()", level: .verbose)
    submitChanges()
  }

  func controlTextDidChange(_ obj: Notification) {
    guard let layoutManager = layoutManager else { return }
    let attachmentChar = Character(UnicodeScalar(NSTextAttachment.character)!)
    let finished = layoutManager.attributedString().string.split(separator: attachmentChar).count == 0
    if finished {
      Logger.log("LTF Submitting changes from controlTextDidChange()", level: .verbose)
      submitChanges()
    }
  }

  override func textShouldBeginEditing(_ textObject: NSText) -> Bool {
    if let view = textObject as? NSTextView {
      layoutManager = view.layoutManager
    }
    return true
  }

  private func submitChanges() {
    let langSetNew = filterDuplicates(from: self.objectValueLangSet, basedOn: self.savedSet)
    makeUndoableUpdate(to: langSetNew)
  }

  // Filter out duplicates. Use the prev set to try to figure out which copy is newer, and favor that one.
  private func filterDuplicates(from langSetNew: LangSet, basedOn langSetOld: LangSet) -> LangSet {
    let dictOld: [String: [Int]] = countTokenIndexes(langSetOld)
    let dictNew: [String: [Int]] = countTokenIndexes(langSetNew)

    var indexesToRemove = Set<Int>()
    // Iterate over only the duplicates:
    for (dupString, indexesNew) in dictNew.filter({ $0.value.count > 1 }) {
      if let indexesOld = dictOld[dupString] {
        let oldIndex = indexesOld[0]
        var indexToKeep = indexesNew[0]
        for index in indexesNew {
          // Keep the token which is farthest distance from old location
          if abs(index - oldIndex) > abs(indexToKeep - oldIndex) {
            indexToKeep = index
          }
        }
        for index in indexesNew {
          if index != indexToKeep {
            indexesToRemove.insert(index)
          }
        }
      }
    }
    let filteredTokens = langSetNew.langTokens.enumerated().filter({ !indexesToRemove.contains($0.offset) }).map({ $0.element })
    return LangSet(langTokens: filteredTokens)
  }

  private func countTokenIndexes(_ langSet: LangSet) -> [String: [Int]] {
    var dict: [String: [Int]] = [:]
    for (index, token) in langSet.langTokens.enumerated() {
      if var list = dict[token.identifierString] {
        list.append(index)
        dict[token.identifierString] = list
      } else {
        dict[token.identifierString] = [index]
      }
    }
    return dict
  }

  private func makeUndoableUpdate(to langSetNew: LangSet) {
    let langSetOld = self.savedSet
    let csvOld = langSetOld.toCommaSeparatedValues()
    let csvNew = langSetNew.toCommaSeparatedValues()

    Logger.log("LTF Updating \(csvOld.quoted) -> \(csvNew.quoted)}", level: .verbose)
    if csvOld == csvNew {
      Logger.log("LTF No changes to lang set", level: .verbose)
    } else {
      self.savedSet = langSetNew
      if let target = target, let action = action {
        target.performSelector(onMainThread: action, with: self, waitUntilDone: false)
      }

      // Register for undo or redo. Needed because the change to stringValue below doesn't include it
      if let undoManager = self.undoManager {
        undoManager.registerUndo(withTarget: self, handler: { languageTokenField in
          self.makeUndoableUpdate(to: langSetOld)
        })
      }
    }

    // Update tokenField value
    self.stringValue = langSetNew.toNewlineSeparatedValues()
  }
}

extension LanguageTokenField: NSTokenFieldDelegate {

  func tokenField(_ tokenField: NSTokenField, hasMenuForRepresentedObject representedObject: Any) -> Bool {
    // Tokens never have a context menu
    return false
  }

  // Returns array of auto-completion results for user's typed string (`substring`)
  func tokenField(_ tokenField: NSTokenField, completionsForSubstring substring: String,
                  indexOfToken tokenIndex: Int, indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?) -> [Any]? {
    let lowSubString = substring.lowercased()
    let currentLangCodes = Set(self.savedSet.langTokens.compactMap{$0.code})
    let matches = ISO639Helper.languages.filter { lang in
      return !currentLangCodes.contains(lang.code) && lang.name.contains { $0.lowercased().hasPrefix(lowSubString) }
    }
    let descriptions = matches.map { $0.description }
    if enableLookupLogging {
      Logger.log("LTF Given substring: \(substring.quoted) -> returning completions: \(descriptions)", level: .verbose)
    }
    return descriptions
  }

  // Called by AppKit. Token -> DisplayStringString. Returns the string to use when displaying as a token
  func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
    guard let token = representedObject as? LangToken else { return nil }

    if enableLookupLogging {
      Logger.log("LTF Given token: \(token) -> returning displayString: \(token.identifierString.quoted)", level: .verbose)
    }
    return token.identifierString
  }

  // Called by AppKit. Token -> EditingString. Returns the string to use when editing a token.
  func tokenField(_ tokenField: NSTokenField, editingStringForRepresentedObject representedObject: Any) -> String? {
    guard let token = representedObject as? LangToken else { return nil }

    if enableLookupLogging {
      Logger.log("LTF Given token: \(token) -> returning editingString: \(token.editingString.quoted)", level: .verbose)
    }
    return token.editingString
  }

  // Called by AppKit. EditingString -> Token
  func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> Any? {
    // Return language code (if possible)
    let token: LangToken
    // editingString is description?
    if let langCode = ISO639Helper.descriptionRegex.captures(in: editingString)[at: 1] {
      token  = LangToken.from(langCode)
    } else {
      token  = LangToken.from(editingString)
    }
    if enableLookupLogging {
      Logger.log("LTF Given editingString: \(editingString.quoted) -> returning: \(token)", level: .verbose)
    }
    return token
  }

  // Serializes an array of LangToken objects into a string of CSV (cut/copy/paste support)
  // Need to override this because it will default to using `tokenizingCharacterSet`, which needed to be overridden for
  // internal parsing of `editingString`s to work correctly, but we want to use CSV when exporting `identifierString`s
  // because they are more user-readable.
  func tokenField(_ tokenField: NSTokenField, writeRepresentedObjects objects: [Any], to pboard: NSPasteboard) -> Bool {
    guard let tokens = objects as? [LangToken] else {
      return false
    }
    let langSet = LangSet(langTokens: tokens)

    pboard.clearContents()
    pboard.setString(langSet.toCommaSeparatedValues(), forType: NSPasteboard.PasteboardType.string)
    return true
  }

  // Parses CSV from the given pasteboard and returns an array of LangToken objects (cut/copy/paste support)
  // See note for `tokenField(writeRepresentedObjects....)` above.
  func tokenField(_ tokenField: NSTokenField, readFrom pboard: NSPasteboard) -> [Any]? {
    if let pbString = pboard.string(forType: NSPasteboard.PasteboardType.string) {
      return LangSet(fromCSV: pbString).langTokens
    }
    return []
  }
}
