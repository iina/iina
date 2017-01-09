//
//  Utility.swift
//  iina
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
    switch alertStyle {
    case .critical:
      alert.messageText = "Error"
    case .informational:
      alert.messageText = "Information"
    case .warning:
      alert.messageText = "Warning"
    }
    alert.informativeText = message
    alert.alertStyle = alertStyle
    alert.runModal()
  }

  static func log(_ message: String) {
    NSLog("%@", message)
  }

  static func assert(_ expr: Bool, _ errorMessage: String, _ block: () -> Void = {}) {
    if !expr {
      NSLog("%@", errorMessage)
      showAlert(message: "Fatal error: \(errorMessage) \nThe application will exit now.")
      block()
      exit(1)
    }
  }

  static func fatal(_ message: String, _ block: () -> Void = {}) {
    NSLog("%@", message)
    NSLog(Thread.callStackSymbols.joined(separator: "\n"))
    showAlert(message: "Fatal error: \(message) \nThe application will exit now.")
    block()
    exit(1)
  }

  // MARK: - Panels, Alerts

  static func quickAskPanel(title: String, infoText: String) -> Bool {
    let panel = NSAlert()
    panel.messageText = title
    panel.informativeText = infoText
    panel.addButton(withTitle: "OK")
    panel.addButton(withTitle: "Cancel")
    return panel.runModal() == NSAlertFirstButtonReturn
  }

  static func quickOpenPanel(title: String, isDir: Bool, ok: (URL) -> Void) -> Bool {
    let panel = NSOpenPanel()
    panel.title = title
    panel.canCreateDirectories = false
    panel.canChooseFiles = !isDir
    panel.canChooseDirectories = isDir
    panel.resolvesAliases = true
    panel.allowsMultipleSelection = false
    if panel.runModal() == NSFileHandlingPanelOKButton {
      if let url = panel.url {
        ok(url)
      }
      return true
    } else {
      return false
    }
  }

  static func quickPromptPanel(messageText: String, informativeText: String, ok: (String) -> Void) -> Bool {
    let panel = NSAlert()
    panel.messageText = messageText
    panel.informativeText = informativeText
    let input = ShortcutAvailableTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    input.lineBreakMode = .byClipping
    input.usesSingleLineMode = true
    input.cell?.isScrollable = true
    panel.accessoryView = input
    panel.addButton(withTitle: "OK")
    panel.addButton(withTitle: "Cancel")
    panel.window.initialFirstResponder = input
    let response = panel.runModal()
    if response == NSAlertFirstButtonReturn {
      ok(input.stringValue)
      return true
    } else {
      return false
    }
  }

  static func quickFontPickerWindow(ok: @escaping (String?) -> Void) {
    guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
    appDelegate.fontPicker.finishedPicking = ok
    appDelegate.fontPicker.showWindow(self)
  }

  // MARK: - App functions

  private static func createDirIfNotExist(url: URL) {
  let path = url.path
    // check exist
    if !FileManager.default.fileExists(atPath: path) {
      do {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: nil)
      } catch {
        Utility.fatal("Cannot create folder in Application Support directory")
      }
    }
  }

  static let appSupportDirUrl: URL = {
    // get path
    let asPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
    Utility.assert(asPath.count >= 1, "Cannot get path to Application Support directory")
    let bundleID = Bundle.main.bundleIdentifier!
    let appAsUrl = asPath.first!.appendingPathComponent(bundleID)
    createDirIfNotExist(url: appAsUrl)
    return appAsUrl
  }()

  static let userInputConfDirURL: URL = {
    let url = Utility.appSupportDirUrl.appendingPathComponent(AppData.userInputConfFolder, isDirectory: true)
    createDirIfNotExist(url: url)
    return url
  }()

  static let logDirURL: URL = {
    let url = Utility.appSupportDirUrl.appendingPathComponent(AppData.logFolder, isDirectory: true)
    createDirIfNotExist(url: url)
    return url
  }()

  static let watchLaterURL: URL = {
    let url = Utility.appSupportDirUrl.appendingPathComponent(AppData.watchLaterFolder, isDirectory: true)
    createDirIfNotExist(url: url)
    return url
  }()

  // MARK: - Util functions

  static func swap<T>(_ a: inout T, _ b: inout T) {
    let temp = a
    a = b
    b = temp
  }

  static func toRealSubScale(fromDisplaySubScale scale: Double) -> Double {
    return scale > 0 ? scale : -1 / scale
  }

  static func toDisplaySubScale(fromRealSubScale realScale: Double) -> Double {
    return realScale >= 1 ? realScale : -1 / realScale
  }

  static func mpvKeyCode(from event: NSEvent) -> String {
    var keyString = ""
    let keyChar: String
    let keyCode = event.keyCode
    let modifiers = event.modifierFlags
    // shift
    guard let keyName = KeyCodeHelper.keyMap[keyCode] else {
      Utility.log("Undefined key code?")
      return ""
    }
    if modifiers.contains(.shift) {
      if KeyCodeHelper.canBeModifiedByShift(keyCode) {
        keyChar = keyName.1!
      } else {
        keyChar = keyName.0
        keyString += "Shift+"
      }
    } else {
      keyChar = keyName.0
    }
    // control
    if modifiers.contains(.control) {
      keyString += "Ctrl+"
    }
    // alt
    if modifiers.contains(.option) {
      keyString += "Alt+"
    }
    // meta
    if modifiers.contains(.command) {
      keyString += "Meta+"
    }
    // char
    keyString += keyChar
    return keyString
  }

  // MARK: - Util classes

  class Regex {
    var regex: NSRegularExpression?

    init (_ pattern: String) {
      if let exp = try? NSRegularExpression(pattern: pattern, options: []) {
        self.regex = exp
      } else {
        Utility.fatal("Cannot create regex \(pattern)")
      }
    }

    func matches(_ str: String) -> Bool {
      if let matches = regex?.numberOfMatches(in: str, options: [], range: NSMakeRange(0, str.characters.count)) {
        return matches > 0
      } else {
        return false
      }
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


  // http://stackoverflow.com/questions/31701326/

  struct ShortCodeGenerator {

    private static let base62chars = [Character]("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".characters)
    private static let maxBase : UInt32 = 62

    static func getCode(withBase base: UInt32 = maxBase, length: Int) -> String {
      var code = ""
      for _ in 0..<length {
        let random = Int(arc4random_uniform(min(base, maxBase)))
        code.append(base62chars[random])
      }
      return code
    }
  }


}

// http://stackoverflow.com/questions/33294620/


func rawPointerOf<T : AnyObject>(obj : T) -> UnsafeRawPointer {
  return UnsafeRawPointer(Unmanaged.passUnretained(obj).toOpaque())
}

func mutableRawPointerOf<T : AnyObject>(obj : T) -> UnsafeMutableRawPointer {
  return UnsafeMutableRawPointer(Unmanaged.passUnretained(obj).toOpaque())
}


func bridge<T : AnyObject>(ptr : UnsafeRawPointer) -> T {
  return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
}

func bridgeRetained<T : AnyObject>(obj : T) -> UnsafeRawPointer {
  return UnsafeRawPointer(Unmanaged.passRetained(obj).toOpaque())
}

func bridgeTransfer<T : AnyObject>(ptr : UnsafeRawPointer) -> T {
  return Unmanaged<T>.fromOpaque(ptr).takeRetainedValue()
}

