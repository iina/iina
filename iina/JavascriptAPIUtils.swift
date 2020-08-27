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
  func fileExists(_ path: String) -> Any
  func writeFile(_ path: String, _ content: String)
  func readFile(_ path: String, _ options: [String: Any]) -> Any?
  func trashFile(_ path: String)
  func deleteFile(_ path: String)
}

class JavascriptAPIUtils: JavascriptAPI, JavascriptAPIUtilsExportable {
  override func extraSetup() {
    context.evaluateScript("""
    iina.utils.ERROR_BINARY_NOT_FOUND = -1;
    iina.utils.ERROR_RUNTIME = -2;
    """)
  }

  func exec(_ file: String, _ args: [String]) -> JSValue? {
    guard permitted(to: .callProcess) else {
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

  func fileExists(_ path: String) -> Any {
    guard let filePath = parsePath(path).path else { return false }

    return FileManager.default.fileExists(atPath: filePath)
  }

  func writeFile(_ path: String, _ content: String) {
    let (filePath_, local) = parsePath(path)
    guard let filePath = filePath_ else { return }

    if !local && FileManager.default.fileExists(atPath: filePath) {
      throwError(withMessage: "Cannot overwrite existing file at \(path). Overwriting is only supported for @tmp and @data files.")
      return
    }

    do {
      try content.write(toFile: filePath, atomically: true, encoding: .utf8)
    } catch let error {
      throwError(withMessage: "Cannot write file: \(error.localizedDescription)")
    }
  }

  func readFile(_ path: String, _ options: [String: Any]) -> Any? {
    guard let filePath = parsePath(path).path else { return nil }

    var encoding = String.Encoding.utf8
    if let encodingString = options["encoding"] as? String {
      guard let enc = stringEncodingFromName(encodingString) else {
        throwError(withMessage: "Unknown encoding \"\(encodingString)\"")
        return nil
      }
      encoding = enc
    }

    do {
      return try String(contentsOfFile: filePath, encoding: encoding)
    } catch let error {
      throwError(withMessage: "Cannot read file: \(error.localizedDescription)")
    }
    return nil
  }

  func trashFile(_ path: String) {
    let (filePath_, local) = parsePath(path)
    guard let filePath = filePath_ else { return }

    whenPermitted(to: .accessFileSystem) {
      guard !local else {
        throwError(withMessage: "utils.trashFile can only be called for files in the user file system.")
        return
      }
      do {
        try FileManager.default.trashItem(at: URL(fileURLWithPath: filePath), resultingItemURL: nil)
      } catch let error {
        throwError(withMessage: "Cannot trash file: \(error.localizedDescription)")
      }
    }
  }

  func deleteFile(_ path: String) {
    let (filePath_, local) = parsePath(path)
    guard let filePath = filePath_ else { return }

    guard local else {
      throwError(withMessage: "utils.deleteFile can only be called for @tmp and @data files.")
      return
    }
    do {
      try FileManager.default.removeItem(atPath: filePath)
    } catch let error {
      throwError(withMessage: "Cannot delete file: \(error.localizedDescription)")
    }
  }
}
