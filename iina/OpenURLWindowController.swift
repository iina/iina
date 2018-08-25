//
//  OpenURLWindowController.swift
//  iina
//
//  Created by Collider LI on 25/8/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class OpenURLWindowController: NSWindowController {

  override var windowNibName: NSNib.Name {
    return NSNib.Name("OpenURLWindowController")
  }

  @IBOutlet weak var urlField: NSTextField!
  @IBOutlet weak var usernameField: NSTextField!
  @IBOutlet weak var passwordField: NSTextField!

  var isAlternativeAction = false

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

  override func windowDidLoad() {
    super.windowDidLoad()
    window?.isMovableByWindowBackground = true
    window?.titlebarAppearsTransparent = true
    window?.titleVisibility = .hidden
    ([.closeButton, .miniaturizeButton, .zoomButton] as [NSWindow.ButtonType]).forEach {
      window?.standardWindowButton($0)?.isHidden = true
    }
  }

  func resetFields() {
    urlField.stringValue = ""
    usernameField.stringValue = ""
    passwordField.stringValue = ""
  }

  @IBAction func cancelBtnAction(_ sender: Any) {
    window?.close()
  }

  @IBAction func openBtnAction(_ sender: Any) {
    if let url = url {
      window?.close()
      PlayerCore.activeOrNewForMenuAction(isAlternative: isAlternativeAction).openURL(url)
    } else {
      Utility.showAlert("wrong_url_format")
    }
  }

  override func cancelOperation(_ sender: Any?) {
    window?.close()
  }
}
