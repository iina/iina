//
//  InitialWindowView.swift
//  iina
//
//  Created by lhc on 20/6/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class InitialWindowView: NSViewController {

  override var nibName: String {
    return "InitialWindowView"
  }

  weak var mainWindow: MainWindowController!

  @IBOutlet weak var recentFilesTableView: NSTableView!
  @IBOutlet weak var appIcon: NSImageView!
  @IBOutlet weak var versionLabel: NSTextField!

  lazy var recentDocuments: [URL] = NSDocumentController.shared().recentDocumentURLs

  override func viewDidLoad() {
    super.viewDidLoad()
    view.wantsLayer = true
    view.layer?.backgroundColor = CGColor(gray: 0.1, alpha: 1)
    appIcon.image = NSApp.applicationIconImage

    let infoDic = Bundle.main.infoDictionary!
    let version = infoDic["CFBundleShortVersionString"] as! String
    let build = infoDic["CFBundleVersion"] as! String
    versionLabel.stringValue = "\(version) Build \(build)"

    recentFilesTableView.delegate = self
    recentFilesTableView.dataSource = self
  }
    
}


extension InitialWindowView: NSTableViewDelegate, NSTableViewDataSource {

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
    mainWindow.playerCore.openFile(recentDocuments[recentFilesTableView.selectedRow])
    mainWindow.initialWindowView.view.isHidden = true
  }

}


class InitialWindowViewActionButton: NSButton {

  override func awakeFromNib() {
    self.wantsLayer = true
    self.layer?.cornerRadius = 4
    self.addTrackingArea(NSTrackingArea(rect: self.bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited], owner: self, userInfo: nil))
  }

  override func mouseEntered(with event: NSEvent) {
    self.layer?.backgroundColor = CGColor(gray: 0, alpha: 0.2)
  }

  override func mouseExited(with event: NSEvent) {
    self.layer?.backgroundColor = CGColor(gray: 0, alpha: 0)
  }

}
