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

  @IBOutlet weak var usernameField: NSTextField!
  @IBOutlet weak var passwordField: NSSecureTextField!

  var url: URL? {
    get {
      guard !urlField.stringValue.isEmpty else { return nil }
      let username = usernameField.stringValue
      let password = passwordField.stringValue
      guard var urlValue = urlField.stringValue.addingPercentEncoding(withAllowedCharacters: .urlAllowed) else {
        return nil
      }
      if let url = URL(string: urlValue),
        url.scheme == nil {
        urlValue = "http://" + urlValue
      }
      guard let nsurl = NSURL(string: urlValue)?.standardized, let urlComponents = NSURLComponents(url: nsurl, resolvingAgainstBaseURL: false) else { return nil }
      if !username.isEmpty {
        urlComponents.user = username
        if !password.isEmpty {
          urlComponents.password = password
        }
      }
      return urlComponents.url
    }
  }

}
