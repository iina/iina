//
//  SettingsSearch.swift
//  iina
//
//  Created by Hechen Li on 2026-05-11.
//  Copyright © 2026 lhc. All rights reserved.
//

fileprivate class Trie {
  class Node {
    var children: [Node] = []
    let char: Character
    init(_ c: Character) {
      char = c
    }
  }

  let entry: SettingsSearch.Entry

  private let root: Node
  private var lastPosition: Node
  var active: Bool

  init(_ entry: SettingsSearch.Entry) {
    self.entry = entry
    self.root = Node(" ")
    self.lastPosition = root
    self.active = true

    let s = [[entry.title], entry.extraTerms]
      .flatMap { $0 }.compactMap { $0 }.joined(separator: " ").lowercased()
    let strings = s.components(separatedBy: " ")
    for string in strings {
      var t = string
      while t.count != 0 {
        addString(t)
        t.removeFirst()
      }
    }
  }

  func reset() {
    lastPosition = root
    active = true
  }

  func addString(_ str: String) {
    var current = root
    for c in Array(str) {
      if let next = current.children.first(where: { $0.char == c }) {
        current = next
      } else {
        let newNode = Node(c)
        current.children.append(newNode)
        current = newNode
      }
    }
  }

  func search(_ str: String) {
    for c in str {
      // half-width and full-width spaces
      if c == " " || c == "　" {
        lastPosition = root
        continue
      }
      if let next = lastPosition.children.first(where: { $0.char == c }) {
        lastPosition = next
      } else {
        active = false
        return
      }
    }
  }
}


struct SettingsSearch {
  class Entry {
    let page: String
    let anchor: Int
    let title: String
    let isMain: Bool
    let extraTerms: [String] = []
    let section: String?
    let parent: Int?

    let icon: NSImage?

    var pageTitle: String?
    var parentEntry: Entry?
    var mainEntry: Entry?

    var isPageHeader: Bool {
      icon != nil
    }

    var titleForDisplay: String {
      mainEntry?.title ?? title
    }

    init(page: String, anchor: Int, title: String, isMain: Bool, section: String?, parent: Int?, icon: NSImage? = nil) {
      self.page = page
      self.anchor = anchor
      self.title = title
      self.isMain = isMain
      self.section = section
      self.parent = parent
      self.icon = icon
    }

    /// For displaying group headers in the result table
    convenience init(pageHeader header: String, icon: NSImage) {
      self.init(page: header, anchor: -1, title: "", isMain: false, section: nil, parent: nil, icon: icon)
    }

    static func assignMainAndParentEntries(_ entries: [Entry]) {
      let dict = Dictionary(grouping: entries, by: \.anchor)
      for (_, group) in dict {
        let mainEntry = group.first(where: \.isMain)
        group.filter { !$0.isMain }.forEach { $0.mainEntry = mainEntry }
      }
      for entry in entries where entry.parent != nil {
        entry.parentEntry = dict[entry.parent!]?.first(where: \.isMain)
      }
    }
  }

  struct Context {
    let page: String
    let section: String?
    let parent: Int?

    func with(section: String?) -> Self {
      .init(page: page, section: section, parent: parent)
    }

    func with(parent: Int?) -> Self {
      .init(page: page, section: section, parent: parent)
    }

    func add(_ tag: Int, _ entry: String?, isMain: Bool = false) {
      guard let entry else { return }
      entries.append(.init(page: page, anchor: tag, title: entry,
                           isMain: isMain, section: section, parent: parent))
    }
  }

  static var entries: [Entry] = []

  static private var tries: [Trie] = []
  static private var lastString: String = ""

  static func makeTries() {
    Entry.assignMainAndParentEntries(entries)
    for entry in entries {
      add(entry: entry)
    }
  }

  static func search(_ searchString: String) -> [SettingsSearch.Entry]? {
    if searchString == lastString {
      return nil
    }
    if searchString.hasPrefix(lastString) {
      tries.filter { $0.active }.forEach { $0.search(String(searchString.dropFirst(lastString.count))) }
    } else {
      tries.forEach { $0.reset(); $0.search(searchString) }
    }
    lastString = searchString
    return tries.filter { $0.active }.map { $0.entry }
  }

  static func add(entry: SettingsSearch.Entry) {
    tries.append(Trie(entry))
  }
}

