//
//  DefaultApplicationSetter.swift
//  iina
//
//  Sets IINA as the default handler for selected media UTIs.
//

import AppKit
import UniformTypeIdentifiers

enum DefaultApplicationSetter {

  /// Collect UTI identifiers for the checked media categories using preferred types only.
  static func targetIdentifiers(
    utiImportedTypes: [[String: Any]],
    checkedCategories: [String: Bool]
  ) -> Set<String>? {
    guard let imported = DefaultAppUTITargets.parseImportedTypes(utiImportedTypes) else {
      return nil
    }
    return DefaultAppUTITargets.identifiers(
      importedTypes: imported,
      checkedCategories: checkedCategories,
      preferredIdentifierForExtension: { ext in
        UTType(filenameExtension: ext)?.identifier
      }
    )
  }

  /// Apply default-app registration. Uses `NSWorkspace` on macOS 12+ so consent
  /// completions finish before reporting success; falls back to Launch Services otherwise.
  static func setAsDefault(
    identifiers: Set<String>,
    completion: @escaping (_ successCount: Int, _ failedCount: Int) -> Void
  ) {
    let sorted = identifiers.sorted()
    guard !sorted.isEmpty else {
      completion(0, 0)
      return
    }

    if #available(macOS 12.0, *) {
      let appURL = Bundle.main.bundleURL
      let group = DispatchGroup()
      let lock = NSLock()
      var successCount = 0
      var failedCount = 0

      for identifier in sorted {
        guard let contentType = UTType(identifier) else {
          Logger.log("Unknown UTI: \(identifier.quoted)", level: .error)
          lock.lock()
          failedCount += 1
          lock.unlock()
          continue
        }
        Logger.log("Setting default for UTI: \(identifier.quoted)", level: .verbose)
        group.enter()
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: contentType) { error in
          lock.lock()
          if let error {
            Logger.log("Failed for \(identifier.quoted): \(error.localizedDescription)", level: .error)
            failedCount += 1
          } else {
            successCount += 1
          }
          lock.unlock()
          group.leave()
        }
      }

      group.notify(queue: .main) {
        completion(successCount, failedCount)
      }
    } else {
      guard let cfBundleID = Bundle.main.bundleIdentifier as CFString? else {
        completion(0, sorted.count)
        return
      }
      var successCount = 0
      var failedCount = 0
      for identifier in sorted {
        Logger.log("Setting default for UTI: \(identifier.quoted)", level: .verbose)
        let status = LSSetDefaultRoleHandlerForContentType(identifier as CFString, .all, cfBundleID)
        if status == kOSReturnSuccess {
          successCount += 1
        } else {
          Logger.log("Failed for \(identifier.quoted): return value \(status)", level: .error)
          failedCount += 1
        }
      }
      completion(successCount, failedCount)
    }
  }
}
