//
//  JavascriptAPIFile.swift
//  iina
//
//  Created by Yuze Jiang on 2/17/20.
//  Copyright © 2020 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

@objc protocol JavascriptAPIFileExportable: JSExport {
  func getFileNamesFromCurrentDir() -> JSValue
  func write(_ fileName: String, _ content: String)
  func read(_ fileName: String) -> String
}

class JavascriptAPIFile: JavascriptAPI, JavascriptAPIFileExportable {

  private let fileManager = FileManager.default

  private lazy var dataURL: URL = {
    let url = Utility.pluginsURL.appendingPathComponent(".data", isDirectory: true)
      .appendingPathComponent(pluginInstance.plugin.identifier, isDirectory: true)
    Utility.createDirIfNotExist(url: url)
    return url
  }()

  private lazy var dataFolderPath: String = {
    return dataURL.path + "/"
  }()

  static func currentDir(_ player: PlayerCore) -> URL? {
    let folder = player.info.currentURL?.deletingLastPathComponent()
    return folder?.isFileURL ?? false ? folder : nil
  }

  @objc func getFileNamesFromCurrentDir() -> JSValue {
    guard let folder = JavascriptAPIFile.currentDir(player) else { return JSValue(nullIn: context) }
    let urls: [String]
    do {
      urls = try fileManager.contentsOfDirectory(atPath: folder.path)
    } catch (let err) {
      log(err as! String, level: .error)
      return JSValue(newErrorFromMessage: "Error when fetching contents of directory.", in: context)
    }
    return JSValue(object: urls, in: context)
  }

  @objc func write(_ fileName: String, _ content: String) {
    do {
      try content.write(toFile: dataFolderPath + fileName, atomically: true, encoding: .utf8)
    } catch {
      throwError(withMessage: "Error when write to file \(fileName)")
    }
  }

  @objc func read(_ fileName: String) -> String {
    guard let streamReader = StreamReader(path: dataFolderPath + fileName) else {
      throwError(withMessage: "Cannot open the file.")
      return ""
    }
    var ret = ""
    while let line = streamReader.nextLine() {
      ret += line
    }
    return ret
  }
}
