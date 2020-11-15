//
//  JavascriptAPIUtils.swift
//  iina
//
//  Created by Collider LI on 2/3/2019.
//  Copyright © 2019 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

fileprivate func searchBinary(_ file: String, in url: URL) -> URL? {
  let url = url.appendingPathComponent(file)
  return FileManager.default.fileExists(atPath: url.path) ? url : nil
}

fileprivate extension Process {
  var descriptionDict: [String: Any] {
    return [
      "status": terminationStatus
    ]
  }
}

@objc protocol JavascriptAPIUtilsExportable: JSExport {
  func exec(_ file: String, _ args: [String]) -> JSValue?
  func ask(_ title: String) -> Bool
  func prompt(_ title: String) -> String?
  func chooseFile(_ title: String, _ options: [String: Any]) -> Any
}

class JavascriptAPIUtils: JavascriptAPI, JavascriptAPIUtilsExportable {
  override func extraSetup() {
    context.evaluateScript("""
    iina.utils.ERROR_BINARY_NOT_FOUND = -1;
    iina.utils.ERROR_RUNTIME = -2;
    """)
  }

  func exec(_ file: String, _ args: [String]) -> JSValue? {
    guard permitted(to: .accessFileSystem) else {
      return nil
    }
    return createPromise { resolve, reject in
      guard let url = searchBinary(file, in: Utility.binariesURL) ?? searchBinary(file, in: Utility.exeDirURL) else {
        reject.call(withArguments: [-1, "Cannot find the binary \(file)"])
        return
      }

      if !FileManager.default.isExecutableFile(atPath: url.path) {
        do {
          try FileManager.default.setAttributes([.posixPermissions: NSNumber(integerLiteral: 0o755)], ofItemAtPath: url.path)
        } catch {
          reject.call(withArguments: [-2, "The binary is not executable, and execute permission cannot be added"])
          return
        }
      }

      let (stdout, stderr) = (Pipe(), Pipe())
      let process = Process()
      process.launchPath = url.path
      process.arguments = args
      process.standardOutput = stdout
      process.standardError = stderr

      var stdoutContent = ""
      var stderrContent = ""

      stdout.fileHandleForReading.readabilityHandler = { file in
        guard let output = String(data: file.availableData, encoding: .utf8) else { return }
        stdoutContent += output
      }
      stderr.fileHandleForReading.readabilityHandler = { file in
        guard let output = String(data: file.availableData, encoding: .utf8) else { return }
        stderrContent += output
      }
      process.launch()

      self.pluginInstance.queue.async {
        process.waitUntilExit()
        stderr.fileHandleForReading.readabilityHandler = nil
        stdout.fileHandleForReading.readabilityHandler = nil
        resolve.call(withArguments: [[
          "status": process.terminationStatus,
          "stdout": stdoutContent,
          "stderr": stderrContent
        ] as [String: Any]])
      }
    }
  }

  func ask(_ title: String) -> Bool {
    let panel = NSAlert()
    panel.messageText = title
    panel.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    panel.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    return panel.runModal() == .alertFirstButtonReturn
  }

  func prompt(_ title: String) -> String? {
    let panel = NSAlert()
    panel.messageText = title
    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 60))
    input.lineBreakMode = .byWordWrapping
    input.usesSingleLineMode = false
    panel.accessoryView = input
    panel.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    panel.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    panel.window.initialFirstResponder = input
    if panel.runModal() == .alertFirstButtonReturn {
      return input.stringValue
    }
    return nil
  }

  func chooseFile(_ title: String, _ options: [String: Any]) -> Any {
    let chooseDir = options["chooseDir"] as? Bool ?? false
    let allowedFileTypes = options["allowedFileTypes"] as? [String]
    return createPromise { resolve, reject in
      Utility.quickOpenPanel(title: title, chooseDir: chooseDir, allowedFileTypes: allowedFileTypes) { result in
        resolve.call(withArguments: [result.path])
      }
    }
  }
}
