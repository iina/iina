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

fileprivate final class JavascriptProcessOutput {
  private let file: FileHandle
  private let drained: DispatchGroup
  private let lock = NSLock()
  private var data = Data()
  private var finished = false

  var content: String {
    lock.lock()
    defer { lock.unlock() }
    return String(decoding: data, as: UTF8.self)
  }

  init(_ file: FileHandle, drained: DispatchGroup, hook: JSValue?) {
    self.file = file
    self.drained = drained
    drained.enter()
    file.readabilityHandler = { [self] file in
      let bytes = file.availableData
      lock.lock()
      guard !finished else { lock.unlock(); return }
      if bytes.isEmpty {
        finished = true
        file.readabilityHandler = nil
        lock.unlock()
        drained.leave()
      } else {
        data.append(bytes)
        if let hook, let output = String(data: bytes, encoding: .utf8) {
          // JavaScript microtasks can call UI APIs while holding the VM lock.
          DispatchQueue.main.async { hook.call(withArguments: [output]) }
        }
        lock.unlock()
      }
    }
  }

  func cancel() {
    file.readabilityHandler = nil
    lock.lock()
    let wasFinished = finished
    finished = true
    lock.unlock()
    if !wasFinished { drained.leave() }
  }
}

@objc protocol JavascriptAPIUtilsExportable: JSExport {
  func fileInPath(_ file: String) -> Bool
  func resolvePath(_ path: String) -> String?
  func exec(_ file: String, _ args_: Any, _ cwd: JSValue?, _ stdoutHook_: JSValue?, _ stderrHook_: JSValue?) -> JSValue?
  func ask(_ title: String) -> Bool
  func prompt(_ title: String) -> String?
  func chooseFile(_ title: String, _ options: [String: Any]) -> Any
  func keychainWrite(_ service: String, _ name: String, _ password: String) -> Any
  func keychainRead(_ service: String, _ name: String) -> Any
  func open(_ url: String) -> Bool
  func preferredLocalizations() -> Any
}

class JavascriptAPIUtils: JavascriptAPI, JavascriptAPIUtilsExportable {
  func keychainWrite(_ service: String, _ name: String, _ password: String) -> Any {
    if service.isEmpty {
      return false
    }
    let serviceName = "\(pluginInstance.plugin.identifier) - \(service)"
    do {
      try KeychainAccess.write(username: name, password: password, forService: .init(serviceName))
      return true
    } catch {
      return false
    }
  }
  
  func keychainRead(_ service: String, _ name: String) -> Any {
    if service.isEmpty {
      return false
    }
    let serviceName = "\(pluginInstance.plugin.identifier) - \(service)"
    do {
      let (_, result) = try KeychainAccess.read(username: name, forService: .init(serviceName))
      return result
    } catch {
      return false
    }
  }
  
  override func extraSetup() {
    context.evaluateScript("""
    iina.utils.ERROR_BINARY_NOT_FOUND = -1;
    iina.utils.ERROR_RUNTIME = -2;
    """)
  }

  func fileInPath(_ file: String) -> Bool {
    guard permitted(to: .accessFileSystem) else {
      return false
    }
    if file.isEmpty {
      return false
    }
    if let _ = searchBinary(file, in: Utility.binariesURL) ?? searchBinary(file, in: Utility.exeDirURL) {
      return true
    }
    if let path = parsePath(file, forceLocalPath: false).path {
      return FileManager.default.fileExists(atPath: path)
    }
    return false
  }

  func resolvePath(_ path: String) -> String? {
    guard permitted(to: .accessFileSystem) else {
      return nil
    }
    return parsePath(path).path
  }

  func exec(_ file: String, _ args_: Any, _ cwd: JSValue?, _ stdoutHook_: JSValue?, _ stderrHook_: JSValue?) -> JSValue? {
    guard permitted(to: .accessFileSystem) else {
      return nil
    }
    
    guard let args = args_ as? [String] else {
      throwError(withMessage: "The exec args parameter must be a string array")
      return nil
    }

    return createPromise { [unowned self] resolve, reject in
      var path = ""
      var args = args
      if !file.contains("/") {
        if let url = searchBinary(file, in: Utility.binariesURL) ?? searchBinary(file, in: Utility.exeDirURL) {
          // a binary included in IINA's bundle?
          if #available(macOS 13.0, *) {
            path = url.path(percentEncoded: false)
          } else {
            path = url.path
          }
        } else {
          path = "/usr/bin/env"
          args.insert(file, at: 0)
        }
      } else {
        // it should be an existing file
        if file.first == "/" {
          // an absolute path?
          path = file
        } else {
          path = parsePath(file).path ?? ""
        }
        // make sure the file exists
        guard FileManager.default.fileExists(atPath: path) else {
          reject.call(withArguments: [-1, "Cannot find the binary \(file)"])
          return
        }
      }

      // If this binary belongs to the plugin but doesn't have exec permission, try fix it
      if !FileManager.default.isExecutableFile(atPath: path) && (
        path.hasPrefix(self.pluginInstance.plugin.dataURL.path) ||
        path.hasPrefix(self.pluginInstance.plugin.tmpURL.path)) {
        do {
          try FileManager.default.setAttributes([.posixPermissions: NSNumber(integerLiteral: 0o755)], ofItemAtPath: path)
        } catch {
          reject.call(withArguments: [-2, "The binary is not executable, and execute permission cannot be added"])
          return
        }
      }

      let (stdout, stderr) = (Pipe(), Pipe())
      let process = Process()
      process.environment = ["LC_ALL": "en_US.UTF-8"]
      process.launchPath = path
      process.arguments = args
      if let cwd, cwd.isString, let cwdPath = parsePath(cwd.toString()).path {
        process.currentDirectoryPath = cwdPath
      }
      process.standardOutput = stdout
      process.standardError = stderr

      var stdoutHook: JSValue?
      var stderrHook: JSValue?
      if let hookVal = stdoutHook_, hookVal.isObject {
        stdoutHook = hookVal
      }
      if let hookVal = stderrHook_, hookVal.isObject {
        stderrHook = hookVal
      }

      let drained = DispatchGroup()
      let stdoutContent = JavascriptProcessOutput(stdout.fileHandleForReading, drained: drained, hook: stdoutHook)
      let stderrContent = JavascriptProcessOutput(stderr.fileHandleForReading, drained: drained, hook: stderrHook)
      Logger.log("Executing \(path) \(args.joined(separator: " "))", subsystem: pluginInstance.subsystem)
      do {
        try process.run()
      } catch {
        stdoutContent.cancel()
        stderrContent.cancel()
        reject.call(withArguments: ["Execution failed reporting: \(error.localizedDescription)"])
        return
      }

      self.pluginInstance.queue.async {
        process.waitUntilExit()
        drained.notify(queue: .main) {
          resolve.call(withArguments: [[
            "status": process.terminationStatus,
            "stdout": stdoutContent.content,
            "stderr": stderrContent.content
          ] as [String: Any]])
        }
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

  func open(_ url: String) -> Bool {
    // always open web links
    if let url = URL(string: url) {
      if url.scheme == "https" || url.scheme == "http" {
        NSWorkspace.shared.open(url)
        return true
      }
    }
    // might be a file path
    let (path, isLocal) = parsePath(url)
    guard let path else {
      log("utils.open: path cannot be found", level: .error)
      return false
    }
    let fileURL = URL(fileURLWithPath: path)
    if isLocal {
      NSWorkspace.shared.open(fileURL)
      return true
    }
    return whenPermitted(to: .accessFileSystem) {
      NSWorkspace.shared.open(fileURL)
      return true
    } ?? false
  }

  func preferredLocalizations() -> Any {
    return Bundle.main.preferredLocalizations
  }
}
