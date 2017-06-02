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

  static let supportedFileExt: [MPVTrack.TrackType: [String]] = [
    .video: ["mkv", "mp4", "avi", "m4v", "mov", "3gp", "ts", "wmv", "flv", "f4v", "asf", "webm", "rm", "rmvb", "qt"],
    .audio: ["mp3", "aac", "mka", "dts", "flac", "ogg", "m4a", "ac3", "opus", "wav", "wv"],
    .sub: ["utf", "utf8", "utf-8", "idx", "sub", "srt", "smi", "rt", "ssa", "aqt", "jss", "js", "ass", "mks", "vtt", "sup", "scc"]
  ]

  // MARK: - Logs, alerts

  @available(*, deprecated, message: "showAlert(message:alertStyle:) is deprecated, use showAlert(_ key:comment:arguments:alertStyle:) instead")
  static func showAlert(message: String, alertStyle: NSAlertStyle = .critical) {
    let alert = NSAlert()
    switch alertStyle {
    case .critical:
      alert.messageText = NSLocalizedString("alert.title_error", comment: "Error")
    case .informational:
      alert.messageText = NSLocalizedString("alert.title_info", comment: "Information")
    case .warning:
      alert.messageText = NSLocalizedString("alert.title_warning", comment: "Warning")
    }
    alert.informativeText = message
    alert.alertStyle = alertStyle
    alert.runModal()
  }
  
  static func showAlert(_ key: String, comment: String? = nil, arguments: [CVarArg]? = nil, style: NSAlertStyle = .critical) {
    let alert = NSAlert()
    switch style {
    case .critical:
      alert.messageText = NSLocalizedString("alert.title_error", comment: "Error")
    case .informational:
      alert.messageText = NSLocalizedString("alert.title_info", comment: "Information")
    case .warning:
      alert.messageText = NSLocalizedString("alert.title_warning", comment: "Warning")
    }
    
    var format: String
    if let stringComment = comment {
      format = NSLocalizedString("alert." + key, comment: stringComment)
    } else {
      format = NSLocalizedString("alert." + key, comment: key)
    }
    
    if let stringArguments = arguments {
      alert.informativeText = String(format: format, arguments: stringArguments)
    } else {
      alert.informativeText = String(format: format)
    }
    
    alert.alertStyle = style
    alert.runModal()
  }

  static func log(_ message: String) {
    NSLog("%@", message)
  }

  static func assert(_ expr: Bool, _ errorMessage: String, _ block: () -> Void = {}) {
    if !expr {
      NSLog("%@", errorMessage)
      showAlert("fatal_error", arguments: [errorMessage])
      block()
      exit(1)
    }
  }

  static func fatal(_ message: String, _ block: () -> Void = {}) -> Never {
    NSLog("%@\n", message)
    NSLog(Thread.callStackSymbols.joined(separator: "\n"))
    showAlert("fatal_error", arguments: [message])
    block()
    // Exit without crash since it's not uncatched/unhandled
    exit(1)
  }

  // MARK: - Panels, Alerts

  /** 
   Pop up an ask panel.
   - parameters:
     - key: A localization key. "alert.`key`.title" will be used as alert title, and "alert.`key`.message" will be the informative text.
     - titleComment: (Optional) Comment for title key.
     - messageComment: (Optional) Comment for message key.
   - Returns: Whether user dismissed the panel by clicking OK.
   */
  static func quickAskPanel(_ key: String, titleComment: String? = nil, messageComment: String? = nil) -> Bool {
    let panel = NSAlert()
    let titleKey = "alert." + key + ".title"
    let messageKey = "alert." + key + ".message"
    panel.messageText = NSLocalizedString(titleKey, comment: titleComment ?? titleKey)
    panel.informativeText = NSLocalizedString(messageKey, comment: messageComment ?? messageKey)
    panel.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    panel.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    return panel.runModal() == NSAlertFirstButtonReturn
  }

  /**
   Pop up an open panel.
   - Returns: Whether user dismissed the panel by clicking OK.
   */
  static func quickOpenPanel(title: String, isDir: Bool, dir: URL? = nil, ok: @escaping (URL) -> Void) {
    let panel = NSOpenPanel()
    panel.title = title
    panel.canCreateDirectories = false
    panel.canChooseFiles = !isDir
    panel.canChooseDirectories = isDir
    panel.resolvesAliases = true
    panel.allowsMultipleSelection = false
    if let dir = dir {
      panel.directoryURL = dir
    }
    panel.begin() { result in
      if result == NSFileHandlingPanelOKButton, let url = panel.url {
        ok(url)
      }
    }
  }

  /**
   Pop up an open panel.
   - Returns: Whether user dismissed the panel by clicking OK.
   */
  static func quickMultipleOpenPanel(title: String, dir: URL? = nil, ok: @escaping ([URL]) -> Void) {
    let panel = NSOpenPanel()
    panel.title = title
    panel.canCreateDirectories = false
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.resolvesAliases = true
    panel.allowsMultipleSelection = true
    if let dir = dir {
      panel.directoryURL = dir
    }
    panel.begin() { result in
      if result == NSFileHandlingPanelOKButton {
        ok(panel.urls)
      }
    }
  }

  /**
   Pop up a save panel.
   - Returns: Whether user dismissed the panel by clicking OK.
   */
  static func quickSavePanel(title: String, types: [String], ok: @escaping (URL) -> Void) {
    let panel = NSSavePanel()
    panel.title = title
    panel.canCreateDirectories = true
    panel.allowedFileTypes = types
    panel.begin() { result in
      if result == NSFileHandlingPanelOKButton, let url = panel.url {
        ok(url)
      }
    }
  }

  /**
   Pop up a prompt panel.
   - parameters:
     - key: A localization key. "alert.`key`.title" will be used as alert title, and "alert.`key`.message" will be the informative text.
     - titleComment: (Optional) Comment for title key.
     - messageComment: (Optional) Comment for message key.
   - Returns: Whether user dismissed the panel by clicking OK.
   */
  static func quickPromptPanel(_ key: String, titleComment: String? = nil, messageComment: String? = nil, ok: (String) -> Void) -> Bool {
    let panel = NSAlert()
    let titleKey = "alert." + key + ".title"
    let messageKey = "alert." + key + ".message"
    panel.messageText = NSLocalizedString(titleKey, comment: titleComment ?? titleKey)
    panel.informativeText = NSLocalizedString(messageKey, comment: messageComment ?? messageKey)
    let input = ShortcutAvailableTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    input.lineBreakMode = .byClipping
    input.usesSingleLineMode = true
    input.cell?.isScrollable = true
    panel.accessoryView = input
    panel.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    panel.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    panel.window.initialFirstResponder = input
    let response = panel.runModal()
    if response == NSAlertFirstButtonReturn {
      ok(input.stringValue)
      return true
    } else {
      return false
    }
  }

  /**
   Pop up a username and password panel.
   - parameters:
     - key: A localization key. "alert.`key`.title" will be used as alert title, and "alert.`key`.message" will be the informative text.
     - titleComment: (Optional) Comment for title key.
     - messageComment: (Optional) Comment for message key.
   - Returns: Whether user dismissed the panel by clicking OK.
   */
  static func quickUsernamePasswordPanel(_ key: String, titleComment: String? = nil, messageComment: String? = nil, ok: (String, String) -> Void) -> Bool {
    let quickLabel: (String, Int) -> NSTextField = { title, yPos in
      let label = NSTextField(frame: NSRect(x: 0, y: yPos, width: 240, height: 14))
      label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize())
      label.stringValue = title
      label.drawsBackground = false
      label.isBezeled = false
      label.isSelectable = false
      label.isEditable = false
      return label
    }
    let panel = NSAlert()
    let titleKey = "alert." + key + ".title"
    let messageKey = "alert." + key + ".message"
    panel.messageText = NSLocalizedString(titleKey, comment: titleComment ?? titleKey)
    panel.informativeText = NSLocalizedString(messageKey, comment: messageComment ?? messageKey)
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 82))
    view.addSubview(quickLabel(NSLocalizedString("general.username", comment: "Username") + ":", 68))
    let input = ShortcutAvailableTextField(frame: NSRect(x: 0, y: 42, width: 240, height: 24))
    input.lineBreakMode = .byClipping
    input.usesSingleLineMode = true
    input.cell?.isScrollable = true
    view.addSubview(input)
    view.addSubview(quickLabel(NSLocalizedString("general.password", comment: "Password") + ":", 26))
    let pwField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    view.addSubview(pwField)
    panel.accessoryView = view
    panel.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    panel.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    panel.window.initialFirstResponder = input
    let response = panel.runModal()
    if response == NSAlertFirstButtonReturn {
      ok(input.stringValue, pwField.stringValue)
      return true
    } else {
      return false
    }
  }

  /**
   Pop up a font picker panel.
   - parameters:
     - ok: A closure accepting the font name.
   */
  static func quickFontPickerWindow(ok: @escaping (String?) -> Void) {
    guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
    appDelegate.fontPicker.finishedPicking = ok
    appDelegate.fontPicker.showWindow(self)
  }

  // MARK: - App functions

  static func setSelfAsDefaultForAllFileTypes() {
    guard
    let docTypes = Bundle.main.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]],
    let cfBundleID = Bundle.main.bundleIdentifier as CFString?
    else { return }

    guard quickAskPanel("set_default") else { return }

    var successCount = 0
    var failedCount = 0
    Utility.log("Set self as default...")
    for docType in docTypes {
      if let exts = docType["CFBundleTypeExtensions"] as? [String] {
        for ext in exts {
          let utiString = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext as CFString, nil)!.takeUnretainedValue()
          let status = LSSetDefaultRoleHandlerForContentType(utiString, .all, cfBundleID)
          if status == kOSReturnSuccess {
            successCount += 1
          } else {
            Utility.log("failed for \(ext): return value \(status)")
            failedCount += 1
          }
        }
      }
    }

    showAlert("set_default.success", arguments: [successCount, failedCount], style: .informational)
  }

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

  static func getFilePath(Configs userConfigs: [String: Any]!, forConfig conf: String, showAlert: Bool = true) -> String? {
    
    // if is default config
    if let dv = PrefKeyBindingViewController.defaultConfigs[conf] {
      return dv
    } else if let uv = userConfigs[conf] as? String {
      return uv
    } else {
      if showAlert {
        Utility.showAlert("error_finding_file", arguments: ["config"])
      }
      return nil
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

  static let playbackHistoryURL: URL = {
    return Utility.appSupportDirUrl.appendingPathComponent(AppData.historyFile, isDirectory: false)
  }()

  static let tempDirURL: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

  static let exeDirURL: URL = URL(fileURLWithPath: Bundle.main.executablePath!).deletingLastPathComponent()


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

  class FontAttributes {
    struct AttributeType {
      enum Align {
        case left
        case center
        case right
      }
      enum Size {
        case system
        case small
        case mini
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
        case .small:
          s = NSFont.systemFontSize(for: .small)
        case .mini:
          s = NSFont.systemFontSize(for: .mini)
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

