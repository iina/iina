//
//  OpenURLAccessoryViewController.swift
//  iina
//
//  Created by lhc on 26/3/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class OpenURLAccessoryViewController: NSViewController {

  @IBOutlet weak var urlField: ShortcutAvailableTextField!

  @IBOutlet weak var safariLinkBtn: NSButton!
  @IBOutlet weak var chromeLinkBtn: NSButton!
  @IBOutlet weak var usernameField: NSTextField!
  @IBOutlet weak var passwordField: NSSecureTextField!

  var url: URL? {
    get {
      let username = usernameField.stringValue
      let password = passwordField.stringValue
      guard var urlValue = urlField.stringValue.addingPercentEncoding(withAllowedCharacters: .urlAllowed) else {
        return nil
      }
      if URL(string: urlValue)?.host == nil {
        urlValue = "http://" + urlValue
      }
      guard let urlComponents = NSURLComponents(string: urlValue) else { return nil }
      if !username.isEmpty && !password.isEmpty {
        urlComponents.user = username
        urlComponents.password = password
      }
      return urlComponents.url
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    [safariLinkBtn, chromeLinkBtn].forEach {
      $0!.image = NSImage(named: NSImageNameFollowLinkFreestandingTemplate)
    }
  }
    
}
