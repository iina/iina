//
//  GuideWindowController.swift
//  iina
//
//  Created by Collider LI on 26/8/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa
@preconcurrency import WebKit

fileprivate let highlightsLink = "https://iina.io/highlights"

fileprivate let ui = UIHelper(scope: "guide_window")

class GuideWindowController: NSWindowController {
  enum Page {
    case highlights
  }

  private var page = 0

  var highlightsWebView: WKWebView?
  private let highlightsContainerView = NSView()
  private let highlightsLoadingIndicator = NSProgressIndicator()
  private let highlightsLoadingFailedBox = NSBox()

  init() {
    let window = CommonWindow(
      contentRect: NSRect(x: 0, y: 0, width: 740, height: 600),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    super.init(window: window)
    setupViews()
    window.center()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupViews() {
    guard let contentView = window?.contentView else { return }

    highlightsContainerView.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(highlightsContainerView)
    highlightsContainerView.padding(.top, .horizontal).size(width: 740, height: 540)

    highlightsLoadingIndicator.translatesAutoresizingMaskIntoConstraints = false
    highlightsLoadingIndicator.style = .spinning
    highlightsLoadingIndicator.isIndeterminate = true
    highlightsContainerView.addSubview(highlightsLoadingIndicator)
    highlightsLoadingIndicator.center()

    let failedLabel = ui.label("fail", wrapping: true, canCompress: false)
    failedLabel.alignment = .center
    let websiteBtn = ui.button("website", target: self, action: #selector(visitIINAWebsite(_:)))

    highlightsLoadingFailedBox.translatesAutoresizingMaskIntoConstraints = false
    highlightsLoadingFailedBox.boxType = .custom
    highlightsLoadingFailedBox.cornerRadius = 4
    highlightsLoadingFailedBox.borderColor = .tertiaryLabelColor
    highlightsLoadingFailedBox.fillColor = .windowBackgroundColor
    highlightsLoadingFailedBox.titlePosition = .noTitle
    highlightsLoadingFailedBox.isHidden = true
    highlightsContainerView.addSubview(highlightsLoadingFailedBox)
    highlightsLoadingFailedBox.size(width: 360).center()

    let boxContentView = highlightsLoadingFailedBox.contentView!
    boxContentView.addSubview(failedLabel)
    boxContentView.addSubview(websiteBtn)
    failedLabel.padding(.top(16), .horizontal(16))
    websiteBtn.padding(.bottom(16)).spacing(.top(16), to: failedLabel).center(.x)

    let bottomBar = NSVisualEffectView()
    bottomBar.translatesAutoresizingMaskIntoConstraints = false
    bottomBar.material = .titlebar
    contentView.addSubview(bottomBar)
    bottomBar.padding(.bottom, .horizontal).spacing(.top, to: highlightsContainerView).size(height: 48)

    let continueBtnCell = GuideWindowButtonCell(textCell: "")
    continueBtnCell.setButtonType(.momentaryPushIn)
    continueBtnCell.bezelStyle = .shadowlessSquare
    continueBtnCell.isBordered = true
    let continueBtn = NSButton()
    continueBtn.translatesAutoresizingMaskIntoConstraints = false
    continueBtn.cell = continueBtnCell
    continueBtn.attributedTitle = NSAttributedString(
      string: ui.localized("continue"),
      attributes: [.foregroundColor: NSColor.white]
    )
    continueBtn.target = self
    continueBtn.action = #selector(continueBtnAction(_:))
    bottomBar.addSubview(continueBtn)
    continueBtn.size(width: 140, height: 32).center()
  }

  func show(pages: [Page]) {
    loadHighlightsPage()
    showWindow(self)
  }

  private func loadHighlightsPage() {
    window?.title = NSLocalizedString("guide.highlights", comment: "Highlights")
    let webView = WKWebView()
    highlightsWebView = webView
    webView.isHidden = true
    webView.translatesAutoresizingMaskIntoConstraints = false
    webView.navigationDelegate = self
    highlightsContainerView.addSubview(webView, positioned: .below, relativeTo: nil)
    Utility.quickConstraints(["H:|-0-[v]-0-|", "V:|-0-[v]-0-|"], ["v": webView])

    let (version, _) = InfoDictionary.shared.version
    webView.load(URLRequest(url: URL(string: "\(highlightsLink)/\(version.split(separator: "-").first!)/")!))
    highlightsLoadingIndicator.startAnimation(nil)
  }

  @objc func continueBtnAction(_ sender: Any) {
    window?.close()
  }

  @objc func visitIINAWebsite(_ sender: Any) {
    NSWorkspace.shared.open(URL(string: AppData.websiteLink)!)
  }
}

extension GuideWindowController: WKNavigationDelegate {
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    if let url = navigationAction.request.url {
      if url.absoluteString.starts(with: "https://iina.io/highlights/") {
        decisionHandler(.allow)
        return
      } else {
        NSWorkspace.shared.open(url)
      }
    }
    decisionHandler(.cancel)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    highlightsLoadingIndicator.stopAnimation(nil)
    highlightsLoadingIndicator.isHidden = true
    highlightsLoadingFailedBox.isHidden = false
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    highlightsLoadingIndicator.stopAnimation(nil)
    highlightsLoadingIndicator.isHidden = true
    highlightsLoadingFailedBox.isHidden = false
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    highlightsLoadingIndicator.stopAnimation(nil)
    highlightsLoadingIndicator.isHidden = true
    highlightsWebView?.isHidden = false
  }
}

class GuideWindowButtonCell: NSButtonCell {
  override func drawBezel(withFrame frame: NSRect, in controlView: NSView) {
    NSGraphicsContext.saveGraphicsState()
    let rectPath = NSBezierPath(
      roundedRect: NSRect(x: 2, y: 2, width: frame.width - 4, height: frame.height - 4),
      xRadius: 4, yRadius: 4
    )

    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: 0)
    shadow.shadowBlurRadius = 1
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
    shadow.set()

    if isHighlighted {
      NSColor.systemBlue.highlight(withLevel: 0.1)?.setFill()
    } else {
      NSColor.systemBlue.setFill()
    }
    rectPath.fill()
    NSGraphicsContext.restoreGraphicsState()
  }
}
