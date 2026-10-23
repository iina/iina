//
//  Titlebar.swift
//  iina
//
//  Created by Hechen Li on 2026-06-01.
//  Copyright © 2026 lhc. All rights reserved.
//

fileprivate let TitleBarHeightNormal: CGFloat = {
  if #available(macOS 26, *) {
    return 32
  }
  return 28
}()

fileprivate extension LayoutValue {
  static let titlebarHeight = LayoutValue(TitleBarHeightNormal + 8, TitleBarHeightNormal)
  static let oscBottomMargin = LayoutValue(10, 6)
}


class Titlebar: NSView {
  /// Default inset for the title container from the leading edge — clears the traffic lights.
  static let docIconLeadingPadding: CGFloat = 86

  private let accessoryIconConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)

  let useSystemTitle = false

  var isTransparent = false {
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

  private var headerHeightConstraint: NSLayoutConstraint!
  private var hasOSC = false
  private var inFullScreen = false
  private(set) var isRevealed = true
  private var backgroundPressOrigin: NSPoint?
  private var backgroundPressDidDrag = false
  private var backgroundClickTimer: Timer?

  private struct WindowButton {
    let button: NSButton
    weak var host: NSView?
    let frame: NSRect
  }
  private var windowButtons: [WindowButton] = []
  var tracksWindowButtons: Bool { !windowButtons.isEmpty }

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow

    let window = mainWindow.window!

    self.background = NSVisualEffectView()
    background.translatesAutoresizingMaskIntoConstraints = false

    self.titleBarBottomBorder = NSBox()
    titleBarBottomBorder.translatesAutoresizingMaskIntoConstraints = false

    self.onTopButton = NSButton(
      image: .sf("pin", withConfiguration: accessoryIconConfig)!,
      target: mainWindow,
      action: #selector(MainWindowController.ontopButtonAction)
    )

    self.removeBlackBarButton = NSButton(
      image: .sf("remove.blackbars", withConfiguration: accessoryIconConfig)!,
      target: mainWindow,
      action: #selector(MainWindowController.removeVideoViewBlackBars)
    )

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
    background.leftAnchor.constraint(greaterThanOrEqualTo: leftAnchor).isActive = true
    background.rightAnchor.constraint(lessThanOrEqualTo: rightAnchor).isActive = true

    titleBarBottomBorder.boxType = .separator
    addSubview(titleBarBottomBorder)
    titleBarBottomBorder.fillColor = .titleBarBorder
    titleBarBottomBorder.padding(.horizontal, .bottom).size(height: 1)

    onTopButton.size(height: 16)
    onTopButton.imageScaling = .scaleProportionallyDown
    onTopButton.translatesAutoresizingMaskIntoConstraints = false
    onTopButton.bezelStyle = .smallSquare
    onTopButton.isBordered = false
    updateOnTopIcon()

    removeBlackBarButton.size(height: 16)
    removeBlackBarButton.imageScaling = .scaleProportionallyDown
    removeBlackBarButton.translatesAutoresizingMaskIntoConstraints = false
    removeBlackBarButton.bezelStyle = .smallSquare
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
      // Flexible title text must not raise the native window minimum.
      container.setContentCompressionResistancePriority(.init(1), for: .horizontal)
      container.setContentHuggingPriority(.init(1), for: .horizontal)
      container.padding(.bottom, .leading)
      topConstraint = container.topAnchor.constraint(equalTo: topAnchor)
      topConstraint.isActive = true

      self.trailingConstraint = trailingAnchor
        .constraint(equalTo: container.trailingAnchor)
      trailingConstraint.isActive = true
      container.leftAnchor.constraint(greaterThanOrEqualTo: leftAnchor).isActive = true
      container.rightAnchor.constraint(lessThanOrEqualTo: rightAnchor).isActive = true

      // title bar

      self.titlebarContainer = NSView()
      titlebarContainer.translatesAutoresizingMaskIntoConstraints = false
      container.addArrangedSubview(titlebarContainer)
      titlebarContainer.padding(.horizontal)
      titleHeightConstraint = titlebarContainer.heightAnchor.constraint(equalToConstant: 0)
      LayoutValue.titlebarHeight.use { [weak self] value in
        self?.titleHeightConstraint.constant = value
        self?.updateHeaderGeometry()
      }
      titleHeightConstraint.isActive = true

      self.docIcon = NSImageView()
      docIcon.translatesAutoresizingMaskIntoConstraints = false
      titlebarContainer.addSubview(docIcon)
      docIcon.padding(.leading(greaterThan: Titlebar.docIconLeadingPadding))
        .center(.y).size(width: 16, height: 16)

      self.titleTextField = NSTextField(labelWithString: window.title)
      titleTextField.translatesAutoresizingMaskIntoConstraints = false
      titleTextField.font = .titleBarFont(ofSize: 13)
      titleTextField.lineBreakMode = .byTruncatingMiddle
      titleTextField.setContentCompressionResistancePriority(.init(1), for: .horizontal)
      titleTextField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
      titlebarContainer.addSubview(titleTextField)
      titleTextField.spacing(.leading(2), to: docIcon).center(.y)

      if #available(macOS 26.0, *) {
        self.titleLeadingConstraint = docIcon.leadingAnchor
          .constraint(equalTo: titlebarContainer.leadingAnchor, constant: Titlebar.docIconLeadingPadding)
      } else {
        // on macOS 15 or below, titlebar is centered
        self.titleLeadingConstraint = docIcon.leadingAnchor
          .constraint(greaterThanOrEqualTo: titlebarContainer.leadingAnchor, constant: Titlebar.docIconLeadingPadding)
        let centerConstraint = titleTextField.centerXAnchor.constraint(equalTo: titlebarContainer.centerXAnchor)
        centerConstraint.priority = .defaultLow
        centerConstraint.isActive = true
        titleTextField.setContentCompressionResistancePriority(.init(1), for: .horizontal)
      }
      titleLeadingConstraint.priority = .defaultHigh
      titleLeadingConstraint.isActive = true

      let accessoryView = NSStackView(views: [removeBlackBarButton, onTopButton])
      accessoryView.translatesAutoresizingMaskIntoConstraints = false
      accessoryView.orientation = .horizontal
      accessoryView.spacing = 8

      titlebarContainer.addSubview(accessoryView)
      accessoryView.padding(.trailing(8)).center(.y)
      titleTextField.spacing(.trailing(greaterThan: 8), to: accessoryView)

      // osc

      self.oscContainer = NSView()
      oscContainer.translatesAutoresizingMaskIntoConstraints = false
      container.addArrangedSubview(oscContainer)
      self.oscView = TimeLabelOverflowedStackView()
      oscView.translatesAutoresizingMaskIntoConstraints = false
      oscContainer.addSubview(oscView)
      oscView.padding(.trailing(6), .top, .bottom(.oscBottomMargin)).size(height: 24)

      oscLeadingConstraint = oscView.leadingAnchor
        .constraint(equalTo: oscContainer.leadingAnchor, constant: 6)
      oscLeadingConstraint.isActive = true
      // Physical bounds let the docked stack detach groups before overflowing.
      oscView.leftAnchor.constraint(greaterThanOrEqualTo: oscContainer.leftAnchor).isActive = true
      oscView.rightAnchor.constraint(lessThanOrEqualTo: oscContainer.rightAnchor).isActive = true
    }

    headerHeightConstraint = heightAnchor.constraint(equalToConstant: LayoutValue.titlebarHeight.get())
    headerHeightConstraint.isActive = true
    LayoutValue.oscBottomMargin.use { [weak self] _ in self?.updateHeaderGeometry() }
    updateShadow()
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func updateHeaderGeometry() {
    guard headerHeightConstraint != nil else { return }
    let titleHeight = inFullScreen && hasOSC ? 0 : LayoutValue.titlebarHeight.get()
    headerHeightConstraint.constant = titleHeight + (hasOSC ? 24 + LayoutValue.oscBottomMargin.get() : 0)
      + (inFullScreen ? 8 : 0)
    if let superview, verticalConstraint == nil {
      verticalConstraint = topAnchor.constraint(equalTo: superview.topAnchor)
      verticalConstraint.isActive = true
    }
    verticalConstraint?.constant = isRevealed ? 0 : -headerHeightConstraint.constant
    positionWindowButtons(animated: false)
    mainWindow.sidebars.updateHeaderInset(isRevealed ? headerHeightConstraint.constant : 0, animated: false)
  }

  func setRevealed(_ revealed: Bool, animated: Bool) {
    if !revealed { cancelBackgroundPress() }
    let changed = revealed != isRevealed
    isRevealed = revealed
    if revealed { isHidden = false }
    let reduceMotion = AccessibilityPreferences.motionReductionEnabled
    let offset: CGFloat = revealed || reduceMotion ? 0 : -headerHeightConstraint.constant
    if animated && changed {
      if reduceMotion {
        verticalConstraint?.constant = 0
        animator().alphaValue = revealed ? 1 : 0
      } else {
        alphaValue = 1
        verticalConstraint?.animator().constant = offset
      }
    } else if !animated {
      verticalConstraint?.constant = offset
      alphaValue = 1
      isHidden = !revealed
    }
    if changed || !animated {
      if !animated { windowButtons.forEach { $0.button.layer?.removeAnimation(forKey: "headerSlide") } }
      positionWindowButtons(animated: animated)
      mainWindow.sidebars.updateHeaderInset(revealed ? headerHeightConstraint.constant : 0,
                                           animated: animated && !reduceMotion)
    }
  }

  func update(hasOSC: Bool, inFullScreen: Bool) {
    self.hasOSC = hasOSC
    self.inFullScreen = inFullScreen
    if inFullScreen { restoreWindowButtons() }
    topConstraint.constant = inFullScreen ? 8 : 0
    container.setVisibilityPriority(inFullScreen && hasOSC ? .notVisible : .mustHold, for: titlebarContainer)
    container.setVisibilityPriority(hasOSC ? .mustHold : .notVisible, for: oscContainer)
    window?.titleVisibility = inFullScreen ? .visible : .hidden
    updateHeaderGeometry()
    if inFullScreen && !hasOSC { setRevealed(false, animated: false) }
  }

  // Native buttons retain their AppKit hosts and actions.
  func trackWindowButtons() {
    guard !inFullScreen, let window else { return }
    let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
      .compactMap { window.standardWindowButton($0) }
    if windowButtons.map({ $0.button }) != buttons {
      restoreWindowButtons()
      windowButtons = buttons.map { WindowButton(button: $0, host: $0.superview, frame: $0.frame) }
    }
    positionWindowButtons(animated: false)
  }

  private func positionWindowButtons(animated: Bool) {
    for item in windowButtons {
      guard let host = item.host, item.button.superview === host else { continue }
      if item.button.frame.origin != item.frame.origin { item.button.setFrameOrigin(item.frame.origin) }
      if !item.button.wantsLayer { item.button.wantsLayer = true }
      guard let layer = item.button.layer else { continue }
      let reduceMotion = AccessibilityPreferences.motionReductionEnabled
      let offset: CGFloat = isRevealed || reduceMotion ? 0 : headerHeightConstraint.constant
      let transform = CATransform3DMakeTranslation(0, host.isFlipped ? -offset : offset, 0)
      // A window resize usually leaves these transforms unchanged. Avoid
      // publishing three extra transactions (and reading presentation copies)
      // on every crop tick; a real header slide still starts where it is shown.
      let previous = animated && !reduceMotion ? layer.presentation()?.transform ?? layer.transform : layer.transform
      if !CATransform3DEqualToTransform(layer.transform, transform) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = transform
        CATransaction.commit()
      }
      if animated && !reduceMotion {
        let slide = CABasicAnimation(keyPath: "transform")
        slide.fromValue = NSValue(caTransform3D: previous)
        slide.toValue = NSValue(caTransform3D: transform)
        slide.duration = NSAnimationContext.current.duration
        slide.timingFunction = NSAnimationContext.current.timingFunction
        layer.add(slide, forKey: "headerSlide")
        item.button.alphaValue = 1
      } else if animated && reduceMotion {
        layer.removeAnimation(forKey: "headerSlide")
        item.button.animator().alphaValue = isRevealed ? 1 : 1e-100
      } else {
        let opacity: CGFloat = isRevealed ? 1 : 1e-100
        if item.button.alphaValue != opacity { item.button.alphaValue = opacity }
      }
    }
  }

  func finishShowing() {
    guard isRevealed else { return }
    positionWindowButtons(animated: false)
  }

  // Keep native widgets registered with AppKit while hidden.
  func finishHiding() {
    windowButtons.forEach { $0.button.alphaValue = 1e-100 }
  }

  func restoreWindowButtons() {
    for item in windowButtons {
      item.button.layer?.removeAnimation(forKey: "headerSlide")
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      item.button.layer?.transform = CATransform3DIdentity
      CATransaction.commit()
      if item.button.superview === item.host { item.button.frame = item.frame }
      item.button.alphaValue = 1
    }
    windowButtons.removeAll()
  }

  func updateOnTopIcon() {
    let isOntop = mainWindow.isOntop
    onTopButton.isHidden = Preference.bool(for: .alwaysShowOnTopIcon) ? false : !isOntop
    onTopButton.image = isOntop ?
      .sf("pin.fill", withConfiguration: accessoryIconConfig) :
      .sf("pin", withConfiguration: accessoryIconConfig)
  }

  func updateRemoveBlackBarButton() {
    let shouldShow = Preference.unlockWindowAspectRatio
    removeBlackBarButton.isHidden = !shouldShow
  }

  func updateTitle() {
    guard let titleTextField,
          let docIcon,
          let window = mainWindow.window else { return }

    let info = mainWindow.player.info
    titleTextField.stringValue = if info.isNetworkResource {
      mainWindow.player.getMediaTitle()
    } else if let url = info.currentURL {
      FileManager.default.displayName(atPath: url.path)
    } else {
      ""
    }

    let filename = window.representedFilename
    docIcon.image = filename.isEmpty ? nil : NSWorkspace.shared.icon(forFile: filename)
  }

  override func rightMouseDown(with event: NSEvent) {
    // docIcon/titleTextField are children of titlebarContainer, so their frames are in the
    // container's coordinate space — not the titlebar's. Convert the click into the container
    // before hit-testing.
    let point = titlebarContainer.convert(event.locationInWindow, from: nil)

    if docIcon.frame.contains(point) || titleTextField.frame.contains(point) {
      showPathMenu()
    }
  }

  override func mouseDown(with event: NSEvent) {
    let point = titlebarContainer.convert(event.locationInWindow, from: nil)

    if docIcon.frame.contains(point) && event.modifierFlags.contains(.command) {
      showPathMenu()
    }
  }

  override func rightMouseUp(with event: NSEvent) {}

  private func cancelBackgroundPress() {
    backgroundPressOrigin = nil
    backgroundPressDidDrag = false
  }

  /// Observe without consuming AppKit's drag or double-click events.
  @discardableResult
  func handleBackgroundMouseEvent(_ event: NSEvent) -> Bool {
    switch event.type {
    case .leftMouseDown:
      backgroundClickTimer?.invalidate()
      backgroundClickTimer = nil
      cancelBackgroundPress()
      guard event.clickCount == 1, !event.modifierFlags.contains(.control),
            isBackgroundEvent(event) else { return false }
      backgroundPressOrigin = event.locationInWindow
    case .leftMouseDragged:
      guard let origin = backgroundPressOrigin else { return false }
      if hypot(event.locationInWindow.x - origin.x, event.locationInWindow.y - origin.y) > 3 {
        backgroundPressDidDrag = true
      }
    case .leftMouseUp:
      guard let origin = backgroundPressOrigin else { return false }
      defer { cancelBackgroundPress() }
      guard event.clickCount == 1, !backgroundPressDidDrag,
            hypot(event.locationInWindow.x - origin.x, event.locationInWindow.y - origin.y) <= 3,
            isBackgroundEvent(event), window?.isVisible == true else { return false }
      backgroundClickTimer = Timer.scheduledTimer(withTimeInterval: NSEvent.doubleClickInterval,
                                                  repeats: false) { [weak self] _ in
        guard let self else { return }
        backgroundClickTimer = nil
        guard window?.isVisible == true, isRevealed, !isHidden,
              !mainWindow.interactiveMode.isActive else { return }
        mainWindow.hideUIFromOSC()
      }
    case .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown:
      backgroundClickTimer?.invalidate()
      backgroundClickTimer = nil
      cancelBackgroundPress()
    default:
      break
    }
    return false
  }

  private func isTitlePathEvent(_ event: NSEvent) -> Bool {
    let point = titlebarContainer.convert(event.locationInWindow, from: nil)
    return docIcon.frame.contains(point) || titleTextField.frame.contains(point)
  }

  private func isBackgroundEvent(_ event: NSEvent) -> Bool {
    guard isRevealed, !isHidden, !mainWindow.interactiveMode.isActive,
          let parent = superview,
          let hit = parent.hitTest(parent.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow),
          hit.isDescendant(of: self) else { return false }
    return SidebarController.isBackgroundHit(hit, in: self, at: event.locationInWindow)
  }

  private func showPathMenu() {
    guard let filename = mainWindow.window?.representedFilename else { return }

    let menu = NSMenu()
    menu.autoenablesItems = false

    let url = URL(fileURLWithPath: filename)
    let point = NSPoint(x: -30, y: 0)  // make sure the first menu item is at the title's position

    var current = url.standardizedFileURL
    var components: [URL] = []

    while true {
      components.append(current)
      let parent = current.deletingLastPathComponent()
      if parent.path == "/" { break }  // reached root
      current = parent
    }

    for (index, pathURL) in components.enumerated() {
      let item = NSMenuItem()
      item.title = FileManager.default.displayName(atPath: pathURL.path)
      item.image = NSWorkspace.shared.icon(forFile: pathURL.path)
      item.image?.size = NSSize(width: 16, height: 16)
      if #available(macOS 27.0, *) {
        item.preferredImageVisibility = .visible
      }
      // Choosing a folder reveals the next path component in it; the document itself does nothing.
      if index > 0 {
        item.representedObject = components[index - 1]
        item.target = self
        item.action = #selector(revealInFinder(_:))
      }
      menu.addItem(item)
    }

    menu.popUp(positioning: nil, at: point, in: titleTextField)
  }

  @objc private func revealInFinder(_ sender: NSMenuItem) {
    guard let url = sender.representedObject as? URL else { return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  private func updateShadow() {
    if isTransparent {
      let shadow = NSShadow()
      shadow.shadowColor = .black
      shadow.shadowBlurRadius = 8
      shadow.shadowOffset = .zero
      titleTextField.shadow = shadow
    } else {
      titleTextField.shadow = nil
    }
  }
}
