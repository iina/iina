//
//  PreferenceWindowController.swift
//  iina
//
//  Created by Collider LI on 6/7/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

protocol PreferenceWindowEmbeddable where Self: NSViewController {
  var preferenceTabTitle: String { get }
  var preferenceContentIsScrollable: Bool { get }
}

extension PreferenceWindowEmbeddable {
  var preferenceContentIsScrollable: Bool {
    return true
  }
}


class PreferenceWindowController: NSWindowController {

  class Trie {
    var s: String
    let returnValue: (String, String?, String?)

    class Node {

      var children: [Node] = []
      let char: Character

      init(c: Character) {
        char = c
      }
    }

    let root: Node
    var lastPosition: Node

    var active: Bool

    init(tab: String, section: String?, label: String?) {
      s = tab
      s += (section != nil) ? " " + section! : ""
      s += (label != nil) ? " " + label! : ""
      s = s.lowercased()
      returnValue = (tab, section, label)

      root = Node(c: " ")
      lastPosition = root
      active = true

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
        var found = false
        for child in current.children {
          if child.char == c {
            found = true
            current = child
            break
          }
        }
        if !found {
          let newNode = Node(c: c)
          current.children.append(newNode)
          current = newNode
        }
      }
    }

    func search(_ str: String) {
      for c in Array(str) {
        if c == " " {
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

  override var windowNibName: NSNib.Name {
    return NSNib.Name("PreferenceWindowController")
  }

  private var tries: [Trie] = []
  private var lastString: String = ""

  @IBOutlet weak var tableView: NSTableView!
  @IBOutlet weak var scrollView: NSScrollView!
  @IBOutlet weak var contentView: NSView!

  private var contentViewBottomConstraint: NSLayoutConstraint?

  private var viewControllers: [NSViewController & PreferenceWindowEmbeddable]

  init(viewControllers: [NSViewController & PreferenceWindowEmbeddable]) {
    self.viewControllers = viewControllers
    super.init(window: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func windowDidLoad() {
    super.windowDidLoad()

    window?.titlebarAppearsTransparent = true
    window?.isMovableByWindowBackground = true

    tableView.delegate = self
    tableView.dataSource = self

    if #available(OSX 10.11, *) {
      contentViewBottomConstraint = contentView.bottomAnchor.constraint(equalTo: contentView.superview!.bottomAnchor)
    }

    let labelDict = Dictionary<String, [String: [String]]>(uniqueKeysWithValues:  [
      ["general", "PrefGeneralViewController"],
      ["ui", "PrefUIViewController"],
      ["sub", "PrefSubViewController"],
      ["network", "PrefNetworkViewController"],
      ["control", "PrefControlViewController"],
      ["key_bindings", "PrefKeyBindingViewController"],
      ["video_audio", "PrefCodecViewController"],
      ["advanced", "PrefAdvancedViewController"],
      ["utilities", "PrefUtilsViewController"],
    ].map { (NSLocalizedString("preference.\($0[0])", comment: ""), self.getLabelDict(inNibNamed: $0[1])) })

    print(labelDict)

    makeTries(labelDict)

    loadTab(at: 0)
  }

  @IBAction func searchFieldAction(_ sender: NSSearchField) {
    let searchString = sender.stringValue.lowercased()
    print("Searching: \(searchString)")
    if searchString.hasPrefix(lastString) {
      tries.filter { $0.active }.forEach { $0.search(String(searchString.dropFirst(lastString.count))) }
    } else {
      tries.forEach { $0.reset(); $0.search(searchString) }
    }
    lastString = searchString
    print("\(tries.filter { $0.active }.map { $0.returnValue })")
    print("\(tries.filter { $0.active }.map { $0.s })")
  }

  private func makeTries(_ labelDict: [String: [String: [String]]]) {
    for (k1, v1) in labelDict {
      tries.append(Trie(tab: k1, section: nil, label: nil))
      for (k2, v2) in v1 {
        tries.append(Trie(tab: k1, section: k2, label: nil))
        for k3 in v2 {
          tries.append(Trie(tab: k1, section: k2, label: k3))
        }
      }
    }
  }

  private func loadTab(at index: Int) {
    contentView.subviews.forEach { $0.removeFromSuperview() }
    guard let vc = viewControllers[at: index] else { return }
    contentView.addSubview(vc.view)
    Utility.quickConstraints(["H:|-20-[v]-20-|", "V:|-28-[v]-28-|"], ["v": vc.view])

    let isScrollable = vc.preferenceContentIsScrollable
    contentViewBottomConstraint?.isActive = !isScrollable
    scrollView.verticalScrollElasticity = isScrollable ? .allowed : .none
  }

  private func getLabelDict(inNibNamed name: String) -> [String: [String]] {
    var objects: NSArray? = NSArray()
    Bundle.main.loadNibNamed(NSNib.Name(name), owner: nil, topLevelObjects: &objects)
    if let topObjects = objects as? [Any] {
      // we assume this nib is a preference view controller, so each section must be a top-level `NSView`.
      return Dictionary<String, [String]>(uniqueKeysWithValues: topObjects.compactMap { view -> (title: String, labels: [String])? in
        if let section = view as? NSView {
          return findLabels(inSection: section)
        } else {
          return nil
        }
      })
    }
    return [:]
  }

  private func findLabels(inSection section: NSView) -> (title: String, labels: [String])? {
    guard let sectionTitleLabel = section.subviews.first(where: {
        ($0 as? NSTextField)?.identifier?.rawValue == "SectionTitle"
      }) else {
        return nil
    }
    let title = (sectionTitleLabel as! NSTextField).stringValue
    var labels = findLabels(in: section)
    labels.remove(at: labels.index(of: title)!)
    return (title, labels)
  }

  private func findLabels(in view: NSView) -> [String] {
    var labels: [String] = []
    for subView in view.subviews {
      if let label = subView as? NSTextField,
        !label.isEditable, label.textColor == .labelColor,
        label.identifier?.rawValue != "AccessoryLabel", label.identifier?.rawValue != "Trigger" {
        labels.append(label.stringValue)
      } else if let button = subView as? NSButton, button.bezelStyle == .regularSquare {
        labels.append(button.title)
      }
      labels.append(contentsOf: findLabels(in: subView))
    }
    return labels
  }

}

extension PreferenceWindowController: NSTableViewDelegate, NSTableViewDataSource {

  func numberOfRows(in tableView: NSTableView) -> Int {
    return viewControllers.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    return viewControllers[at: row]?.preferenceTabTitle
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    loadTab(at: tableView.selectedRow)
  }

}
