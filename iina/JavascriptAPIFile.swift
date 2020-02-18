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
}

class JavascriptAPIFile: JavascriptAPI, JavascriptAPIFileExportable {

  private let fileManager = FileManager.default
  
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
}
