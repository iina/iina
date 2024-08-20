//
//  OpenURLWindowController.swift
//  iina
//
//  Created by Collider LI on 25/8/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class OpenURLWindowController: NSWindowController, NSTextFieldDelegate, NSControlTextEditingDelegate, NSWindowDelegate {

  override var windowNibName: NSNib.Name {
    return NSNib.Name("OpenURLWindowController")
  }

  @IBOutlet weak var urlStackView: NSStackView!
  @IBOutlet weak var httpPrefixTextField: NSTextField!
  @IBOutlet weak var urlField: NSTextField!
  @IBOutlet weak var usernameField: NSTextField!
  @IBOutlet weak var passwordField: NSSecureTextField!
  @IBOutlet weak var rememberPasswordCheckBox: NSButton!
  @IBOutlet weak var errorMessageLabel: NSTextField!
  @IBOutlet weak var openButton: NSButton!

  @IBOutlet weak var overlayView: NSVisualEffectView!
  @IBOutlet weak var loadingMediaProgressIndicator: NSProgressIndicator!

  var isAlternativeAction = false

  var playerCore: PlayerCore?
  var loadingURL: String?

  override func windowDidLoad() {
    super.windowDidLoad()
    window?.isMovableByWindowBackground = true
    window?.titlebarAppearsTransparent = true
    window?.titleVisibility = .hidden
    urlStackView.setVisibilityPriority(.notVisible, for: httpPrefixTextField)
    urlField.delegate = self
    ([.closeButton, .miniaturizeButton, .zoomButton] as [NSWindow.ButtonType]).forEach {
      window?.standardWindowButton($0)?.isHidden = true
    }

    loadingMediaProgressIndicator.startAnimation(self)
  }

  func showLoadingScreen(playerCore: PlayerCore) {
    _ = window
    overlayView.isHidden = false
    self.playerCore = playerCore
    loadingURL = playerCore.info.currentURL?.absoluteString
    if #available(macOS 14, *) {
      NSApp.activate()
    } else {
      NSApp.activate(ignoringOtherApps: true)
    }
    showWindow(self)
  }

  func failedToLoadURL() {
    guard isWindowLoaded && window?.isVisible == true else { return }
    urlField.stringValue = loadingURL ?? ""
    errorMessageLabel.isHidden = false
    overlayView.isHidden = true
    urlField.textColor = .systemRed
  }

  func resetWindowState() {
    urlField.stringValue = ""
    usernameField.stringValue = ""
    passwordField.stringValue = ""
    rememberPasswordCheckBox.state = .off
    urlStackView.setVisibilityPriority(.notVisible, for: httpPrefixTextField)
    window?.makeFirstResponder(urlField)
    overlayView.isHidden = true
    playerCore = nil
    loadingURL = nil
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard let playerCore else { return true }
    playerCore.stop()
    return true
  }

  func windowWillClose(_ notification: Notification) {
    playerCore = nil
    overlayView.isHidden = true
  }

  override func cancelOperation(_ sender: Any?) {
    window?.close()
  }

  @IBAction func cancelBtnAction(_ sender: Any) {
    window?.close()
  }

  @IBAction func openBtnAction(_ sender: Any) {
    if let url = getURL().url {
      if rememberPasswordCheckBox.state == .on,
         let host = url.host,
         !usernameField.stringValue.isEmpty {
        try? KeychainAccess.write(username: usernameField.stringValue,
                                  password: passwordField.stringValue,
                                  forService: .httpAuth,
                                  server: host,
                                  port: url.port)
      }
      overlayView.isHidden = false
      playerCore = PlayerCore.activeOrNewForMenuAction(isAlternative: isAlternativeAction)
      playerCore!.openURL(url)
    } else {
      Utility.showAlert("wrong_url_format")
    }
  }

  private func getURL() -> (url: URL?, hasScheme: Bool) {
    guard !urlField.stringValue.isEmpty else { return (nil, false) }
    let username = usernameField.stringValue
    let password = passwordField.stringValue
    let trimmedUrlString = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var urlValue = trimmedUrlString.addingPercentEncoding(withAllowedCharacters: .urlAllowed) else {
      return (nil, false)
    }
    var hasScheme = true
    if let url = URL(string: urlValue), url.scheme == nil {
      urlValue = "http://" + urlValue
      hasScheme = false
    }
    guard let nsurl = NSURL(string: urlValue)?.standardized, let urlComponents = NSURLComponents(url: nsurl, resolvingAgainstBaseURL: false) else { return (nil, false) }
    if !username.isEmpty {
      urlComponents.user = username
      if !password.isEmpty {
        urlComponents.password = password
      }
    }
    return (urlComponents.url, hasScheme)
  }

  // NSControlTextEditingDelegate

  func controlTextDidChange(_ obj: Notification) {
    if let textView = obj.userInfo?["NSFieldEditor"] as? NSTextView, let str = textView.textStorage?.string, str.isEmpty {
      errorMessageLabel.isHidden = true
      urlStackView.setVisibilityPriority(.notVisible, for: httpPrefixTextField)
      openButton.isEnabled = true
      return
    }
    let (url, hasScheme) = getURL()
    if let url = url, let host = url.host {
      errorMessageLabel.isHidden = true
      urlField.textColor = .labelColor
      openButton.isEnabled = true
      if hasScheme {
        urlStackView.setVisibilityPriority(.notVisible, for: httpPrefixTextField)
      } else {
        urlStackView.setVisibilityPriority(.mustHold, for: httpPrefixTextField)
      }
      // find saved password
      if let (username, password) = try? KeychainAccess.read(username: nil, forService: .httpAuth, server: host, port: url.port) {
        usernameField.stringValue = username
        passwordField.stringValue = password
      } else {
        usernameField.stringValue = ""
        passwordField.stringValue = ""
      }
    } else {
      urlField.textColor = .systemRed
      errorMessageLabel.isHidden = false
      urlStackView.setVisibilityPriority(.notVisible, for: httpPrefixTextField)
      openButton.isEnabled = false
    }
  }

}
