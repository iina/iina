//
//  InitialWindowController.swift
//  iina
//
//  Created by lhc on 27/6/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class InitialWindowController: NSWindowController {

  override var windowNibName: String {
    return "InitialWindowController"
  }

  weak var player: PlayerCore!


  @IBOutlet weak var recentFilesTableView: NSTableView!
  @IBOutlet weak var appIcon: NSImageView!
  @IBOutlet weak var versionLabel: NSTextField!
  @IBOutlet weak var visualEffectView: NSVisualEffectView!
  @IBOutlet weak var mainView: NSView!

  lazy var recentDocuments: [URL] = NSDocumentController.shared().recentDocumentURLs

  init(playerCore: PlayerCore) {
    self.player = playerCore
    super.init(window: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func windowDidLoad() {
    super.windowDidLoad()
    window?.appearance = NSAppearance(named: NSAppearanceNameVibrantDark)
    window?.titlebarAppearsTransparent = true
    window?.isMovableByWindowBackground = true

    window?.contentView?.register(forDraggedTypes: [NSFilenamesPboardType, NSURLPboardType, NSPasteboardTypeString])

    mainView.wantsLayer = true
    mainView.layer?.backgroundColor = CGColor(gray: 0.1, alpha: 1)
    appIcon.image = NSApp.applicationIconImage

    let infoDic = Bundle.main.infoDictionary!
    let version = infoDic["CFBundleShortVersionString"] as! String
    let build = infoDic["CFBundleVersion"] as! String
    versionLabel.stringValue = "\(version) Build \(build)"

    recentFilesTableView.delegate = self
    recentFilesTableView.dataSource = self

    if #available(OSX 10.11, *) {
      visualEffectView.material = .ultraDark
    }
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
      "docIcon": NSWorkspace.shared().icon(forFile: url.path)
    ]
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard let url = recentDocuments.at(recentFilesTableView.selectedRow) else { return }
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

  private let normalBackground = CGColor(gray: 0, alpha: 0)
  private let hoverBackground = CGColor(gray: 0, alpha: 0.25)
  private let pressedBackground = CGColor(gray: 0, alpha: 0.35)

  private let openFileBtnID = "openFile"
  private let openURLBtnID = "openURL"

  var action: Selector?

  override func awakeFromNib() {
    self.wantsLayer = true
    self.layer?.cornerRadius = 4
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
    if self.identifier == openFileBtnID {
      (NSApp.delegate as! AppDelegate).openFile(self)
    } else {
      (NSApp.delegate as! AppDelegate).openURL(self)
    }
  }

  override func mouseUp(with event: NSEvent) {
    self.layer?.backgroundColor = hoverBackground
  }
  
}
