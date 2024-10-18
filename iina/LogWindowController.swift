//
//  LogWindowController.swift
//  iina
//
//  Created by Yuze Jiang on 2022/11/10.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

fileprivate let colorMap: [Int: NSColor] = [0: .lightGray, 1: .green, 2: .yellow, 3: .red]
fileprivate var circleDict: [NSColor: NSImage] = [:]
fileprivate let kIconSize = 17.0
fileprivate let kBorderWidth = 1.25

class LogWindowController: NSWindowController, NSMenuDelegate {
  override var windowNibName: NSNib.Name {
    return NSNib.Name("LogWindowController")
  }

  @IBOutlet weak var logTableView: NSTableView!
  @IBOutlet var logArrayController: NSArrayController!
  @IBOutlet weak var subsystemPopUpButton: NSPopUpButton!
  @IBOutlet weak var levelPopUpButton: NSPopUpButton!

  @objc dynamic var logs: [Logger.Log] = []
  @objc dynamic var predicate = NSPredicate(value: true)

  override func windowDidLoad() {
    super.windowDidLoad()

    logTableView.sizeLastColumnToFit()
    let tableViewMenu = NSMenu()
    tableViewMenu.addItem(withTitle: "Copy", action: #selector(menuCopy), keyEquivalent: "")
    logTableView.menu = tableViewMenu

    levelPopUpButton.menu?.items.forEach {
      $0.image = LogWindowController.indicatorIcon(withColor: colorMap[$0.tag]!)
    }
    levelPopUpButton.selectItem(withTag: Logger.Level.preferred.rawValue)
    subsystemPopUpButton.menu!.delegate = self

    syncLogs()
  }

  fileprivate static func indicatorIcon(withColor color: NSColor) -> NSImage {
    if let cached = circleDict[color] {
      return cached
    }
    let image = NSImage(size: NSMakeSize(kIconSize, kIconSize), flipped: false) { rect in
      let inset = NSInsetRect(rect, kBorderWidth / 2 + rect.size.width * 0.25, kBorderWidth / 2 + rect.size.height * 0.25)
      let path = NSBezierPath.init(ovalIn: inset)
      path.lineWidth = kBorderWidth

      let fractionOfBlendedColor = (NSApp.appearance?.isDark ?? false) ? 0.15 : 0.3
      let borderColor = color.blended(withFraction: fractionOfBlendedColor, of: .controlTextColor)

      borderColor?.setStroke()
      path.stroke()

      color.setFill()
      path.fill()

      return true
    }
    circleDict[color] = image
    return image
  }

  // MARK: - NSMenuDelegate

  func menuNeedsUpdate(_ menu: NSMenu) {
    // The first menu item is "All"
    let offset = 1
    Logger.$subsystems.withLock() { subsystems in
      for (index, subsystem) in subsystems.enumerated() {
        guard !subsystem.added else { continue }
        subsystem.added = true
        menu.insertItem(withTitle: subsystem.rawValue, action: nil, keyEquivalent: "", at: index + offset)
      }
    }
  }

  private func updatePredicate() {
    var subsystemPredicate = NSPredicate(value: true)
    if subsystemPopUpButton.indexOfSelectedItem != 0 {
      subsystemPredicate = NSPredicate(format: "subsystem = %@", subsystemPopUpButton.titleOfSelectedItem!)
    }
    let levelPredicate = NSPredicate(format: "level >= %d", levelPopUpButton.selectedTag())
    predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [subsystemPredicate, levelPredicate])
  }

  @IBAction func subsystemUpdated(_ sender: Any) {
    updatePredicate()
  }

  @IBAction func save(_ sender: Any) {
    Utility.quickSavePanel(title: "Log", filename: "iina.log", sheetWindow: window) { url in
      let logs = (self.logArrayController.content as! [Logger.Log]).map { $0.logString }.joined()
      try? logs.write(to: url, atomically: true, encoding: .utf8)
    }
  }

  // MARK: - Menu actions

  @IBAction func copy(_ sender: Any) {
    menuCopy()
  }

  @objc private func menuCopy()
  {
    let string = (logArrayController.selectedObjects as! [Logger.Log]).map { $0.logString }.joined()
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(string, forType: .string)
  }

  // MARK: - Logs

  @objc func syncLogs() {
    guard isWindowLoaded else { return }
    Logger.$logs.withLock() { logs in
      guard !logs.isEmpty else { return }
      var scroll = false
      let range = logTableView.rows(in: logTableView.visibleRect)
      if range.location + range.length >= self.logs.count {
        scroll = true
      }

      self.logs.append(contentsOf: logs)
      logs.removeAll()
      if scroll {
        // macOS couldn't calcuate the frame size correctly when the row height is variable and
        // is not rendered. After the first scroll, all rows should be rendered, which makes the
        // second frame size correct. Scroll the second time to correctly scroll to the last row.
        logTableView.scroll(NSPoint(x: 0, y: logTableView.frame.size.height))
        logTableView.scroll(NSPoint(x: 0, y: logTableView.frame.size.height))
      }
    }
  }
}

@objc(LogLevelTransformer) class LogLevelTransformer: ValueTransformer {
  static override func allowsReverseTransformation() -> Bool {
    return false
  }

  static override func transformedValueClass() -> AnyClass {
    return NSImage.self
  }

  override func transformedValue(_ value: Any?) -> Any? {
    guard let value = value as? Int else { return nil }
    return LogWindowController.indicatorIcon(withColor: colorMap[value]!)
  }
}

