//
//  JavascriptAPIFile.swift
//  iina
//
//  Created by Collider LI on 22/9/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

@objc protocol JavascriptAPIFileExportable: JSExport {
  func list(_ path: String, _ options: [String: Any]) -> [[String: Any]]?
  func exists(_ path: String) -> Bool
  func write(_ path: String, _ content: String)
  func read(_ path: String, _ options: [String: Any]) -> Any?
  func trash(_ path: String)
  func delete(_ path: String)
  func revealInFinder(_ path: String)
  func handle(_ path: String, _ mode: String) -> JavascriptFileHandle?
}

class JavascriptAPIFile: JavascriptAPI, JavascriptAPIFileExportable {
  func exists(_ path: String) -> Bool {
    guard let filePath = parsePath(path).path else { return false }

    return FileManager.default.fileExists(atPath: filePath)
  }

  func list(_ path: String, _ options: [String: Any]) -> [[String: Any]]? {
    guard let dirPath = parsePath(path).path else { return nil }

    var fmOptions: FileManager.DirectoryEnumerationOptions = []
    if !(options["includeSubDir"] as? Bool == true) {
      fmOptions.insert([
        .skipsPackageDescendants,
        .skipsSubdirectoryDescendants
      ])
    }

    let urls = try? FileManager.default.contentsOfDirectory(
      at: URL(fileURLWithPath: dirPath),
      includingPropertiesForKeys: [.isDirectoryKey],
      options:fmOptions
    )

    return urls?.map {
      ["filename": $0.lastPathComponent, "isDir": $0.isExistingDirectory]
    }
  }

  func write(_ path: String, _ content: String) {
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

  func read(_ path: String, _ options: [String: Any]) -> Any? {
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

  func trash(_ path: String) {
    guard let filePath = parsePath(path).path else { return }

    do {
      try FileManager.default.trashItem(at: URL(fileURLWithPath: filePath), resultingItemURL: nil)
    } catch let error {
      throwError(withMessage: "Cannot trash file: \(error.localizedDescription)")
    }
  }

  func delete(_ path: String) {
    let (filePath_, local) = parsePath(path)
    guard let filePath = filePath_ else { return }

    guard local else {
      throwError(withMessage: "file.delete can only be called for @tmp and @data files.")
      return
    }
    do {
      try FileManager.default.removeItem(atPath: filePath)
    } catch let error {
      throwError(withMessage: "Cannot delete file: \(error.localizedDescription)")
    }
  }

  func move(_ source: String, _ dest: String) {
    guard let sourcePath = parsePath(source).path, let destPath = parsePath(dest).path else { return }

    do {
      try FileManager.default.moveItem(atPath: sourcePath, toPath: destPath)
    } catch let error {
      throwError(withMessage: "Cannot move file: \(error.localizedDescription)")
    }
  }

  func revealInFinder(_ path: String) {
    guard let filePath = parsePath(path).path else { return }

    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: filePath)])
  }

  func handle(_ path: String, _ mode: String) -> JavascriptFileHandle? {
    guard let filePath = parsePath(path).path else { return nil }

    let handleMode: JavascriptFileHandle.Mode
    switch mode {
    case "read":
      handleMode = .read
    case "write":
      handleMode = .write
    default:
      throwError(withMessage: "file.handle: moude should be \"read\" or \"write\".")
      return nil
    }
    if let handle = JavascriptFileHandle(url: URL(fileURLWithPath: filePath), mode: handleMode) {
      return handle
    }
    throwError(withMessage: "file.handle: cannot create file handle")
    return nil
  }
}


@objc protocol JavascriptFileHandleExportable: JSExport {
  func offset() -> UInt64
  func seekTo(_ offset: UInt64)
  func seekToEnd()
  func read(_ length: Int) -> Any?
  func readToEnd() -> Any?
  func write(_ data: JSValue)
  func close()
}

class JavascriptFileHandle: NSObject, JavascriptFileHandleExportable {
  enum Mode {
    case read, write
  }

  private var handle: FileHandle
  private var mode: Mode

  init?(url: URL, mode: Mode) {
    do {
      self.handle = mode == .read ? try FileHandle(forReadingFrom: url) : try FileHandle(forWritingTo: url)
      self.mode = mode
    } catch {
      return nil
    }
  }

  func offset() -> UInt64 {
    return handle.offsetInFile
  }

  func seekTo(_ offset: UInt64) {
    handle.seek(toFileOffset: offset)
  }

  func seekToEnd() {
    handle.seekToEndOfFile()
  }

  func read(_ length: Int) -> Any? {
    guard mode == .read else {
      return nil
    }
    return createUInt8Array(fromData: handle.readData(ofLength: length))
  }

  func readToEnd() -> Any? {
    guard mode == .read else {
      return nil
    }
    return createUInt8Array(fromData: handle.readDataToEndOfFile())
  }

  func write(_ data: JSValue) {
    if data.isString {
      if let utf8Data = data.toString()!.data(using: .utf8) {
        handle.write(utf8Data)
      }
      return
    }

    let context = JSContext.current()!
    var buffer: [UInt8] = []
    let setter: @convention(block) (UInt8) -> Void = { value in
      buffer.append(value)
    }
    context.setObject(setter, forKeyedSubscript: "__iina_data_setter" as NSString)
    context.setObject(data, forKeyedSubscript: "__iina_data_value" as NSString)
    context.evaluateScript("""
    for (value of __iina_data_value) {
      __iina_data_setter(value);
    }
    """)
    context.setObject(nil, forKeyedSubscript: "__iina_data_setter" as NSString)
    context.setObject(nil, forKeyedSubscript: "__iina_data_value" as NSString)

    handle.write(Data(buffer))
  }

  func close() {
    handle.closeFile()
  }

  private func createUInt8Array(fromData data: Data) -> JSValue? {
    let context = JSContext.current()!
    let length = data.count
    let getter: @convention(block) (Int) -> UInt8 = { offset in
      return data[offset]
    }
    context.setObject(getter, forKeyedSubscript: "__iina_data_getter" as NSString)

    let array = context.evaluateScript("""
    Uint8Array.from(function* () {
      for (let i = 0; i < \(length); i++) {
        yield __iina_data_getter(i);
      }
    }())
    """)

    context.setObject(nil, forKeyedSubscript: "__iina_data_getter" as NSString)
    return array
  }
}
