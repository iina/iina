//
//  JavascriptAPIHttp.swift
//  iina
//
//  Created by Collider LI on 12/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore
import Just

fileprivate typealias JustRequestFunc = (URLComponentsConvertible, [String : Any], [String : Any]) -> HTTPResult

@objc protocol JavascriptAPIHttpExportable: JSExport {
  func get(_ url: String, _ options: [String: Any]?) -> JSValue?
  func post(_ url: String, _ options: [String: Any]?) -> JSValue?
  func put(_ url: String, _ options: [String: Any]?) -> JSValue?
  func patch(_ url: String, _ options: [String: Any]?) -> JSValue?
  func delete(_ url: String, _ options: [String: Any]?) -> JSValue?
  func xmlrpc(_ location: String) -> JavascriptAPIXmlrpc?
  func download(_ url: String, _ dest: String, _ options: [String: Any]?) -> JSValue?
}

class JavascriptAPIHttp: JavascriptAPI, JavascriptAPIHttpExportable {
  // Just's async result does not expose its task until completion. Keep its request
  // encoding, but use an instance-owned session so teardown can cancel pending IO.
  private let session = URLSession(configuration: .default)
  // Main-owned registry. Each write owns a separate, irrevocable cancellation
  // token so a new instance cannot revive an old instance's pending download.
  private var downloads: [UUID: JavascriptPluginDownload] = [:]
  private let downloadQueue = DispatchQueue(label: "com.colliderli.iina.plugin.download", qos: .utility)

  override func cleanUp(_ instance: JavascriptPluginInstance) {
    dispatchPrecondition(condition: .onQueue(.main))
    downloads.values.forEach { $0.cancel() }
    downloads.removeAll()
    session.invalidateAndCancel()
  }

  private func perform(_ method: HTTPMethod, url: String, params: [String: String],
                       data: [String: Any], headers: [String: String],
                       completion: @escaping (HTTPResult) -> Void) {
    let builder = HTTP(session: session)
    guard let request = builder.synthesizeRequest(method, url: url, params: params,
      data: data, json: nil, headers: .init(dictionary: headers), files: [:], auth: nil,
      timeout: nil, urlQuery: nil, requestBody: nil) else {
      completion(HTTPResult(data: nil, response: nil,
                           error: URLError(.badURL), task: nil))
      return
    }
    session.dataTask(with: request) { data, response, error in
      completion(HTTPResult(data: data, response: response, error: error, task: nil))
    }.resume()
  }


  @objc func get(_ url: String, _ options: [String: Any]?) -> JSValue? {
    return request(.get, url: url, options: options)
  }

  @objc func post(_ url: String, _ options: [String: Any]?) -> JSValue? {
    return request(.post, url: url, options: options)
  }

  @objc func put(_ url: String, _ options: [String: Any]?) -> JSValue? {
    return request(.put, url: url, options: options)
  }

  @objc func patch(_ url: String, _ options: [String: Any]?) -> JSValue? {
    return request(.patch, url: url, options: options)
  }

  @objc func delete(_ url: String, _ options: [String: Any]?) -> JSValue? {
    return request(.delete, url: url, options: options)
  }

  @objc func xmlrpc(_ location: String) -> JavascriptAPIXmlrpc? {
    guard let instance = pluginInstance, instance.isActive else { return nil }
    guard hostIsValid(location) else {
      return nil
    }
    return JavascriptAPIXmlrpc(context: context, pluginInstance: pluginInstance, location: location, session: session)
  }

  func download(_ url: String, _ dest: String, _ options: [String: Any]?) -> JSValue? {
    return whenPermitted(to: .networkRequest) {
      guard hostIsValid(url) else {
        throwError(withMessage: "URL is not allowed.")
        return nil
      }
      guard let method = HTTPMethod(rawValue: options?["method"] as? String ?? "GET") else {
        throwError(withMessage: "method is invalid.")
        return nil
      }
      guard let destPath = self.parsePath(dest).path else {
        throwError(withMessage: "Not allowed to write to the destination.")
        return nil
      }
      let params = options?["params"] as? [String: String]
      let headers = options?["headers"] as? [String: String]
      let data = options?["data"] as? [String: Any]
      return createPromise { reply in
        let operation = JavascriptPluginDownload(stagingDirectory: self.pluginInstance.plugin.tmpURL)
        self.downloads[operation.id] = operation
        let queue = self.downloadQueue
        self.perform(method, url: url,
                     params: params ?? [:], data: data ?? [:], headers: headers ?? [:]) { [weak self] response in
          queue.async {
            var writeError = false
            if response.ok, let content = response.content {
              do { try operation.write(content, to: URL(fileURLWithPath: destPath)) }
              catch { writeError = true }
            }
            DispatchQueue.main.async {
              self?.downloads.removeValue(forKey: operation.id)
              if writeError { reply.reject(["Unable to write to the destination."]) }
              else if response.ok { reply.resolve([]) }
              else { reply.reject([response.toDict()]) }
            }
          }
        }
      }
    }
  }

  private func request(_ method: HTTPMethod, url: String, options: [String: Any]?) -> JSValue? {
    return whenPermitted(to: .networkRequest) {
      // check host
      guard hostIsValid(url) else {
        return JSValue(undefinedIn: context)
      }
      // request
      let params = options?["params"] as? [String: String]
      let headers = options?["headers"] as? [String: String]
      let data = options?["data"] as? [String: Any]
      return createPromise { reply in
        self.perform(method, url: url,
                     params: params ?? [:],
                     data: data ?? [:],
                     headers: headers ?? [:],
                     completion: { response in
          if response.ok { reply.resolve([response.toDict()]) }
          else { reply.reject([response.toDict()]) }
        })
      }
    }
  }

  private func hostIsValid(_ url: String) -> Bool {
    guard let urlComponents = URLComponents(string: url.addingPercentEncoding(withAllowedCharacters: .urlAllowed) ?? url) else {
      throwError(withMessage: "URL \(url) is invalid.")
      return false
    }
    guard pluginInstance.canAccess(url: urlComponents.url!) else {
      throwError(withMessage: "URL \(url) is not allowed.")
      return false
    }
    return true
  }
}

@objc protocol JavascriptAPIXmlrpcExportable: JSExport {
  func call(_ method: String, _ args: [Any]) -> JSValue?
}

class JavascriptAPIXmlrpc: JavascriptAPI, JavascriptAPIXmlrpcExportable {
  private let xmlrpc: JustXMLRPC

  init(context: JSContext, pluginInstance: JavascriptPluginInstance, location: String, session: URLSession) {
    self.xmlrpc = JustXMLRPC(location, session: session)
    super.init(context: context, pluginInstance: pluginInstance)
  }

  @objc func call(_ method: String, _ args: [Any]) -> JSValue? {
    return createPromise { reply in
      self.xmlrpc.call(method, args) { response in
        switch response {
        case .ok(let returnValue):
          reply.resolve([returnValue])
        case .failure:
          reply.reject([])
        case .error(let err):
          reply.reject([[
            "httpCode": err.httpCode,
            "reason": err.reason,
            "description": err.readableDescription,
          ] as [String: Any]])
        }
      }
    }
  }
}

fileprivate extension HTTPResult {
  func toDict() -> [String: Any?] {
    return [
      "statusCode": statusCode,
      "reason": reason,
      "data": json,
      "text": text
    ]
  }
}

/// Stages the body off main, then writes through the destination as Data.write
/// does: preserve existing inodes/permissions and follow symbolic links. Once
/// publication starts, cancellation or an IO error may leave a partial file.
/// Cancellation owns removal of the staging name; it never joins the writer.
/// Destination mutation is serialized with cancellation one syscall at a time,
/// so no further bytes can be published after cancel returns. Filesystem syscall
/// latency is not bounded, even though body IO never runs on main.
final class JavascriptPluginDownload {
  let id = UUID()
  private let lock = NSLock()
  private var cancelled = false
  private var started = false
  private var stagingPath: String?
  private let stagingDirectory: URL

  init(stagingDirectory: URL) {
    self.stagingDirectory = stagingDirectory
  }

  func cancel() {
    lock.lock()
    defer { lock.unlock() }
    cancelled = true
    removeStagingFile()
  }

  // Caller holds lock. The writer retains its fd, not the directory entry: an
  // unlinked file disappears on process exit even if the writer never resumes.
  private func removeStagingFile() {
    if let path = stagingPath {
      if unlink(path) == 0 || errno == ENOENT { stagingPath = nil }
    }
  }

  private func checkCancellation() throws {
    lock.lock()
    let stopped = cancelled
    lock.unlock()
    if stopped { throw URLError(.cancelled) }
  }

  private func createStagingFile() throws -> Int32 {
    lock.lock()
    defer { lock.unlock() }
    guard !cancelled, !started else { throw URLError(.cancelled) }
    started = true
    let path = stagingDirectory.appendingPathComponent(".iina-download-\(id.uuidString)").path
    let fd = open(path, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { throw URLError(.cannotCreateFile) }
    // Creation and ownership are indivisible with respect to cancellation.
    stagingPath = path
    return fd
  }

  private func openDestination(_ destination: URL) throws -> Int32 {
    lock.lock()
    defer { lock.unlock() }
    guard !cancelled else { throw URLError(.cancelled) }
    // O_TRUNC preserves the existing inode and mode, follows symlinks (including
    // dangling links), and applies the process umask/parent ACL for a new file.
    let fd = open(destination.path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o666)
    guard fd >= 0 else { throw URLError(.cannotCreateFile) }
    return fd
  }

  func write(_ data: Data, to destination: URL) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let fd = try createStagingFile()
    defer {
      close(fd)
      lock.lock()
      removeStagingFile()
      lock.unlock()
    }
    try data.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        try checkCancellation()
        let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), min(256 * 1024, bytes.count - offset))
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { throw URLError(.cannotWriteToFile) }
        offset += count
      }
    }
    guard lseek(fd, 0, SEEK_SET) >= 0 else { throw URLError(.cannotOpenFile) }
    let output = try openDestination(destination)
    defer { close(output) }
    var buffer = [UInt8](repeating: 0, count: 256 * 1024)
    while true {
      try checkCancellation()
      let count = read(fd, &buffer, buffer.count)
      if count < 0 && errno == EINTR { continue }
      guard count >= 0 else { throw URLError(.cannotDecodeContentData) }
      if count == 0 { break }
      try buffer.withUnsafeBytes { bytes in
        var offset = 0
        while offset < count {
          lock.lock()
          if cancelled {
            lock.unlock()
            throw URLError(.cancelled)
          }
          let written = Darwin.write(output, bytes.baseAddress!.advanced(by: offset), count - offset)
          let code = errno
          lock.unlock()
          if written < 0 && code == EINTR { continue }
          guard written > 0 else { throw URLError(.cannotWriteToFile) }
          offset += written
        }
      }
    }
  }
}
