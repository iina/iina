//
//  UpdateChecker.swift
//  iina
//
//  Created by lhc on 12/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation
import Just

class UpdateChecker {

  enum State {
    case updateDetected, noUpdate, error, networkError
  }

  struct GithubTag {
    var name: String
    var numericName: [Int]
    var commitSHA: String
    var commitUrl: String
    var zipUrl: String
    var tarUrl: String
  }

  static let githubTagApiPath = "https://api.github.com/repos/lhc70000/iina/tags"

  static func checkUpdate(alertIfOfflineOrNoUpdate: Bool = true) {
    var tagList: [GithubTag] = []

    Just.get(githubTagApiPath) { response in
      // network error
      guard response.ok else {
        if response.statusCode == nil {
          // if network not available
          if alertIfOfflineOrNoUpdate {
            showUpdateAlert(.networkError, message: response.reason)
          }
        } else {
          // if network error
          showUpdateAlert(.error, message: response.reason)
        }
        return
      }

      guard let tags = response.json as? [[String: Any]] else {
        showUpdateAlert(.error, message: "Wrong response format")
        return
      }

      // parse tags
      tags.forEach { tag in
        guard let name = tag["name"] as? String else { return }

        // discard tags like "v0.0.1-build2"
        guard Regex.tagVersion.matches(name) else { return }
        let numericName = Regex.tagVersion.captures(in: name)[1].components(separatedBy: ".").map { str -> Int in
          return Int(str) ?? 0
        }

        guard let commitInfo = tag["commit"] as? [String: String] else { return }

        tagList.append(GithubTag(name: name,
                                 numericName: numericName,
                                 commitSHA: commitInfo["sha"] ?? "",
                                 commitUrl: commitInfo["url"] ?? "",
                                 zipUrl: tag["zipball_url"] as! String,
                                 tarUrl: tag["tarball_url"] as! String))
      }

      // tagList should not be empty
      guard tagList.count > 0 else {
        showUpdateAlert(.error, message: "Wrong response format")
        return
      }

      // get latest
      let latest = tagList.sorted { $1.numericName.lexicographicallyPrecedes($0.numericName) }.first!.numericName

      // get current
      let currentVer = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
      let current = currentVer.components(separatedBy: ".").map { str -> Int in
        return Int(str) ?? 0
      }

      // compare
      let hasUpdate = current.lexicographicallyPrecedes(latest)

      if hasUpdate {
        showUpdateAlert(.updateDetected)
      } else if alertIfOfflineOrNoUpdate {
        showUpdateAlert(.noUpdate)
      }

    }

  }

  private static func showUpdateAlert(_ state: State, message: String? = nil) {
    DispatchQueue.main.sync {

      let alert = NSAlert()
      let isError = state == .error || state == .networkError

      let title: String
      var mainMessage: String

      switch state {
      case .updateDetected:
        title = NSLocalizedString("update.title_update_found", comment: "Title")
        mainMessage = NSLocalizedString("update.update_found", comment: "Update found")
      case .noUpdate:
        title = NSLocalizedString("update.title_no_update", comment: "Title")
        mainMessage = NSLocalizedString("update.no_update", comment: "No update")
      case .error, .networkError:
        title = NSLocalizedString("update.title_error", comment: "Title")
        mainMessage = NSLocalizedString("update.check_failed", comment: "Error")
        alert.alertStyle = .warning
      }

      if let message = message { mainMessage.append("\n\n\(message)") }

      alert.alertStyle = isError ? .warning : .informational
      alert.messageText = title
      alert.informativeText = mainMessage

      if state == .noUpdate {
        // if no update
        alert.addButton(withTitle: "OK")
        alert.runModal()
      } else {
        // if require user action
        alert.addButton(withTitle: NSLocalizedString("update.dl_from_website", comment: "Website"))
        alert.addButton(withTitle: NSLocalizedString("update.dl_from_github", comment: "Github"))
        alert.addButton(withTitle: NSLocalizedString("button.cancel", comment: "Cancel"))

        let result = alert.runModal()

        if result == NSAlertFirstButtonReturn {
          // website
          NSWorkspace.shared().open(URL(string: AppData.websiteLink)!)
        } else if result == NSAlertSecondButtonReturn {
          // github
          NSWorkspace.shared().open(URL(string: AppData.githubReleaseLink)!)
        }
      }
    }
  }

}
