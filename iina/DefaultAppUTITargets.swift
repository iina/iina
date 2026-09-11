//
//  DefaultAppUTITargets.swift
//  iina
//
//  Pure UTI selection for “Set as default application”.
//

import Foundation

enum DefaultAppUTITargets {
  struct ImportedType: Equatable {
    let identifier: String
    let conformsTo: [String]
    let extensions: [String]
  }

  /// Prefer each imported identifier plus one preferred UTI per extension —
  /// do not expand every UTI that claims the extension (prompt flood on Tahoe+).
  static func identifiers(
    importedTypes: [ImportedType],
    checkedCategories: [String: Bool],
    preferredIdentifierForExtension: (String) -> String?
  ) -> Set<String> {
    var result = Set<String>()
    for type in importedTypes {
      let matchesChecked = checkedCategories.contains { category, checked in
        checked && type.conformsTo.contains(category)
      }
      guard matchesChecked else { continue }
      result.insert(type.identifier)
      for ext in type.extensions {
        if let preferred = preferredIdentifierForExtension(ext) {
          result.insert(preferred)
        }
      }
    }
    return result
  }

  static func parseImportedTypes(_ raw: [[String: Any]]) -> [ImportedType]? {
    var parsed: [ImportedType] = []
    for utiImportedType in raw {
      guard
        let identifier = utiImportedType["UTTypeIdentifier"] as? String,
        let conformsTo = utiImportedType["UTTypeConformsTo"] as? [String],
        let tagSpec = utiImportedType["UTTypeTagSpecification"] as? [String: Any]
      else {
        return nil
      }
      let exts: [String]
      if let list = tagSpec["public.filename-extension"] as? [String] {
        exts = list
      } else if let single = tagSpec["public.filename-extension"] as? String {
        exts = [single]
      } else {
        return nil
      }
      parsed.append(ImportedType(identifier: identifier, conformsTo: conformsTo, extensions: exts))
    }
    return parsed
  }
}
