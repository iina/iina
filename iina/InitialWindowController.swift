//
//  InitialWindowController.swift
//  iina
//
//  Created by lhc on 27/6/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

fileprivate extension NSUserInterfaceItemIdentifier {
  static let openFile = NSUserInterfaceItemIdentifier("openFile")
  static let openURL = NSUserInterfaceItemIdentifier("openURL")
  static let resumeLast = NSUserInterfaceItemIdentifier("resumeLast")
}

fileprivate extension NSColor {
  static let initialWindowActionButtonBackground: NSColor = {
    if #available(macOS 10.14, *) {
      return NSColor(named: .initialWindowActionButtonBackground)!
    } else {
      return NSColor(calibratedWhite: 0, alpha: 0)
    }
  }()
  static let initialWindowActionButtonBackgroundHover: NSColor = {
    if #available(macOS 10.14, *) {
      return NSColor(named: .initialWindowActionButtonBackgroundHover)!
    } else {
      return NSColor(calibratedWhite: 0, alpha: 0.25)
    }
  }()
  static let initialWindowActionButtonBackgroundPressed: NSColor = {
    if #available(macOS 10.14, *) {
      return NSColor(named: .initialWindowActionButtonBackgroundPressed)!
    } else {
      return NSColor(calibratedWhite: 0, alpha: 0.35)
    }
  }()
  static let initialWindowLastFileBackground: NSColor = {
    if #available(macOS 10.14, *) {
      return NSColor(named: .initialWindowLastFileBackground)!
    } else {
      return NSColor(calibratedWhite: 1, alpha: 0.1)
    }
  }()
  static let initialWindowLastFileBackgroundHover: NSColor = {
    if #available(macOS 10.14, *) {
      return NSColor(named: .initialWindowLastFileBackgroundHover)!
    } else {
      return NSColor(calibratedWhite: 0.5, alpha: 0.1)
    }
  }()
  static let initialWindowLastFileBackgroundPressed: NSColor = {
    if #available(macOS 10.14, *) {
      return NSColor(named: .initialWindowLastFileBackgroundPressed)!
    } else {
      return NSColor(calibratedWhite: 0, alpha: 0.1)
    }
  }()
  static let initialWindowBetaLabel: NSColor = {
    if #available(macOS 10.14, *) {
      return NSColor(named: .initialWindowBetaLabel)!
    } else {
      return NSColor(calibratedRed: 1, green: 0.6, blue: 0.2, alpha: 1)
    }
  }()
}


class InitialWindowController: NSWindowController {

  override var windowNibName: NSNib.Name {
    return NSNib.Name("InitialWindowController")
  }

  weak var player: PlayerCore!

  var loaded = false

  @IBOutlet weak var recentFilesTableView: NSTableView!
  @IBOutlet weak var appIcon: NSImageView!
  @IBOutlet weak var versionLabel: NSTextField!
  @IBOutlet weak var visualEffectView: NSVisualEffectView!
  @IBOutlet weak var leftOverlayView: NSView!
  @IBOutlet weak var mainView: NSView!
  @IBOutlet weak var betaIndicatorView: BetaIndicatorView!
  @IBOutlet weak var lastFileContainerView: InitialWindowViewActionButton!
  @IBOutlet weak var lastFileIcon: NSImageView!
  @IBOutlet weak var lastFileNameLabel: NSTextField!
  @IBOutlet weak var lastPositionLabel: NSTextField!
  @IBOutlet weak var recentFilesTableTopConstraint: NSLayoutConstraint!

  private let observedPrefKeys: [Preference.Key] = [.themeMaterial]

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath, let change = change else { return }

    switch keyPath {

    case Preference.Key.themeMaterial.rawValue:
      if let newValue = change[.newKey] as? Int {
        setMaterial(Preference.Theme(rawValue: newValue))
      }

    default:
      return
    }
  }

  lazy var recentDocuments: [URL] = {
    NSDocumentController.shared.recentDocumentURLs.filter { $0 != lastPlaybackURL }
  }()
  private var lastPlaybackURL: URL?

  init(playerCore: PlayerCore) {
    self.player = playerCore
    super.init(window: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func windowDidLoad() {
    super.windowDidLoad()
    loaded = true

    window?.titlebarAppearsTransparent = true
    window?.titleVisibility = .hidden
    window?.isMovableByWindowBackground = true

    window?.contentView?.registerForDraggedTypes([.nsFilenames, .nsURL, .string])

    mainView.wantsLayer = true

    let (version, build) = Utility.iinaVersion()
    let isStableRelease = !version.contains("-")
    versionLabel.stringValue = isStableRelease ? version : "\(version) (\(build))"
    betaIndicatorView.isHidden = isStableRelease

    loadLastPlaybackInfo()

    recentFilesTableView.delegate = self
    recentFilesTableView.dataSource = self

    setMaterial(Preference.enum(for: .themeMaterial))

    observedPrefKeys.forEach { key in
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }
  }

  private func setMaterial(_ theme: Preference.Theme?) {
    guard let window = window, let theme = theme else { return }
    if #available(macOS 10.14, *) {
      window.appearance = NSAppearance(iinaTheme: theme)
      if #available(macOS 10.16, *) {
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = window.effectiveAppearance.isDark ?
          [NSColor.black.withAlphaComponent(0.4).cgColor, NSColor.black.withAlphaComponent(0).cgColor] :
          [NSColor.black.withAlphaComponent(0.1).cgColor, NSColor.black.withAlphaComponent(0).cgColor]
        leftOverlayView.wantsLayer = true
        leftOverlayView.layer = gradientLayer
      }
    } else {
      window.appearance = NSAppearance(named: .vibrantDark)
      mainView.layer?.backgroundColor = CGColor(gray: 0.1, alpha: 1)
      visualEffectView.material = .ultraDark
    }
  }

  func loadLastPlaybackInfo() {
    if Preference.bool(for: .recordRecentFiles),
      Preference.bool(for: .resumeLastPosition),
      let lastFile = Preference.url(for: .iinaLastPlayedFilePath),
      FileManager.default.fileExists(atPath: lastFile.path) {
      // if last file exists
      lastPlaybackURL = lastFile
      lastFileContainerView.isHidden = false
      lastFileContainerView.normalBackground = NSColor.initialWindowLastFileBackground
      lastFileContainerView.hoverBackground = NSColor.initialWindowLastFileBackgroundHover
      lastFileContainerView.pressedBackground = NSColor.initialWindowLastFileBackgroundPressed
      lastFileIcon.image = #imageLiteral(resourceName: "history")
      lastFileNameLabel.stringValue = lastFile.lastPathComponent
      let lastPosition = Preference.double(for: .iinaLastPlayedFilePosition)
      lastPositionLabel.stringValue = VideoTime(lastPosition).stringRepresentation
      recentFilesTableTopConstraint.constant = 42
    } else {
      lastPlaybackURL = nil
      lastFileContainerView.isHidden = true
      recentFilesTableTopConstraint.constant = 24
    }
  }

  func reloadData() {
    loadLastPlaybackInfo()
    recentDocuments = NSDocumentController.shared.recentDocumentURLs.filter { $0 != lastPlaybackURL }
    recentFilesTableView.reloadData()
  }
}


extension InitialWindowController: NSTableViewDelegate, NSTableViewDataSource {

  func numberOfRows(in tableView: NSTableView) -> Int {
    return recentDocuments.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    let url = recentDocuments[row]
    return [
      "filename": url.lastPathComponent,
      "docIcon": NSWorkspace.shared.icon(forFile: url.path)
    ]
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard let url = recentDocuments[at: recentFilesTableView.selectedRow] else { return }
    player.openURL(url)
    recentFilesTableView.deselectAll(nil)
  }

}


class InitialWindowContentView: NSView {

  var player: PlayerCore {
    return (window!.windowController as! InitialWindowController).player
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    return player.acceptFromPasteboard(sender)
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    return player.openFromPasteboard(sender)
  }

}


class InitialWindowViewActionButton: NSView {

  var normalBackground = NSColor.initialWindowActionButtonBackground {
    didSet {
      self.layer?.backgroundColor = normalBackground.cgColor
    }
  }
  var hoverBackground = NSColor.initialWindowActionButtonBackgroundHover
  var pressedBackground = NSColor.initialWindowActionButtonBackgroundPressed

  var action: Selector?

  override func awakeFromNib() {
    self.wantsLayer = true
    self.layer?.cornerRadius = 6
    self.layer?.backgroundColor = normalBackground.cgColor
    self.addTrackingArea(NSTrackingArea(rect: self.bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited], owner: self, userInfo: nil))
  }

  override func mouseEntered(with event: NSEvent) {
    self.layer?.backgroundColor = hoverBackground.cgColor
  }

  override func mouseExited(with event: NSEvent) {
    self.layer?.backgroundColor = normalBackground.cgColor
  }

  override func mouseDown(with event: NSEvent) {
    self.layer?.backgroundColor = pressedBackground.cgColor
    if self.identifier == .openFile {
      (NSApp.delegate as! AppDelegate).openFile(self)
    } else if self.identifier == .openURL {
      (NSApp.delegate as! AppDelegate).openURL(self)
    } else {
      if let lastFile = Preference.url(for: .iinaLastPlayedFilePath),
        let windowController = window?.windowController as? InitialWindowController {
        windowController.player.openURL(lastFile)
      }
    }
  }

  override func mouseUp(with event: NSEvent) {
    self.layer?.backgroundColor = hoverBackground.cgColor
  }

}


class BetaIndicatorView: NSView {

  @IBOutlet var betaPopover: NSPopover!
  @IBOutlet var text1: NSTextField!
  @IBOutlet var text2: NSTextField!

  override func awakeFromNib() {
    self.layer?.backgroundColor = NSColor.initialWindowBetaLabel.cgColor
    self.layer?.cornerRadius = 4
    self.addTrackingArea(NSTrackingArea(rect: self.bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited], owner: self, userInfo: nil))

    text1.setHTMLValue(text1.stringValue)
    text2.setHTMLValue(text2.stringValue)
  }

  override func mouseEntered(with event: NSEvent) {
    NSCursor.pointingHand.push()
  }

  override func mouseExited(with event: NSEvent) {
    NSCursor.pop()
  }

  override func mouseUp(with event: NSEvent) {
    if betaPopover.isShown {
      betaPopover.close()
    } else {
      betaPopover.show(relativeTo: self.bounds, of: self, preferredEdge: .maxX)
    }
  }

}
