//
//  FileGroup.swift
//  iina
//
//  Created by lhc on 20/5/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

fileprivate let subsystem = Logger.makeSubsystem("fgroup")

class FileInfo: Hashable {
  var url: URL
  var path: String
  var filename: String
  var ext: String
  var nameInSeries: String?
  var characters: [Character]
  var dist: [FileInfo: UInt] = [:]
  var minDist: [FileInfo] = []
  var relatedSubs: [FileInfo] = []
  var priorityStringOccurrences = 0
  var isMatched = false

  var prefix: String {  // prefix detected by FileGroup
    didSet {
      if prefix.count < self.characters.count {
        suffix = String(filename[filename.index(filename.startIndex, offsetBy: prefix.count)...])
        getNameInSeries()
      } else {
        prefix = ""
        suffix = self.filename
      }
    }
  }
  var suffix: String  // filename - prefix

  init(_ url: URL) {
    self.url = url
    self.path = url.path
    self.ext = url.pathExtension
    self.filename = url.deletingPathExtension().lastPathComponent
    self.characters = [Character](self.filename)
    self.prefix = ""
    self.suffix = self.filename
  }

  private func getNameInSeries() {
    // e.g. "abc_" "ch01_xxx" -> "ch01"
    var firstDigit = false
    let name = suffix.unicodeScalars.prefix {
      if CharacterSet.decimalDigits.contains($0) {
        if !firstDigit {
          firstDigit = true
        }
      } else {
        if firstDigit {
          return false
        }
      }
      return true
    }
    self.nameInSeries = String(name)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(path)
  }
  
  static func == (lhs: FileInfo, rhs: FileInfo) -> Bool {
    return lhs.path == rhs.path
  }
}


class FileGroup {

  var prefix: String
  var contents: [FileInfo]
  var groups: [FileGroup]

  private let chineseNumbers: [Character] = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

  static func group(files: [FileInfo]) -> FileGroup {
    Logger.log("Start grouping \(files.count) files", subsystem: subsystem)
    let group = FileGroup(prefix: "", contents: files)
    group.tryGroupFiles()
    return group
  }

  init(prefix: String, contents: [FileInfo] = []) {
    self.prefix = prefix
    self.contents = contents
    self.groups = []
  }

  private func tryGroupFiles() {
    Logger.log("Try group files, prefix=\(prefix), count=\(contents.count)", level: .verbose, subsystem: subsystem)
    guard contents.count >= 3 else {
      Logger.log("Contents count < 3, skipped", level: .verbose, subsystem: subsystem)
      return
    }

    var tempGroup: [String: [FileInfo]] = [:]
    var currChars: [(Character, String)] = []
    var i = prefix.count

    while tempGroup.count < 2 {
      var lastPrefix = prefix
      var anyProcessed = false
      for finfo in contents {
        // if reached string end
        if i >= finfo.characters.count {
          tempGroup[prefix, default: []].append(finfo)
          currChars.append(("/", prefix))
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
        anyProcessed = true
      }
      // if all items have the same prefix
      if tempGroup.count == 1 {
        prefix = lastPrefix
        tempGroup.removeAll()
        currChars.removeAll()
      }
      i += 1
      // if all items have the same name
      if !anyProcessed {
        break
      }
    }

    let maxSubGroupCount = tempGroup.reduce(0, { max($0, $1.value.count) })
    if stopGrouping(currChars) || maxSubGroupCount < 3 {
      Logger.log("Stop grouping, maxSubGroup=\(maxSubGroupCount)", level: .verbose, subsystem: subsystem)
      contents.forEach { $0.prefix = self.prefix }
    } else {
      Logger.log("Continue grouping, groups=\(tempGroup.count), chars=\(currChars)", level: .verbose, subsystem: subsystem)
      groups = tempGroup.map { FileGroup(prefix: $0.0, contents: $0.1) }
      // continue
      for g in groups {
        g.tryGroupFiles()
      }
    }
  }

  func flatten() -> [String: [FileInfo]] {
    var result: [String: [FileInfo]] = [:]
    func search(_ group: FileGroup) {
      if group.groups.count > 0 {
        for g in group.groups {
          search(g)
        }
      } else {
        result[group.prefix] = group.contents
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
      if chineseNumbers.contains(c) { chineseNumberCount += 1 }
      if chineseNumberCount >= 3 { return true }
    }
    return false
  }

}

