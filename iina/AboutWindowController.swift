//
//  AboutWindowController.swift
//  iina
//
//  Created by lhc on 31/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class AboutWindowController: NSWindowController {

  override var windowNibName: String {
    return "AboutWindowController"
  }


  @IBOutlet weak var iconImageView: NSImageView!
  @IBOutlet weak var versionLabel: NSTextField!
  @IBOutlet weak var mpvVersionLabel: NSTextField!
  @IBOutlet weak var copyRightLabel: NSTextField!
  @IBOutlet weak var githubLabel: NSTextField!
  @IBOutlet weak var websiteLabel: NSTextField!
  @IBOutlet weak var emailLabel: NSTextField!


  override func windowDidLoad() {
    super.windowDidLoad()

    let infoDic = Bundle.main.infoDictionary!
    iconImageView.image = NSApp.applicationIconImage
    let version = infoDic["CFBundleShortVersionString"] as! String
    let build = infoDic["CFBundleVersion"] as! String
    versionLabel.stringValue = "\(version) Build \(build)"
    let copyright = infoDic["NSHumanReadableCopyright"] as! String
    copyRightLabel.stringValue = copyright

    mpvVersionLabel.stringValue = PlayerCore.shared.mpvController.mpvVersion

    githubLabel.allowsEditingTextAttributes = true
    githubLabel.isSelectable = true
    githubLabel.attributedStringValue = NSMutableAttributedString(linkTo: AppData.githubLink, text: AppData.githubLink, font: githubLabel.font!)!

    websiteLabel.allowsEditingTextAttributes = true
    websiteLabel.isSelectable = true
    websiteLabel.attributedStringValue = NSMutableAttributedString(linkTo: AppData.websiteLink, text: AppData.websiteLink, font: websiteLabel.font!)!

    emailLabel.allowsEditingTextAttributes = true
    emailLabel.isSelectable = true
    emailLabel.attributedStringValue = NSMutableAttributedString(linkTo: "mailto:\(AppData.emailLink)", text: AppData.emailLink, font: emailLabel.font!)!

  }

}
