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
  // Registry is main-owned; each child serializes its IO and cancellation.
  private var processes: [UUID: JavascriptPluginProcess] = [:]

  override func cleanUp(_ instance: JavascriptPluginInstance) {
    dispatchPrecondition(condition: .onQueue(.main))
    processes.values.forEach { $0.cancel() }
    processes.removeAll()
  }

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

    return createPromise { [unowned self] reply in
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
          // assume it's a system command
          let useBash = false
          if useBash {
            path = "/bin/bash"
            args.insert(file, at: 0)
            args = ["-c", args.map {
              $0.replacingOccurrences(of: " ", with: "\\ ")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\"", with: "\\\"")
            }.joined(separator: " ")]
          } else {
            args.insert(file, at: 0)
          }
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
          reply.reject([-1, "Cannot find the binary \(file)"])
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
          reply.reject([-2, "The binary is not executable, and execute permission cannot be added"])
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

      let hooks = [stdoutHook_, stderrHook_].map { value -> JavascriptPluginCallback? in
        guard let value, value.isObject else { return nil }
        return pluginInstance.makeCallback([value], once: false)
      }
      let id = UUID()
      let operation = JavascriptPluginProcess(process: process, pipes: [stdout, stderr], hooks: hooks) { [weak self] result in
        dispatchPrecondition(condition: .onQueue(.main))
        self?.processes.removeValue(forKey: id)
        hooks.forEach { $0?.cancel() }
        switch result {
        case .success(let output): reply.resolve([output])
        case .failure(let error): reply.reject(["Execution failed reporting: \(error.localizedDescription)"])
        }
      }
      guard let instance = pluginInstance, instance.isActive else { return }
      processes[id] = operation
      Logger.log("Executing \(path) \(args.joined(separator: " "))", subsystem: pluginInstance.subsystem)
      operation.start()

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
    return createPromise { reply in
      Utility.quickOpenPanel(title: title, chooseDir: chooseDir, allowedFileTypes: allowedFileTypes) { result in
        reply.resolve([result.path])
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

/// Owns the direct child and its pipe readers independently of JavaScript delivery.
/// All IO state is confined to `queue`; completion runs on the main queue.
private final class JavascriptPluginProcess {
  private let process: Process
  private let pipes: [Pipe]
  private let hooks: [JavascriptPluginCallback?]
  private let completion: (Result<[String: Any], Error>) -> Void
  private let queue = DispatchQueue(label: "com.colliderli.iina.plugin.exec")
  private var sources: [DispatchSourceRead] = []
  private var output = [Data(), Data()]
  private var closed = [false, false]
  private var exited = false
  private var cancelled = false
  private var completed = false

  init(process: Process, pipes: [Pipe], hooks: [JavascriptPluginCallback?],
       completion: @escaping (Result<[String: Any], Error>) -> Void) {
    self.process = process
    self.pipes = pipes
    self.hooks = hooks
    self.completion = completion
  }

  func start() {
    queue.async { [self] in startOnQueue() }
  }

  private func startOnQueue() {
    // Install readers before launch, but resume them only after Process has inherited
    // the pipes. A failed launch closes both ends without waiting for an exit event.
    for (index, pipe) in pipes.enumerated() {
      let handle = pipe.fileHandleForReading
      let fd = handle.fileDescriptor
      _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
      let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
      source.setEventHandler { [self] in drain(index) }
      source.setCancelHandler { handle.closeFile() }
      sources.append(source)
    }
    process.terminationHandler = { [self] _ in
      queue.async { [self] in
        exited = true
        // Drain data already in the pipes before reporting completion. Descendants
        // do not own this exec call; do not wait for them to close inherited writers.
        for index in pipes.indices { drain(index); close(index) }
        finishIfReady()
      }
    }
    do {
      try process.run()
      sources.forEach { $0.resume() }
    } catch {
      completed = true
      process.terminationHandler = nil
      sources.forEach { $0.setEventHandler(handler: nil); $0.resume(); $0.cancel() }
      pipes.forEach { $0.fileHandleForWriting.closeFile() }
      DispatchQueue.main.async { [completion] in completion(.failure(error)) }
    }
  }

  func cancel() {
    queue.async { [self] in
      guard !completed, !cancelled else { return }
      cancelled = true
      // Detach readers even if the child refuses termination. Never wait on the UI.
      for index in pipes.indices { close(index) }
      if process.isRunning { process.terminate() }
      queue.asyncAfter(deadline: .now() + 1) { [self] in
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
      }
      finishIfReady()
    }
  }

  private func drain(_ index: Int) {
    guard !closed[index] else { return }
    var bytes = [UInt8](repeating: 0, count: 8192)
    while true {
      let count = read(pipes[index].fileHandleForReading.fileDescriptor, &bytes, bytes.count)
      if count > 0 {
        output[index].append(contentsOf: bytes.prefix(count))
        if !cancelled, let text = String(bytes: bytes.prefix(count), encoding: .utf8) {
          hooks[index]?.call(withArguments: [text])
        }
      } else if count < 0 && errno == EINTR {
        continue
      } else {
        if count == 0 || (errno != EAGAIN && errno != EWOULDBLOCK) { close(index) }
        break
      }
    }
  }

  private func close(_ index: Int) {
    guard !closed[index] else { return }
    closed[index] = true
    sources[index].setEventHandler(handler: nil)
    sources[index].cancel()
  }

  private func finishIfReady() {
    guard exited, closed.allSatisfy({ $0 }), !completed else { return }
    completed = true
    process.terminationHandler = nil
    let result: [String: Any] = ["status": process.terminationStatus,
                                 "stdout": String(decoding: output[0], as: UTF8.self),
                                 "stderr": String(decoding: output[1], as: UTF8.self)]
    DispatchQueue.main.async { [completion] in completion(.success(result)) }
  }
}
