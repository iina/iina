//
//  Titlebar.swift
//  iina
//
//  Created by Hechen Li on 2026-06-01.
//  Copyright © 2026 lhc. All rights reserved.
//

fileprivate let TitlebarHeight: CGFloat = 32
fileprivate let DocIconLeadingPadding: CGFloat = 88


class Titlebar: NSView {
  let useSystemTitle = false

  var isTransparant = false {
    didSet {
      updateShadow()
      updateMask()
    }
  }

  weak var mainWindow: MainWindowController!

  var background: NSVisualEffectView
  var titlebarOnTopButton: NSButton
  var titleBarBottomBorder: NSBox

  var titlebarContainer: NSView!
  var titlebarTrailingConstraint: NSLayoutConstraint!
  var titleTextField: NSTextField!
  var docIcon: NSImageView!

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow

    let window = mainWindow.window!

    self.background = NSVisualEffectView()
    background.translatesAutoresizingMaskIntoConstraints = false

    self.titleBarBottomBorder = NSBox()
    titleBarBottomBorder.translatesAutoresizingMaskIntoConstraints = false

    self.titlebarOnTopButton = NSButton(image: .sf("pin")!,
                                        target: mainWindow,
                                        action: #selector(MainWindowController.ontopButtonAction))
    titlebarOnTopButton.translatesAutoresizingMaskIntoConstraints = false

    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false

    background.blendingMode = .withinWindow
    background.material = .titlebar
    background.wantsLayer = true
    background.layerContentsRedrawPolicy = .onSetNeedsDisplay
    background.state = .active
    addSubview(background)
    background.padding(.top, .horizontal, .bottom(1))

    titleBarBottomBorder.boxType = .separator
    addSubview(titleBarBottomBorder)
    titleBarBottomBorder.fillColor = .titleBarBorder
    titleBarBottomBorder.padding(.horizontal, .bottom).size(height: 1)

    titlebarOnTopButton.frame.size.width = 30
    titlebarOnTopButton.isBordered = false
    updateOnTopIcon()

    if useSystemTitle {
      let titlebarAccessoryViewController = NSTitlebarAccessoryViewController()
      titlebarAccessoryViewController.view = titlebarOnTopButton
      titlebarAccessoryViewController.layoutAttribute = .right
      mainWindow.window!.addTitlebarAccessoryViewController(titlebarAccessoryViewController)
    } else {
      window.titleVisibility = .hidden

      self.titlebarContainer = NSView()
      titlebarContainer.translatesAutoresizingMaskIntoConstraints = false
      addSubview(titlebarContainer)
      titlebarContainer.padding(.top, .leading(DocIconLeadingPadding))
        .size(height: TitlebarHeight)
      self.titlebarTrailingConstraint = trailingAnchor
        .constraint(equalTo: titlebarContainer.trailingAnchor)
      titlebarTrailingConstraint.isActive = true

      self.docIcon = NSImageView()
      docIcon.translatesAutoresizingMaskIntoConstraints = false
      titlebarContainer.addSubview(docIcon)
      docIcon.padding(.leading).center(.y)
        .size(width: 16, height: 16)

      self.titleTextField = NSTextField(labelWithString: window.title)
      titleTextField.translatesAutoresizingMaskIntoConstraints = false
      titleTextField.font = .titleBarFont(ofSize: 13)
      titleTextField.lineBreakMode = .byTruncatingMiddle
      titleTextField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      titlebarContainer.addSubview(titleTextField)
      titleTextField.padding(.leading(20)).center(.y)

      titlebarContainer.addSubview(titlebarOnTopButton)
      titlebarOnTopButton.padding(.trailing(8)).center(.y, offset: 1)
      titleTextField.spacing(.trailing(greaterThan: 8), to: titlebarOnTopButton)
    }

    updateShadow()
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func updateOnTopIcon() {
    let isOntop = mainWindow.isOntop
    titlebarOnTopButton.isHidden = Preference.bool(for: .alwaysShowOnTopIcon) ? false : !isOntop
    titlebarOnTopButton.image = isOntop ? .sf("pin.fill") : .sf("pin")
  }

  func updateTitle() {
    guard let titleTextField,
          let docIcon,
          let sysTitle = mainWindow.titleTextField else { return }

    titleTextField.stringValue = sysTitle.stringValue
    if let fileName = mainWindow.window?.representedFilename {
      docIcon.image = NSWorkspace.shared.icon(forFile: fileName)
    } else {
      docIcon.image = nil
    }
  }

  override func rightMouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)

    guard docIcon.frame.contains(point) || titleTextField.frame.contains(point) else {
      super.rightMouseDown(with: event)
      return
    }

    showPathMenu()
  }

  private func showPathMenu() {
    guard let filename = mainWindow.window?.representedFilename else { return }

    let menu = NSMenu()
    menu.autoenablesItems = false

    let url = URL(fileURLWithPath: filename)
    let point = NSPoint(x: -16, y: 26)  // make sure the first menu item is at the title's positon

    var current = url.standardizedFileURL
    var components: [URL] = []

    while true {
      components.append(current)
      let parent = current.deletingLastPathComponent()
      if parent == current { break }  // reached root
      current = parent
    }

    for pathURL in components {
      let item = NSMenuItem()
      item.title = FileManager.default.displayName(atPath: pathURL.path)
      item.image = NSWorkspace.shared.icon(forFile: pathURL.path)
      item.image?.size = NSSize(width: 16, height: 16)
      item.representedObject = pathURL
      item.target = self
      item.action = #selector(revealInFinder(_:))
      menu.addItem(item)
    }

    menu.popUp(positioning: nil, at: point, in: titlebarContainer)
  }

  @objc private func revealInFinder(_ sender: NSMenuItem) {
    guard let url = sender.representedObject as? URL else { return }
    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
  }

  override func layout() {
    super.layout()
    updateMask()
  }

  private func updateShadow() {
    if isTransparant {
      let shadow = NSShadow()
      shadow.shadowColor = .black
      shadow.shadowBlurRadius = 8
      shadow.shadowOffset = .zero
      titleTextField.shadow = shadow
    } else {
      titleTextField.shadow = nil
    }
  }

  private func updateMask() {
    guard let titlebarTrailingConstraint else { return }

    let constant = titlebarTrailingConstraint.constant
    let mask = CAGradientLayer()
    mask.frame = bounds

    mask.colors = [
      CGColor(gray: 0, alpha: 1),
      CGColor(gray: 0, alpha: 0),
    ]

    mask.locations = [0, 1]

    if isTransparant {
      mask.startPoint = CGPoint(x: 0, y: 1)
      mask.endPoint   = CGPoint(x: 0, y: 0)
    } else {
      let fadeStart = max(0, bounds.width - constant) / bounds.width
      let fadeEnd = max(0, bounds.width - constant + 100) / bounds.width

      let dy: CGFloat = constant == 0 ? 0 : (1 / bounds.width)
      mask.startPoint = CGPoint(x: fadeStart, y: 0.5 + dy)
      mask.endPoint   = CGPoint(x: fadeEnd, y: 0.5 - dy)
    }

    background.layer!.mask = mask
  }
}
