//
//  PreferenceWindowController.swift
//  iina
//
//  Created by Collider LI on 6/7/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

fileprivate extension String {
  func removedLastSemicolon() -> String {
    if self.hasSuffix(":") || self.hasSuffix("：") {
      return String(self.dropLast())
    }
    return self
  }
}

fileprivate extension NSView {
  func identifierStartsWith(_ prefix: String) -> Bool {
    if let id = identifier {
      return id.rawValue.starts(with: prefix)
    } else {
      return false
    }
  }
}

protocol PreferenceWindowEmbeddable where Self: NSViewController {
  var preferenceTabTitle: String { get }
  var preferenceTabImage: NSImage { get }
  var preferenceContentIsScrollable: Bool { get }
}

extension PreferenceWindowEmbeddable {
  var preferenceContentIsScrollable: Bool {
    return true
  }
}

class PreferenceWindowController: NSWindowController {

  class Trie {

    class Node {
      var children: [Node] = []
      let char: Character
      init(_ c: Character) {
        char = c
      }
    }

    typealias ReturnValue = (tab: String, strippedSection: String, strippedLabel: String?, section: String, label: String?)

    var s: String
    let returnValue: ReturnValue

    let root: Node
    var lastPosition: Node

    var active: Bool

    init(tab: String, section: String, label: String?) {
      s = [tab, section, label].compactMap { $0 }.joined(separator: " ").lowercased()
      returnValue = (tab, section.removedLastSemicolon(), label?.removedLastSemicolon(), section, label)

      root = Node(" ")
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

  override var windowNibName: NSNib.Name {
    return NSNib.Name("PreferenceWindowController")
  }

  private var tries: [Trie] = []
  private var lastString: String = ""
  private var currentCompletionResults: [Trie.ReturnValue] = []

  private let indexingQueue = DispatchQueue(label: "IINAPreferenceIndexingTask", qos: .userInitiated)
  private var isIndexing: Bool = true

  @IBOutlet weak var searchField: NSSearchField!
  @IBOutlet weak var tableView: NSTableView!
  @IBOutlet weak var maskView: PrefSearchResultMaskView!
  @IBOutlet weak var scrollView: NSScrollView!
  @IBOutlet weak var contentView: NSView!
  @IBOutlet var completionPopover: NSPopover!
  @IBOutlet weak var completionTableView: NSTableView!
  @IBOutlet weak var noResultLabel: NSTextField!

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
    window?.titleVisibility = .hidden
    window?.isMovableByWindowBackground = true

    tableView.delegate = self
    tableView.dataSource = self
    completionTableView.delegate = self
    completionTableView.dataSource = self

    contentViewBottomConstraint = contentView.bottomAnchor.constraint(equalTo: contentView.superview!.bottomAnchor)

    let labelDict = [String: [String: [String]]](uniqueKeysWithValues:  [
      ["general", "PrefGeneralViewController"],
      ["ui", "PrefUIViewController"],
      ["subtitle", "PrefSubViewController"],
      ["network", "PrefNetworkViewController"],
      ["control", "PrefControlViewController"],
      ["keybindings", "PrefKeyBindingViewController"],
      ["video_audio", "PrefCodecViewController"],
      ["plugin", "PrefPluginViewController"],
      ["advanced", "PrefAdvancedViewController"],
      ["utilities", "PrefUtilsViewController"],
    ].map { (NSLocalizedString("preference.\($0[0])", comment: ""), self.getLabelDict(inNibNamed: $0[1])) })

    indexingQueue.async{
      self.isIndexing = true
      self.makeTries(labelDict)
      self.isIndexing = false
    }

    loadTab(at: 0)
  }

  override func mouseDown(with event: NSEvent) {
    dismissCompletionList()
  }

  // MARK: Searching

  private func makeTries(_ labelDict: [String: [String: [String]]]) {
    // search for sections and labels
    for (k1, v1) in labelDict {
      for (k2, v2) in v1 {
        tries.append(Trie(tab: k1, section: k2, label: nil))
        for k3 in v2 {
          tries.append(Trie(tab: k1, section: k2, label: k3))
        }
      }
    }
  }

  @IBAction func searchFieldAction(_ sender: Any) {
    guard !isIndexing else { return }
    let searchString = searchField.stringValue.lowercased()
    if searchString == lastString { return }
    if searchString.count == 0 {
      dismissCompletionList()
      return
    }
    if searchString.hasPrefix(lastString) {
      tries.filter { $0.active }.forEach { $0.search(String(searchString.dropFirst(lastString.count))) }
    } else {
      tries.forEach { $0.reset(); $0.search(searchString) }
    }
    lastString = searchString
    currentCompletionResults = tries.filter { $0.active }.map { $0.returnValue }
    completeSearchField()
  }

  private func completeSearchField() {
    noResultLabel.isHidden = currentCompletionResults.count != 0
    if !completionPopover.isShown {
      let range = searchField.currentEditor()?.selectedRange
      completionPopover.show(relativeTo: searchField.bounds, of: searchField, preferredEdge: .maxY)
      searchField.selectText(self)
      searchField.currentEditor()?.selectedRange = range ?? NSMakeRange(0, 0)
    }
    completionTableView.reloadData()
  }

  private func dismissCompletionList() {
    if completionPopover.isShown {
      completionPopover.close()
    }
  }

  // MARK: Tabs

  private func loadTab(at index: Int, thenFindLabelTitled title: String? = nil) {
    // load view
    if index != tableView.selectedRow {
      tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }
    contentView.subviews.forEach { $0.removeFromSuperview() }
    guard let vc = viewControllers[at: index] else { return }
    contentView.addSubview(vc.view)
    Utility.quickConstraints(["H:|-20-[v]-20-|", "V:|-28-[v]-28-|"], ["v": vc.view])

    let isScrollable = vc.preferenceContentIsScrollable
    contentViewBottomConstraint?.isActive = !isScrollable
    scrollView.verticalScrollElasticity = isScrollable ? .allowed : .none
    // scroll to top
    scrollView.documentView?.scroll(.zero)

    // find label
    if let title = title, let label = findLabel(titled: title, in: vc.view) {
      maskView.perform(#selector(maskView.highlight(_:)), with: label, afterDelay: 0.25)
      if let collapseView = findCollapseView(label) {
        collapseView.setCollapsed(false, animated: false)
      }
    }
  }

  private func getLabelDict(inNibNamed name: String) -> [String: [String]] {
    var objects: NSArray? = NSArray()
    Bundle.main.loadNibNamed(NSNib.Name(name), owner: nil, topLevelObjects: &objects)
    if let topObjects = objects as? [Any] {
      // we assume this nib is a preference view controller, so each section must be a top-level `NSView`.
      return [String: [String]](uniqueKeysWithValues: topObjects.compactMap { view -> (title: String, labels: [String])? in
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
        $0 is NSTextField && $0.identifierStartsWith("SectionTitle")
      }) else {
        return nil
    }
    let title = (sectionTitleLabel as! NSTextField).stringValue
    var labels = findLabels(in: section)
    labels.remove(at: labels.firstIndex(of: title)!)
    return (title, labels)
  }

  private func findLabels(in view: NSView) -> [String] {
    var labels: [String] = []
    for subView in view.subviews {
      if let title = getTitle(from: subView) {
        labels.append(title)
      }
      labels.append(contentsOf: findLabels(in: subView))
    }
    return labels
  }

  private func findLabel(titled title: String, in view: NSView) -> NSView? {
    for subView in view.subviews {
      if getTitle(from: subView) == title {
        return subView
      }
      if let r = findLabel(titled: title, in: subView) {
        return r
      }
    }
    return nil
  }

  private func getTitle(from view: NSView) -> String? {
    if let label = view as? NSTextField,
      !label.isEditable, label.textColor == .labelColor,
      !label.identifierStartsWith("AccessoryLabel"), !label.identifierStartsWith("Trigger") {
      return label.stringValue
    } else if let button = view as? NSButton,
      (button.identifierStartsWith("FunctionalButton") || button.bezelStyle == .regularSquare) {
      return button.title
    }
    return nil
  }

  private func findCollapseView(_ view: NSView) -> CollapseView? {
    if let superview = view.superview {
      if let collapseView = superview as? CollapseView {
        return collapseView
      } else {
        return findCollapseView(_:superview)
      }
    }
    return nil
  }

}

extension PreferenceWindowController: NSTableViewDelegate, NSTableViewDataSource {

  func numberOfRows(in tableView: NSTableView) -> Int {
    if tableView == self.tableView {
      return viewControllers.count
    } else {
      return currentCompletionResults.count
    }
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    if tableView == self.tableView {
      return [
        "image": viewControllers[at: row]?.preferenceTabImage,
        "title": viewControllers[at: row]?.preferenceTabTitle
      ] as [String: Any?]
    } else {
      guard let result = currentCompletionResults[at: row] else { return nil }
      let noLabel = result.strippedLabel == nil
      return [
        "tab": result.tab,
        "noSection": noLabel,
        "section": result.strippedSection,
        "label": result.strippedLabel ?? result.strippedSection,
      ]
    }
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    if (notification.object as! NSTableView) == self.tableView {
      loadTab(at: tableView.selectedRow)
    } else {
      dismissCompletionList()
      guard
        let result = currentCompletionResults[at: completionTableView.selectedRow],
        let index = viewControllers.enumerated().first(where: { (_, vc) in vc.preferenceTabTitle == result.tab })?.offset
        else {
          return
      }
      loadTab(at: index, thenFindLabelTitled: result.label ?? result.section)
    }
  }

}

class PrefSearchResultMaskView: NSView {

  var maskRect: NSRect?

  override static func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
    if key == "alphaValue" {
      let kfa = CAKeyframeAnimation(keyPath: "alphaValue")
      kfa.duration = 1.5
      kfa.timingFunctions = [CAMediaTimingFunction(name: .default), CAMediaTimingFunction(name: .linear)]
      kfa.values = [1, 1, 0]
      kfa.keyTimes = [0, 0.75, 1.5]
      return kfa
    } else {
      return super.defaultAnimation(forKey: key)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let maskRect = maskRect else { return }
    NSGraphicsContext.saveGraphicsState()
    let framePath = NSBezierPath(rect: bounds)
    let maskPath =  NSBezierPath(roundedRect: maskRect, xRadius: 6, yRadius: 6)
    framePath.append(maskPath)
    framePath.windingRule = .evenOdd
    framePath.setClip()
    if #available(macOS 10.14, *) {
      NSColor.windowBackgroundColor.withSystemEffect(.pressed).setFill()
    } else {
      NSColor(calibratedWhite: 0.5, alpha: 0.5).setFill()
    }
    dirtyRect.fill()
    NSGraphicsContext.restoreGraphicsState()
  }

  @objc func highlight(_ view: NSView) {
    view.scrollToVisible(view.bounds.insetBy(dx: 0, dy: -20))

    isHidden = false
    alphaValue = 1

    let viewToHighlight = view.identifierStartsWith("SectionTitle") ? view.superview! : view

    let rectInWindow = viewToHighlight.convert(viewToHighlight.bounds.insetBy(dx: -8, dy: -8), to: nil)
    maskRect = convert(rectInWindow, from: nil)
    needsDisplay = true

    NSAnimationContext.runAnimationGroup({ _ in
      self.animator().alphaValue = 0
    }, completionHandler: {
      self.isHidden = true
    })
  }

}

class PrefTabTitleLabelCell: NSTextFieldCell {
  override var backgroundStyle: NSView.BackgroundStyle {
    didSet {
      if backgroundStyle == .dark {
        self.textColor = NSColor.white
      } else {
        self.textColor = NSColor.controlTextColor
      }
    }
  }
}
