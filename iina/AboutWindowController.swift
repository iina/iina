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

  @IBOutlet weak var windowBackgroundBox: NSBox!
  @IBOutlet weak var iconImageView: NSImageView!
  @IBOutlet weak var iinaLabel: NSTextField! {
    didSet {
      iinaLabel.font = NSFont.systemFont(ofSize: 24, weight: .light)
    }
  }
  @IBOutlet weak var versionLabel: NSTextField!
  @IBOutlet weak var mpvVersionLabel: NSTextField!
  @IBOutlet var detailTextView: NSTextView!
  @IBOutlet var creditsTextView: NSTextView!

  @IBOutlet weak var licenseButton: AboutWindowButton!
  @IBOutlet weak var contributorsButton: AboutWindowButton!
  @IBOutlet weak var creditsButton: AboutWindowButton!
  @IBOutlet weak var tabView: NSTabView!

  override func windowDidLoad() {
    super.windowDidLoad()

    // print(Translator.all)

    if #available(macOS 10.13, *) {
      windowBackgroundBox.fillColor = NSColor(named: .aboutWindowBackground)!
    } else {
      windowBackgroundBox.fillColor = .white
    }
    iconImageView.image = NSApp.applicationIconImage

    let (version, build) = Utility.iinaVersion()
    versionLabel.stringValue = "\(version) Build \(build)"
    // let copyright = infoDic["NSHumanReadableCopyright"] as! String

    mpvVersionLabel.stringValue = PlayerCore.active.mpv.mpvVersion

    if let contrubutionFile = Bundle.main.path(forResource: "Contribution", ofType: "rtf") {
      detailTextView.readRTFD(fromFile: contrubutionFile)
      detailTextView.textColor = NSColor.secondaryLabelColor
    }

    if let creditsFile = Bundle.main.path(forResource: "Credits", ofType: "rtf") {
      creditsTextView.readRTFD(fromFile: creditsFile)
      creditsTextView.textColor = NSColor.secondaryLabelColor
    }
  }

  @IBAction func sectionBtnAction(_ sender: NSButton) {
    tabView.selectTabViewItem(at: sender.tag)
    [licenseButton, contributorsButton, creditsButton].forEach {
      $0?.state = $0 == sender ? .on : .off
      $0?.updateState()
    }
  }

  private func getContributors() {

  }

}

class AboutWindowButton: NSButton {

  override func awakeFromNib() {
    wantsLayer = true
    layer?.cornerRadius = 4
    updateState()
  }

  func updateState() {
    if let cell = self.cell as? NSButtonCell {
      if #available(OSX 10.14, *) {
        cell.backgroundColor = state == .on ? .controlAccentColor : .clear
      } else {
        cell.backgroundColor = state == .on ? .systemBlue : .clear
      }
    }
    attributedTitle = NSAttributedString(string: title,
                                         attributes: [.foregroundColor: state == .on ? NSColor.white : NSColor.labelColor])
  }
}
