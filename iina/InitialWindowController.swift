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

class InitialWindowController: NSWindowController {

  override var windowNibName: NSNib.Name {
    return NSNib.Name("InitialWindowController")
  }

  weak var player: PlayerCore!


  @IBOutlet weak var recentFilesTableView: NSTableView!
  @IBOutlet weak var appIcon: NSImageView!
  @IBOutlet weak var versionLabel: NSTextField!
  @IBOutlet weak var visualEffectView: NSVisualEffectView!
  @IBOutlet weak var mainView: NSView!
  @IBOutlet weak var betaIndicatorView: BetaIndicatorView!
  @IBOutlet weak var lastFileContainerView: InitialWindowViewActionButton!
  @IBOutlet weak var lastFileIcon: NSImageView!
  @IBOutlet weak var lastFileNameLabel: NSTextField!
  @IBOutlet weak var lastPositionLabel: NSTextField!
  @IBOutlet weak var recentFilesTableTopConstraint: NSLayoutConstraint!

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
    
    if #available(macOS 10.14, *) {
      visualEffectView.material = .underWindowBackground
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
      lastFileContainerView.normalBackground = CGColor(gray: 1, alpha: 0.1)
      lastFileContainerView.hoverBackground = CGColor(gray: 0.5, alpha: 0.1)
      lastFileContainerView.pressedBackground = CGColor(gray: 0, alpha: 0.1)
      lastFileIcon.image = #imageLiteral(resourceName: "history").tinted(.white)
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
    if url.isExistingDirectory {
      let _ = player.openURLs([url])
    } else {
      player.openURL(url, shouldAutoLoad: true)
    }
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

  var normalBackground = CGColor(gray: 0, alpha: 0) {
    didSet {
      self.layer?.backgroundColor = normalBackground
    }
  }
  var hoverBackground = CGColor(gray: 0, alpha: 0.25)
  var pressedBackground = CGColor(gray: 0, alpha: 0.35)

  var action: Selector?

  override func awakeFromNib() {
    self.wantsLayer = true
    self.layer?.cornerRadius = 4
    self.layer?.backgroundColor = normalBackground
    self.addTrackingArea(NSTrackingArea(rect: self.bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited], owner: self, userInfo: nil))
  }

  override func mouseEntered(with event: NSEvent) {
    self.layer?.backgroundColor = hoverBackground
  }

  override func mouseExited(with event: NSEvent) {
    self.layer?.backgroundColor = normalBackground
  }

  override func mouseDown(with event: NSEvent) {
    self.layer?.backgroundColor = pressedBackground
    if self.identifier == .openFile {
      (NSApp.delegate as! AppDelegate).openFile(self)
    } else if self.identifier == .openURL {
      (NSApp.delegate as! AppDelegate).openURL(self)
    } else {
      if let lastFile = Preference.url(for: .iinaLastPlayedFilePath),
        let windowController = window?.windowController as? InitialWindowController {
        windowController.player.openURL(lastFile, shouldAutoLoad: true)
      }
    }
  }

  override func mouseUp(with event: NSEvent) {
    self.layer?.backgroundColor = hoverBackground
  }
  
}


class BetaIndicatorView: NSView {

  @IBOutlet var betaPopover: NSPopover!
  @IBOutlet var text1: NSTextField!
  @IBOutlet var text2: NSTextField!

  override func awakeFromNib() {
    self.layer?.backgroundColor = CGColor(red: 1, green: 0.6, blue: 0.2, alpha: 1)
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
