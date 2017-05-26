//
//  FileGroup.swift
//  iina
//
//  Created by lhc on 20/5/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

fileprivate let GroupPrefixMinLength = 7
fileprivate let GroupFilenameMaxLength = 12


class FileInfo: Hashable {
  var url: URL
  var path: String
  var filename: String
  var ext: String
  var characters: [Character]
  var dist: [FileInfo: UInt] = [:]
  var minDist: [FileInfo] = []
  var segments: [String] = []
  var priorityStringOccurances = 0

  init(_ url: URL) {
    self.url = url
    self.path = url.path
    self.ext = url.pathExtension
    self.filename = url.deletingPathExtension().lastPathComponent
    self.characters = [Character](self.filename.characters)
    self.getSegments()
  }

  private func getSegments() {
    var currentSegemnt = ""
    let firstChar = filename.characters.first!
    var currentSegmentIsDigit = firstChar >= "0" && firstChar <= "9"
    for char in filename.characters {
      let isDigit = char >= "0" && char <= "9"
      if isDigit != currentSegmentIsDigit {
        segments.append(currentSegemnt)
        currentSegemnt = String(char)
        currentSegmentIsDigit = isDigit
      } else {
        currentSegemnt.append(char)
      }
    }
    segments.append(currentSegemnt)
  }

  var hashValue: Int {
    return path.hashValue
  }

  static func == (lhs: FileInfo, rhs: FileInfo) -> Bool {
    return lhs.path == rhs.path
  }
}


class FileGroup {

  var prefix: String
  var contents: [FileInfo]
  var groups: [FileGroup]

  private let chineseNumbers: [Character] = ["零", "一", "十", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

  static func group(files: [FileInfo]) -> FileGroup {
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
      } else {
        let filenameMaxLength = group.contents.reduce(0, { max($0, $1.characters.count) })
        if group.prefix.characters.count >= GroupPrefixMinLength && filenameMaxLength > GroupFilenameMaxLength {
          result[group.prefix] = group.contents.map { $0.url.path }
        }
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

