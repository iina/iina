//
//  Utility.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class Utility {

  static let tabTitleFontAttributes = FontAttributes(font: .system, size: .system, align: .center).value
  static let tabTitleActiveFontAttributes = FontAttributes(font: .systemBold, size: .system, align: .center).value

  static let supportedFileExt: [MPVTrack.TrackType: [String]] = [
    .video: ["mkv", "mp4", "avi", "m4v", "mov", "3gp", "ts", "mts", "m2ts", "wmv", "flv", "f4v", "asf", "webm", "rm", "rmvb", "qt", "dv", "mpg", "mpeg", "mxf", "vob", "gif"],
    .audio: ["mp3", "aac", "mka", "dts", "flac", "ogg", "oga", "mogg", "m4a", "ac3", "opus", "wav", "wv", "aiff", "ape", "tta", "tak", "cue"],
    .sub: ["utf", "utf8", "utf-8", "idx", "sub", "srt", "smi", "rt", "ssa", "aqt", "jss", "js", "ass", "mks", "vtt", "sup", "scc"]
  ]
  static let playableFileExt = supportedFileExt[.video]! + supportedFileExt[.audio]!
  static let playlistFileExt = ["m3u", "m3u8", "pls"]
  static let blacklistExt = supportedFileExt[.sub]! + playlistFileExt
  static let lut3dExt = ["3dl", "cube", "dat", "m3d"]

  // MARK: - Logs, alerts

  enum AlertMode {
    case modal
    case nonModal
    case sheet
    case sheetModal
  }

  @available(*, deprecated, message: "showAlert(message:alertStyle:) is deprecated, use showAlert(_ key:comment:arguments:alertStyle:) instead")
  static func showAlert(message: String, alertStyle: NSAlert.Style = .critical) {
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
  
  static func showAlert(_ key: String, comment: String? = nil, arguments: [CVarArg]? = nil, style: NSAlert.Style = .critical) {
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

  // MARK: - Panels, Alerts

  /** 
   Pop up an ask panel.
   - parameters:
     - key: A localization key. "alert.`key`.title" will be used as alert title, and "alert.`key`.message" will be the informative text.
     - titleComment: (Optional) Comment for title key.
     - messageComment: (Optional) Comment for message key.
   - Returns: Whether user dismissed the panel by clicking OK.
   */
  static func quickAskPanel(_ key: String, titleComment: String? = nil, messageComment: String? = nil, useSheet: Bool = false, sheetCallback: ((Bool) -> Void)? = nil) -> Bool {
    let panel = NSAlert()
    let titleKey = "alert." + key + ".title"
    let messageKey = "alert." + key + ".message"
    panel.messageText = NSLocalizedString(titleKey, comment: titleComment ?? titleKey)
    panel.informativeText = NSLocalizedString(messageKey, comment: messageComment ?? messageKey)
    panel.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    panel.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    if useSheet {
      panel.beginSheetModal(for: NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows[0]) { response in
        if let sheetCallback = sheetCallback {
          sheetCallback(response == .alertFirstButtonReturn)
        }
      }
      return false
    } else {
      return panel.runModal() == .alertFirstButtonReturn
    }
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
    panel.level = .modalPanel
    if let dir = dir {
      panel.directoryURL = dir
    }
    panel.begin() { result in
      if result == .OK, let url = panel.url {
        ok(url)
      }
    }
  }

  /**
   Pop up an open panel.
   - Returns: Whether user dismissed the panel by clicking OK.
   */
  static func quickMultipleOpenPanel(title: String, dir: URL? = nil, canChooseDir: Bool, ok: @escaping ([URL]) -> Void) {
    let panel = NSOpenPanel()
    panel.title = title
    panel.canCreateDirectories = false
    panel.canChooseFiles = true
    panel.canChooseDirectories = canChooseDir
    panel.resolvesAliases = true
    panel.allowsMultipleSelection = true
    if let dir = dir {
      panel.directoryURL = dir
    }
    panel.begin() { result in
      if result == .OK {
        ok(panel.urls)
      }
    }
  }

  /**
   Pop up a save panel.
   - Returns: Whether user dismissed the panel by clicking OK.
   */
  static func quickSavePanel(title: String, types: [String],
                             mode: AlertMode = .nonModal, sheetWindow: NSWindow? = nil,
                             ok: @escaping (URL) -> Void) {
    let panel = NSSavePanel()
    panel.title = title
    panel.canCreateDirectories = true
    panel.allowedFileTypes = types
    let handler: (NSApplication.ModalResponse) -> Void = { result in
      if result == .OK, let url = panel.url {
        ok(url)
      }
    }
    switch mode {
    case .modal:
      let response = panel.runModal()
      handler(response)
    case .nonModal:
      panel.begin(completionHandler: handler)
    case .sheet:
      guard let sheetWindow = sheetWindow else {
        Logger.fatal("No sheet window")
      }
      panel.beginSheet(sheetWindow, completionHandler: handler)
    default:
      Logger.log("quickSavePanel: Unsupported mode", level: .error)
    }
  }

  /**
   Pop up a prompt panel.
   - parameters:
     - key: A localization key. "alert.`key`.title" will be used as alert title, and "alert.`key`.message" will be the informative text.
     - titleComment: (Optional) Comment for title key.
     - messageComment: (Optional) Comment for message key.
     - mode: A `AlertMode`, `.modal` (default) or `.sheetModal`.
     - sheetWindow: Must present if mode is `.sheetModal`.
   - Returns: Whether user dismissed the panel by clicking OK. Only works when using `.modal` mode.
   */
  @discardableResult static func quickPromptPanel(_ key: String,
                                                  titleComment: String? = nil, messageComment: String? = nil,
                                                  mode: AlertMode = .modal, sheetWindow: NSWindow? = nil,
                                                  ok: @escaping (String) -> Void) -> Bool {
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
    // handler
    switch mode {
    case .modal:
      let response = panel.runModal()
      if response == .alertFirstButtonReturn {
        ok(input.stringValue)
        return true
      } else {
        return false
      }
    case .sheetModal:
      guard let sheetWindow = sheetWindow else {
        Logger.fatal("No sheet window")
      }
      panel.beginSheetModal(for: sheetWindow) { response in
        if response == .alertFirstButtonReturn {
          ok(input.stringValue)
        }
      }
      return false
    default:
      Logger.log("quickPromptPanel: Unsupported mode", level: .error)
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
      label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
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
    input.nextKeyView = pwField
    panel.accessoryView = view
    panel.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    panel.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    panel.window.initialFirstResponder = input
    let response = panel.runModal()
    if response == .alertFirstButtonReturn {
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

  static func iinaVersion() -> (String, String) {
    let infoDic = Bundle.main.infoDictionary!
    let version = infoDic["CFBundleShortVersionString"] as! String
    let build = infoDic["CFBundleVersion"] as! String
    return (version, build)
  }

  static func createDirIfNotExist(url: URL) {
    let path = url.path
    // check exist
    if !FileManager.default.fileExists(atPath: path) {
      do {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
      } catch {
        Logger.fatal("Cannot create directory: \(url)")
      }
    }
  }

  static private let allTypes: [MPVTrack.TrackType] = [.video, .audio, .sub]

  static func mediaType(forExtension ext: String) -> MPVTrack.TrackType? {
    return allTypes.first { supportedFileExt[$0]!.contains(ext.lowercased()) }
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
    Logger.ensure(asPath.count >= 1, "Cannot get path to Application Support directory")
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
    // get path
    let libraryPath = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
    Logger.ensure(libraryPath.count >= 1, "Cannot get path to Logs directory")
    let logsUrl = libraryPath.first!.appendingPathComponent("Logs", isDirectory: true)
    let bundleID = Bundle.main.bundleIdentifier!
    let appLogsUrl = logsUrl.appendingPathComponent(bundleID, isDirectory: true)
    createDirIfNotExist(url: appLogsUrl)
    return appLogsUrl
  }()

  static let watchLaterURL: URL = {
    let url = Utility.appSupportDirUrl.appendingPathComponent(AppData.watchLaterFolder, isDirectory: true)
    createDirIfNotExist(url: url)
    return url
  }()

  static let thumbnailCacheURL: URL = {
    // get path
    let cachesPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
    Logger.ensure(cachesPath.count >= 1, "Cannot get path to Caches directory")
    let bundleID = Bundle.main.bundleIdentifier!
    let appCachesUrl = cachesPath.first!.appendingPathComponent(bundleID, isDirectory: true)
    let appThumbnailCacheUrl = appCachesUrl.appendingPathComponent(AppData.thumbnailCacheFolder, isDirectory: true)
    createDirIfNotExist(url: appThumbnailCacheUrl)
    return appThumbnailCacheUrl
  }()

  static let playbackHistoryURL: URL = {
    return Utility.appSupportDirUrl.appendingPathComponent(AppData.historyFile, isDirectory: false)
  }()

  static let tempDirURL: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

  static let exeDirURL: URL = URL(fileURLWithPath: Bundle.main.executablePath!).deletingLastPathComponent()


  // MARK: - Util functions

  static func toRealSubScale(fromDisplaySubScale scale: Double) -> Double {
    return scale > 0 ? scale : -1 / scale
  }

  static func toDisplaySubScale(fromRealSubScale realScale: Double) -> Double {
    return realScale >= 1 ? realScale : -1 / realScale
  }

  static func quickConstraints(_ constraints: [String], _ views: [String: NSView]) {
    constraints.forEach { c in
      let cc = NSLayoutConstraint.constraints(withVisualFormat: c, options: [], metrics: nil, views: views)
      NSLayoutConstraint.activate(cc)
    }
  }

  /// See `mp_get_playback_resume_config_filename` in mpv/configfiles.c
  static func mpvWatchLaterMd5(_ filename: String) -> String {
    // mp_is_url
    // if(!Regex.mpvURL.matches(filename)) {
      // ignore_path_in_watch_later_config
    // }
    // handle dvd:// and bd://
    return filename.md5
  }

  static func playbackProgressFromWatchLater(_ mpvMd5: String) -> VideoTime? {
    let fileURL = Utility.watchLaterURL.appendingPathComponent(mpvMd5)
    if let reader = StreamReader(path: fileURL.path),
      let firstLine = reader.nextLine(),
      firstLine.hasPrefix("start="),
      let progressString = firstLine.components(separatedBy: "=").last,
      let progress = Double(progressString) {
      return VideoTime(progress)
    } else {
      return nil
    }
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

    var value : [NSAttributedStringKey : Any]? {
      get {
        let f: NSFont?
        let s: CGFloat
        let a = NSMutableParagraphStyle()
        switch self.size {
        case .system:
          s = NSFont.systemFontSize
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
          NSFont.systemFont(ofSize: NSFont.systemFontSize)
          return [
            .font: f,
            .paragraphStyle: a
          ]
        } else {
          return nil
        }
      }
    }
  }


  // http://stackoverflow.com/questions/31701326/

  struct ShortCodeGenerator {

    private static let base62chars = [Character]("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
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

