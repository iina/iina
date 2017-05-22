//
//  FileGroup.swift
//  iina
//
//  Created by lhc on 20/5/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

class FileGroup {

  class FileInfo {
    var filename: String
    var url: URL
    var characters: [Character]

    init(_ url: URL) {
      self.url = url
      self.filename = url.deletingPathExtension().lastPathComponent
      self.characters = [Character](self.filename.characters)
    }
  }

  var prefix: String
  var contents: [FileInfo]
  var groups: [FileGroup]

  private let chineseNumbers: [Character] = ["零", "一", "十", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

  static func group(files: [URL]) -> FileGroup {
    let fileInfo = files.map { FileInfo($0) }
    let group = FileGroup(prefix: "", contents: fileInfo)
    group.tryGroupFiles()
    return group
  }

  init(prefix: String, contents: [FileInfo] = []) {
    self.prefix = prefix
    self.contents = contents
    self.groups = []
  }

  private func tryGroupFiles() {
    guard contents.count >= 3 else { return }

    var tempGroup: [String: [FileInfo]] = [:]
    var currChars: [(Character, String)] = []
    var i = prefix.characters.count

    var shouldContinue = true
    while tempGroup.count < 2 && shouldContinue {
      var lastPrefix = ""
      for finfo in contents {
        if i >= finfo.characters.count {
          shouldContinue = false
          continue
        }
        let c = finfo.characters[i]
        var p = prefix
        p.append(c)
        lastPrefix = p
        if tempGroup[p] == nil {
          tempGroup[p] = []
          currChars.append((c, p))
        }
        tempGroup[p]!.append(finfo)
      }
      // if all items have the same prefix
      if tempGroup.count == 1 {
        prefix = lastPrefix
        tempGroup.removeAll()
        currChars.removeAll()
      }
      i += 1
    }

    if !stopGrouping(currChars) {
      groups = tempGroup.map { FileGroup(prefix: $0, contents: $1) }
      // continue
      for g in groups {
        g.tryGroupFiles()
      }
    }
  }

  func flatten() -> [String: [String]] {
    var result: [String: [String]] = [:]
    var search: ((FileGroup) -> Void)!
    search = { group in
      if group.groups.count > 0 {
        for g in group.groups {
          search(g)
        }
      } else if group.prefix.characters.count >= 5 {
        result[group.prefix] = group.contents.map { $0.url.path }
      }
    }
    search(self)
    return result
  }

  private func stopGrouping(_ chars: [(Character, String)]) -> Bool {
    var chineseNumberCount = 0
    for (c, _) in chars {
      if c >= "0" && c <= "9" { return true }
      // chinese characters
      if chineseNumbers.contains(c) { chineseNumberCount += 1}
      if chineseNumberCount >= 3 { return true }
    }
    return false
  }

}

