//
//  Titlebar.swift
//  iina
//
//  Created by Hechen Li on 2026-06-01.
//  Copyright © 2026 lhc. All rights reserved.
//

fileprivate let TitleBarHeightNormal: CGFloat = {
  if #available(macOS 26, *) {
    return 34
  }
  return 28
}()

fileprivate extension LayoutValue {
  static let titlebarHeight = LayoutValue(TitleBarHeightNormal + 6, TitleBarHeightNormal)
  static let oscBottomMargin = LayoutValue(10, 6)
}


class Titlebar: NSView {
  /// Default inset for the title container from the leading edge — clears the traffic lights.
  static let docIconLeadingPadding: CGFloat = 82

  let useSystemTitle = false

  var isTransparant = false {
    didSet {
      updateShadow()
    }
  }

  weak var mainWindow: MainWindowController!

  private var background: NSVisualEffectView
  private var titleBarBottomBorder: NSBox
  private var backgroundLeadingConstraint: NSLayoutConstraint!
  private var backgroundTrailingConstraint: NSLayoutConstraint!

  private var onTopButton: NSButton
  private var removeBlackBarButton: NSButton

  private var container: NSStackView!
  private var titlebarContainer: NSView!
  private var titleHeightConstraint: NSLayoutConstraint!
  private var titleLeadingConstraint: NSLayoutConstraint!
  private var trailingConstraint: NSLayoutConstraint!
  private var topConstraint: NSLayoutConstraint!
  private var verticalConstraint: NSLayoutConstraint!
  private var titleTextField: NSTextField!
  private var docIcon: NSImageView!

  var oscView: TimeLabelOverflowedStackView!
  private var oscContainer: NSView!
  private var oscLeadingConstraint: NSLayoutConstraint!

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow

    let window = mainWindow.window!

    self.background = NSVisualEffectView()
    background.translatesAutoresizingMaskIntoConstraints = false

    self.titleBarBottomBorder = NSBox()
    titleBarBottomBorder.translatesAutoresizingMaskIntoConstraints = false

    self.onTopButton = NSButton(
      image: .sf("pin")!,
      target: mainWindow,
      action: #selector(MainWindowController.ontopButtonAction)
    )
    onTopButton.translatesAutoresizingMaskIntoConstraints = false

    self.removeBlackBarButton = NSButton(
      image: .removeBlackbars,
      target: mainWindow,
      action: #selector(MainWindowController.removeVideoViewBlackBars)
    )
    removeBlackBarButton.translatesAutoresizingMaskIntoConstraints = false

    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false

    background.blendingMode = .withinWindow
    background.material = .titlebar
    background.wantsLayer = true
    background.layerContentsRedrawPolicy = .onSetNeedsDisplay
    background.state = .active
    addSubview(background)
    background.padding(.top, .bottom(1))
    backgroundLeadingConstraint = background.leadingAnchor.constraint(equalTo: leadingAnchor)
    backgroundLeadingConstraint.isActive = true
    backgroundTrailingConstraint = trailingAnchor.constraint(equalTo: background.trailingAnchor)
    backgroundTrailingConstraint.isActive = true

    titleBarBottomBorder.boxType = .separator
    addSubview(titleBarBottomBorder)
    titleBarBottomBorder.fillColor = .titleBarBorder
    titleBarBottomBorder.padding(.horizontal, .bottom).size(height: 1)

    onTopButton.frame.size.width = 30
    onTopButton.isBordered = false
    updateOnTopIcon()

    removeBlackBarButton.frame.size.width = 30
    removeBlackBarButton.isBordered = false
    updateRemoveBlackBarButton()

    if useSystemTitle {
      let titlebarAccessoryViewController = NSTitlebarAccessoryViewController()
      titlebarAccessoryViewController.view = onTopButton
      titlebarAccessoryViewController.layoutAttribute = .right
      mainWindow.window!.addTitlebarAccessoryViewController(titlebarAccessoryViewController)
    } else {
      window.titleVisibility = .hidden

      //
      // titlebarContainer [-(leading)-[docIcon]-[titleTextField]] \                       |
      //                   --------------------------------------  | container -(trailing)-|
      //      oscContainer [-(leading)-[         oscView        ]] /                       |
      //
      self.container = NSStackView()
      container.translatesAutoresizingMaskIntoConstraints = false
      addSubview(container)
      container.orientation = .vertical
      container.alignment = .centerX
      container.spacing = 0
      container.padding(.bottom, .leading)
      topConstraint = container.topAnchor.constraint(equalTo: topAnchor)
      topConstraint.isActive = true

      self.trailingConstraint = trailingAnchor
        .constraint(equalTo: container.trailingAnchor)
      trailingConstraint.isActive = true

      // title bar

      self.titlebarContainer = NSView()
      titlebarContainer.translatesAutoresizingMaskIntoConstraints = false
      container.addArrangedSubview(titlebarContainer)
      titleHeightConstraint = titlebarContainer.heightAnchor.constraint(equalToConstant: 0)
      LayoutValue.titlebarHeight.use { [weak self] value in
        self?.titleHeightConstraint.constant = value
      }
      titleHeightConstraint.isActive = true

      self.docIcon = NSImageView()
      docIcon.translatesAutoresizingMaskIntoConstraints = false
      titlebarContainer.addSubview(docIcon)
      docIcon.padding(.leading(greaterThan: Titlebar.docIconLeadingPadding))
        .center(.y).size(width: 16, height: 16)

      self.titleLeadingConstraint = docIcon.leadingAnchor
        .constraint(equalTo: titlebarContainer.leadingAnchor, constant: Titlebar.docIconLeadingPadding)
      titleLeadingConstraint.priority = .defaultHigh
      titleLeadingConstraint.isActive = true

      self.titleTextField = NSTextField(labelWithString: window.title)
      titleTextField.translatesAutoresizingMaskIntoConstraints = false
      titleTextField.font = .titleBarFont(ofSize: 13)
      titleTextField.lineBreakMode = .byTruncatingMiddle
      titleTextField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      titlebarContainer.addSubview(titleTextField)
      titleTextField.spacing(.leading(2), to: docIcon).center(.y)

      let accessoryView = NSStackView(views: [removeBlackBarButton, onTopButton])
      accessoryView.translatesAutoresizingMaskIntoConstraints = false
      accessoryView.orientation = .horizontal
      accessoryView.spacing = 8

      titlebarContainer.addSubview(accessoryView)
      accessoryView.padding(.trailing(8)).center(.y)
      titleTextField.spacing(.trailing(greaterThan: 8), to: accessoryView)

      // osc

      self.oscContainer = TitlebarInnerView(titlebar: self)
      oscContainer.translatesAutoresizingMaskIntoConstraints = false
      container.addArrangedSubview(oscContainer)
      self.oscView = TimeLabelOverflowedStackView()
      oscView.translatesAutoresizingMaskIntoConstraints = false
      oscContainer.addSubview(oscView)
      oscView.padding(.trailing(6), .top, .bottom(.oscBottomMargin)).size(height: 24)

      oscLeadingConstraint = oscView.leadingAnchor
        .constraint(equalTo: oscContainer.leadingAnchor, constant: 6)
      oscLeadingConstraint.isActive = true
    }

    updateShadow()
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func updateVerticalConstraint(isDisplaying: Bool) {
    guard let superview else { return }
    if let verticalConstraint {
      superview.removeConstraint(verticalConstraint)
    }
    if isDisplaying {
      verticalConstraint = topAnchor.constraint(equalTo: superview.topAnchor)
    } else {
      verticalConstraint = bottomAnchor.constraint(equalTo: superview.topAnchor)
    }
    verticalConstraint.isActive = true
  }

  func update(hasOSC: Bool, inFullScreen: Bool) {
    // when in full screen, the OSC should have a top padding
    topConstraint.constant = inFullScreen ? 8 : 0
    // show/hide title or OSC
    container.setVisibilityPriority(.mustHold, for: titlebarContainer)
    if hasOSC {
      container.setVisibilityPriority(.mustHold, for: oscContainer)
      if inFullScreen {
        container.setVisibilityPriority(.notVisible, for: titlebarContainer)
      }
    } else {
      container.setVisibilityPriority(.notVisible, for: oscContainer)
    }
    // show systsem titlebar when in fullscreen
    if !useSystemTitle {
      window?.titleVisibility = inFullScreen ? .visible : .hidden
    }
    // update vertical constraint
    updateVerticalConstraint(isDisplaying: !inFullScreen || hasOSC)
  }

  func updateOnTopIcon() {
    let isOntop = mainWindow.isOntop
    onTopButton.isHidden = Preference.bool(for: .alwaysShowOnTopIcon) ? false : !isOntop
    onTopButton.image = isOntop ? .sf("pin.fill") : .sf("pin")
  }

  func updateRemoveBlackBarButton() {
    let shouldShow = Preference.unlockWindowAspectRatio
    removeBlackBarButton.isHidden = !shouldShow
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

  func setLeadingConstraint(_ constant: CGFloat, animated: Bool = true) {
    if animated {
      titleLeadingConstraint.animator().constant = constant == 0 ? 0 : constant + 8
      oscLeadingConstraint.animator().constant = constant + 6
      backgroundLeadingConstraint.animator().constant = constant
    } else {
      titleLeadingConstraint.constant = constant == 0 ? 0 : constant + 8
      oscLeadingConstraint.constant = constant + 6
      backgroundLeadingConstraint.constant = constant
    }
  }

  func setTrailingConstraint(_ constant: CGFloat, animated: Bool = true) {
    if animated {
      trailingConstraint.animator().constant = constant
      backgroundTrailingConstraint.animator().constant = constant
    } else {
      trailingConstraint.constant = constant
      backgroundTrailingConstraint.constant = constant
    }
  }

  override func rightMouseDown(with event: NSEvent) {
    // docIcon/titleTextField are children of titlebarContainer, so their frames are in the
    // container's coordinate space — not the titlebar's. Convert the click into the container
    // before hit-testing.
    let point = titlebarContainer.convert(event.locationInWindow, from: nil)

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
    let point = NSPoint(x: -30, y: 0)  // make sure the first menu item is at the title's positon

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

    menu.popUp(positioning: nil, at: point, in: titleTextField)
  }

  @objc private func revealInFinder(_ sender: NSMenuItem) {
    guard let url = sender.representedObject as? URL else { return }
    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
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

  /// Inner edge (toward the video center) of the sidebar on the given side, in titlebar coords.
  /// Returns `0` for a hidden left sidebar and `w` for a hidden right sidebar so the lead/trail
  /// fade bands collapse to the bar edges.
  private func sidebarInnerEdge(for side: SidebarController.Side, in w: CGFloat) -> CGFloat {
    let panel = mainWindow.sidebars.sideBar(for: side)
    guard !panel.view.isHidden else {
      return side == .leading ? 0 : w
    }
    return side == .leading ? max(0, panel.view.frame.maxX) : min(w, panel.view.frame.minX)
  }
}


/// Calls titlebar's updateLayer() to make sure the mask is redrawn during the animation.
fileprivate class TitlebarInnerView: NSView {
  weak var titlebar: Titlebar!

  init(titlebar: Titlebar) {
    self.titlebar = titlebar
    super.init(frame: .zero)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func layout() {
    super.layout()
    titlebar.needsDisplay = true
  }
}
