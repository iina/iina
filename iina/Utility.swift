//
//  Utility.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

typealias PK = Preference.Key

class Utility {

  static let supportedFileExt: [MPVTrack.TrackType: [String]] = [
    .video: ["mkv", "mp4", "avi", "m4v", "mov", "3gp", "ts", "mts", "m2ts", "wmv", "flv", "f4v", "asf", "webm", "rm", "rmvb", "qt", "dv", "mpg", "mpeg", "mxf", "vob", "gif"],
    .audio: ["mp3", "aac", "mka", "dts", "flac", "ogg", "oga", "mogg", "m4a", "ac3", "opus", "wav", "wv", "aiff", "aif", "ape", "tta", "tak"],
    .sub: ["utf", "utf8", "utf-8", "idx", "sub", "srt", "smi", "rt", "ssa", "aqt", "jss", "js", "ass", "mks", "vtt", "sup", "scc"]
  ]
  static let playableFileExt = supportedFileExt[.video]! + supportedFileExt[.audio]!
  static let singleFilePlaylistExt = ["cue"]
  static let multipleFilePlaylistExt = ["m3u", "m3u8", "pls"]
  static let playlistFileExt = singleFilePlaylistExt + multipleFilePlaylistExt
  static let blacklistExt = supportedFileExt[.sub]! + multipleFilePlaylistExt
  static let lut3dExt = ["3dl", "cube", "dat", "m3d"]

  // MARK: - Logs, alerts

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
    @unknown default:
      assertionFailure("Unknown \(type(of: alertStyle)) \(alertStyle)")
    }
    alert.informativeText = message
    alert.alertStyle = alertStyle
    alert.runModal()
  }

  static func showAlert(_ key: String, comment: String? = nil, arguments: [CVarArg]? = nil, style: NSAlert.Style = .critical, sheetWindow: NSWindow? = nil) {
    let alert = NSAlert()
    switch style {
    case .critical:
      alert.messageText = NSLocalizedString("alert.title_error", comment: "Error")
    case .informational:
      alert.messageText = NSLocalizedString("alert.title_info", comment: "Information")
    case .warning:
      alert.messageText = NSLocalizedString("alert.title_warning", comment: "Warning")
    @unknown default:
      assertionFailure("Unknown \(type(of: style)) \(style)")
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
    if let sheetWindow = sheetWindow {
      alert.beginSheetModal(for: sheetWindow)
    } else {
      alert.runModal()
    }
  }

  // MARK: - Panels, Alerts

  /**
   Pop up an ask panel.
   - Parameters:
     - key: A localization key. "alert.`key`.title" will be used as alert title, and "alert.`key`.message" will be the informative text.
     - titleComment: (Optional) Comment for title key.
     - messageComment: (Optional) Comment for message key.
     - sheetWindow: (Optional) The window on which to display the sheet; if this value is nil then run modal.
     - callback: (Optional) Completion handler used by sheet modal.
   - Returns: Whether user dismissed the panel by clicking OK, discardable when using sheet.
   */
  @discardableResult
  static func quickAskPanel(_ key: String, titleComment: String? = nil, messageComment: String? = nil, sheetWindow: NSWindow? = nil, callback: ((NSApplication.ModalResponse) -> Void)? = nil) -> Bool {
    let panel = NSAlert()
    let titleKey = "alert." + key + ".title"
    let messageKey = "alert." + key + ".message"
    panel.messageText = NSLocalizedString(titleKey, comment: titleComment ?? titleKey)
    panel.informativeText = NSLocalizedString(messageKey, comment: messageComment ?? messageKey)
    panel.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    panel.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))

    if let sheetWindow = sheetWindow {
      panel.beginSheetModal(for: sheetWindow, completionHandler: callback)
      return false
    } else {
      return panel.runModal() == .alertFirstButtonReturn
    }
  }

  /**
   Pop up an open panel.
   - Parameters:
     - title: Title of the panel.
     - chooseDir: Chooses directories or not; if false, then only choose files.
     - dir: (Optional) Base directory.
     - sheetWindow: (Optional) The window on which to display the sheet.
     - callback: (Optional) Completion handler.
   */
  static func quickOpenPanel(title: String, chooseDir: Bool, dir: URL? = nil, sheetWindow: NSWindow? = nil, allowedFileTypes: [String]? = nil, callback: @escaping (URL) -> Void) {
    let panel = NSOpenPanel()
    panel.title = title
    panel.canCreateDirectories = false
    panel.canChooseFiles = !chooseDir
    panel.canChooseDirectories = chooseDir
    panel.resolvesAliases = true
    panel.allowedFileTypes = allowedFileTypes
    panel.allowsMultipleSelection = false
    panel.level = .modalPanel
    if let dir = dir {
      panel.directoryURL = dir
    }
    let handler: (NSApplication.ModalResponse) -> Void = { result in
      if result == .OK, let url = panel.url {
        callback(url)
      }
    }
    if let sheetWindow = sheetWindow {
      panel.beginSheetModal(for: sheetWindow, completionHandler: handler)
    } else {
      panel.begin(completionHandler: handler)
    }
  }

  /**
   Pop up an open panel.
   - Parameters
     - title: Title of the panel.
     - dir: (Optional) Base directory.
     - sheetWindow: (Optional) The window on which to display the sheet.
     - callback: (Optional) Completion handler.
   */
  static func quickMultipleOpenPanel(title: String, dir: URL? = nil, canChooseDir: Bool, callback: @escaping ([URL]) -> Void) {
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
        callback(panel.urls)
      }
    }
  }

  /**
   Pop up a save panel.
   */
  static func quickSavePanel(title: String, types: [String], sheetWindow: NSWindow? = nil, callback: @escaping (URL) -> Void) {
    let panel = NSSavePanel()
    panel.title = title
    panel.canCreateDirectories = true
    panel.allowedFileTypes = types
    let handler: (NSApplication.ModalResponse) -> Void = { result in
      if result == .OK, let url = panel.url {
        callback(url)
      }
    }
    if let sheetWindow = sheetWindow {
      panel.beginSheet(sheetWindow, completionHandler: handler)
    } else {
      panel.begin(completionHandler: handler)
    }
  }

  /**
   Pop up a prompt panel.
   - parameters:
     - key: A localization key. "alert.`key`.title" will be used as alert title, and "alert.`key`.message" will be the informative text.
     - titleComment: (Optional) Comment for title key.
     - messageComment: (Optional) Comment for message key.
     - sheetWindow: (Optional) The window on which to display the sheet.
     - callback: (Optional) Completion handler.
   - Returns: Whether user dismissed the panel by clicking OK. Only works when using `.modal` mode.
   */
  @discardableResult
  static func quickPromptPanel(_ key: String, titleComment: String? = nil, messageComment: String? = nil, sheetWindow: NSWindow? = nil, callback: @escaping (String) -> Void) -> Bool {
    let panel = NSAlert()
    let titleKey = "alert." + key + ".title"
    let messageKey = "alert." + key + ".message"
    panel.messageText = NSLocalizedString(titleKey, comment: titleComment ?? titleKey)
    panel.informativeText = NSLocalizedString(messageKey, comment: messageComment ?? messageKey)
    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    input.lineBreakMode = .byClipping
    input.usesSingleLineMode = true
    input.cell?.isScrollable = true
    panel.accessoryView = input
    panel.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    panel.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    panel.window.initialFirstResponder = input

    if let sheetWindow = sheetWindow {
      panel.beginSheetModal(for: sheetWindow) { response in
        if response == .alertFirstButtonReturn {
          callback(input.stringValue)
        }
      }
    } else {
      if panel.runModal() == .alertFirstButtonReturn {
        callback(input.stringValue)
        return true
      }
    }
    return false
  }

  /**
   Pop up a username and password panel.
   - parameters:
     - key: A localization key. "alert.`key`.title" will be used as alert title, and "alert.`key`.message" will be the informative text.
     - titleComment: (Optional) Comment for title key.
     - messageComment: (Optional) Comment for message key.
   - Returns: Whether user dismissed the panel by clicking OK.
   */
  static func quickUsernamePasswordPanel(_ key: String, titleComment: String? = nil, messageComment: String? = nil, sheetWindow: NSWindow? = nil, callback: @escaping (String, String) -> Void) {
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
    let input = NSTextField(frame: NSRect(x: 0, y: 42, width: 240, height: 24))
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
    if let sheetWindow = sheetWindow {
      panel.beginSheetModal(for: sheetWindow) { response in
        if response == .alertFirstButtonReturn {
          callback(input.stringValue, pwField.stringValue)
        }
      }
    } else {
      let response = panel.runModal()
      if response == .alertFirstButtonReturn {
        callback(input.stringValue, pwField.stringValue)
      }
    }
  }

  /**
   Pop up a font picker panel.
   - parameters:
     - callback: A closure accepting the font name.
   */
  static func quickFontPickerWindow(callback: @escaping (String?) -> Void) {
    guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
    appDelegate.fontPicker.finishedPicking = callback
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
  
  static let cacheURL: URL = {
    let cachesPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
    Logger.ensure(cachesPath.count >= 1, "Cannot get path to Caches directory")
    let bundleID = Bundle.main.bundleIdentifier!
    let appCachesUrl = cachesPath.first!.appendingPathComponent(bundleID, isDirectory: true)
    return appCachesUrl
  }()

  static let thumbnailCacheURL: URL = {
    let appThumbnailCacheUrl = cacheURL.appendingPathComponent(AppData.thumbnailCacheFolder, isDirectory: true)
    createDirIfNotExist(url: appThumbnailCacheUrl)
    return appThumbnailCacheUrl
  }()
  
  static let screenshotCacheURL: URL = {
    let url = cacheURL.appendingPathComponent(AppData.screenshotCacheFolder, isDirectory: true)
    createDirIfNotExist(url: url)
    return url
  }()

  static let playbackHistoryURL: URL = {
    return Utility.appSupportDirUrl.appendingPathComponent(AppData.historyFile, isDirectory: false)
  }()

  static let tempDirURL: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

  static let exeDirURL: URL = URL(fileURLWithPath: Bundle.main.executablePath!).deletingLastPathComponent()


  // MARK: - Util functions

  static func setBoldTitle(for button: NSButton, _ active: Bool) {
    button.attributedTitle = NSAttributedString(string: button.title,
                                                attributes: FontAttributes(font: active ? .systemBold : .system, size: .system, align: .center).value)
  }

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

  @available(macOS, deprecated: 10.14, message: "Use the system appearance-based APIs instead.")
  static func getAppearanceAndMaterial(from theme: Preference.Theme) -> (NSAppearance?, NSVisualEffectView.Material) {
    switch theme {
    case .ultraDark:
      return (NSAppearance(named: .vibrantDark), .ultraDark)
    case .light:
      return (NSAppearance(named: .vibrantLight), .light)
    case .mediumLight:
      return (NSAppearance(named: .vibrantLight), .mediumLight)
    default:
      return (NSAppearance(named: .vibrantDark), .dark)
    }
  }

  static func getLatestScreenshot(from path: String) -> URL? {
    let folder = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    guard let contents = try? FileManager.default.contentsOfDirectory(
      at: folder,
      includingPropertiesForKeys: [.creationDateKey],
      options: .skipsSubdirectoryDescendants) else { return nil }

    var latestDate = Date.distantPast
    var latestFile: URL = contents[0]

    for file in contents {
      if let date = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate, date > latestDate {
        latestDate = date
        latestFile = file
      }
    }
    return latestFile
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

    var value : [NSAttributedString.Key : Any]? {
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

  static func resolvePaths(_ paths: [String]) -> [String] {
    return paths.map { (try? URL(resolvingAliasFileAt: URL(fileURLWithPath: $0)))?.path ?? $0 }
  }

  static func resolveURLs(_ urls: [URL]) -> [URL] {
    return urls.map { (try? URL(resolvingAliasFileAt: $0)) ?? $0 }
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

