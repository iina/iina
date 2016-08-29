//
//  Utility.swift
//  mpvx
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class Utility {
  
  static let tabTitleFontAttributes = FontAttributes(font: .system, size: .system, align: .center).value
  static let tabTitleActiveFontAttributes = FontAttributes(font: .systemBold, size: .system, align: .center).value
  
  // MARK: - Logs, alerts
  
  static func showAlert(message: String, alertStyle: NSAlertStyle = .critical) {
    let alert = NSAlert()
    alert.messageText = message
    alert.alertStyle = alertStyle
    alert.runModal()
  }
  
  static func log(_ message: String) {
    NSLog("%@", message)
  }
  
  static func assert(_ expr: Bool, _ errorMessage: String, _ block: () -> Void = {}) {
    if !expr {
      NSLog("%@", errorMessage)
      block()
      exit(1)
    }
  }
  
  static func fatal(_ message: String, _ block: () -> Void = {}) {
    NSLog("%@", message)
    print(Thread.callStackSymbols)
    block()
    exit(1)
  }
  
  // MARK: - Panels, Alerts
  
  static func quickOpenPanel(title: String, ok: (URL) -> Void) {
    let panel = NSOpenPanel()
    panel.title = title
    panel.canCreateDirectories = false
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.resolvesAliases = true
    panel.allowsMultipleSelection = false
    if panel.runModal() == NSFileHandlingPanelOKButton {
      if let url = panel.url {
        ok(url)
      }
    }
  }
  
  static func quickPromptPanel(messageText: String, informativeText: String, ok: (String) -> Void) {
    let panel = NSAlert()
    panel.messageText = messageText
    panel.informativeText = informativeText
    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    input.bezelStyle = .roundedBezel
    panel.accessoryView = input
    panel.addButton(withTitle: "Jump")
    panel.addButton(withTitle: "Cancel")
    let response = panel.runModal()
    if response == NSAlertFirstButtonReturn {
      ok(input.stringValue)
    }
  }
  
  // MARK: - Util functions
  
  static func swap<T>(_ a: inout T, _ b: inout T) {
    let temp = a
    a = b
    b = temp
  }
    
  // MARK: - Util classes
  
  class Regex {
    var regex: RegularExpression?
    
    init (_ pattern: String) {
      if let exp = try? RegularExpression(pattern: pattern, options: []) {
        self.regex = exp
      } else {
        Utility.fatal("Cannot create regex \(pattern)")
      }
    }
    
    func matches(_ str: String) -> Bool {
      return regex?.numberOfMatches(in: str, options: [], range: NSMakeRange(0, str.characters.count)) > 0
    }
  }
  
  class FontAttributes {
    struct AttributeType {
      enum Align {
        case left
        case center
        case right
      }
      enum Size {
        case system
        case pt(Float)
      }
      enum Font {
        case system
        case systemBold
        case name(String)
      }
    }
    
    var align: AttributeType.Align
    var size: AttributeType.Size
    var font: AttributeType.Font
    
    init(font: AttributeType.Font, size: AttributeType.Size, align: AttributeType.Align) {
      self.font = font
      self.size = size
      self.align = align
    }
    
    var value : [String : AnyObject]? {
      get {
        let f: NSFont?
        let s: CGFloat
        let a = NSMutableParagraphStyle()
        switch self.size {
        case .system:
          s = NSFont.systemFontSize()
        case .pt(let point):
          s = CGFloat(point)
        }
        switch self.font {
        case .system:
          f = NSFont.systemFont(ofSize: s)
        case .systemBold:
          f = NSFont.boldSystemFont(ofSize: s)
        case .name(let n):
          f = NSFont(name: n, size: s)
        }
        switch self.align {
        case .left:
          a.alignment = .left
        case .center:
          a.alignment = .center
        case .right:
          a.alignment = .right
        }
        if let f = f {
          NSFont.systemFont(ofSize: NSFont.systemFontSize())
          return [
            NSFontAttributeName: f,
            NSParagraphStyleAttributeName: a
          ]
        } else {
          return nil
        }
      }
    }
  }

}

