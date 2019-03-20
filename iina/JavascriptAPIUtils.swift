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
}

class JavascriptAPIUtils: JavascriptAPI, JavascriptAPIUtilsExportable {
  @objc func exec(_ file: String, _ args: [String]) -> JSValue? {
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
      process.launch()

      self.pluginInstance.queue.async {
        process.waitUntilExit()
        resolve.call(withArguments: [[
          "status": process.terminationStatus,
          "stdout": String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? JSValue(nullIn: self.context),
          "stderr": String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? JSValue(nullIn: self.context)
        ] as [String: Any]])
      }
    }
  }

  override func extraSetup() {
    context.evaluateScript("""
    iina.utils.ERROR_BINARY_NOT_FOUND = -1;
    iina.utils.ERROR_RUNTIME = -2;
    """)
  }
}
