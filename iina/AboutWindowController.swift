//
//  AboutWindowController.swift
//  iina
//
//  Created by lhc on 31/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class AboutWindowController: NSWindowController {

  override var windowNibName: NSNib.Name {
    return NSNib.Name("AboutWindowController")
  }


  @IBOutlet weak var iconImageView: NSImageView!
  @IBOutlet weak var iinaLabel: NSTextField! {
    didSet {
      iinaLabel.font = NSFont.systemFont(ofSize: 24, weight: .light)
    }
  }
  @IBOutlet weak var versionLabel: NSTextField!
  @IBOutlet weak var mpvVersionLabel: NSTextField!
  @IBOutlet var detailTextView: NSTextView!


  override func windowDidLoad() {
    super.windowDidLoad()

    window?.titlebarAppearsTransparent = true
    window?.backgroundColor = .white

    iconImageView.image = NSApp.applicationIconImage

    let (version, build) = Utility.iinaVersion()
    versionLabel.stringValue = "\(version) Build \(build)"
    // let copyright = infoDic["NSHumanReadableCopyright"] as! String

    mpvVersionLabel.stringValue = PlayerCore.active.mpv.mpvVersion

    let contrubutionFile = Bundle.main.path(forResource: "Contribution", ofType: "rtf")!
    detailTextView.readRTFD(fromFile: contrubutionFile)
  }

  @IBAction func creditsBtnAction(_ sender: Any) {
    guard let path = Bundle.main.path(forResource: "Credits", ofType: "rtf") else { return }
    NSWorkspace.shared.openFile(path)
  }

}
