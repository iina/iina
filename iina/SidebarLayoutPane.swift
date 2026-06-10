//
//  SidebarLayoutPane.swift
//  iina
//
//  Created by Hechen Li on 2026-06-03.
//  Copyright © 2026 lhc. All rights reserved.
//


fileprivate extension LayoutValue {
  static let sidebarMargin = LayoutValue(18, 14)
  static let stackViewSpacing = LayoutValue(20, 16)
  static let containerPadding = LayoutValue(12, 10)
  static let stackViewSubListSpacing = LayoutValue(12, 8)
}


class SidebarLayoutPane: SidebarScrollView {
  let ui = UIHelper()
  weak var player: PlayerCore!

  private var videoSettingsStack: NSStackView!
  private var lockAspectSwitch: NSSwitch!
  private var lockWindowAspectStack: NSStackView!
  private var oscLayoutSelector: OSCLayoutSelector!
  private var removeBlackBarBtn: SideBarButton!

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    drawsBackground = false
    
    let stack = ui.vStack(spacing: .stackViewSpacing)

    stack.addArrangedSubview(ui.hStack(
      ui.image("rectangle.grid.3x2.fill", size: 20),
      ui.label("Compact Interface"),
      ui.flexibleSpace(),
      ui.toggleButton(bindTo: .compactUI, isSmall: true)
    ))

//    stack.addArrangedSubview(createSectionTitle("Video"))

    videoSettingsStack = ui.vStack(spacing: .stackViewSubListSpacing)

    videoSettingsStack.addArrangedSubview(ui.hStack(
      ui.image("custom.arrow.up.left.and.down.right.and.arrow.up.right.and.down.left.rectangle", size: 20),
      ui.label("Edge-to-Edge Video"),
      ui.flexibleSpace(),
      ui.toggleButton(bindTo: .edgeToEdgeVideo, isSmall: true)
    ))

    self.lockWindowAspectStack = ui.hStack(
      ui.image("lock.rectangle", size: 20),
      ui.label("Lock Window Aspect Ratio"),
      ui.flexibleSpace(),
      ui.toggleButton(bindTo: .unlockWindowAspectRatio, isSmall: true, inverted: true)
    )
    videoSettingsStack.addArrangedSubview(lockWindowAspectStack)

    self.removeBlackBarBtn = SideBarButton("Remove black bars", image: .removeBlackbars)
    removeBlackBarBtn.target = self
    removeBlackBarBtn.action = #selector(removeBlackBars)
    removeBlackBarBtn.size(height: 32)
    videoSettingsStack.addArrangedSubview(removeBlackBarBtn)
    removeBlackBarBtn.padding(.horizontal)

    updateVideoSettingsStack()

    stack.addArrangedSubview(Container(videoSettingsStack) {
      $0.padding(.horizontal(.containerPadding), .vertical(.containerPadding))
    })

    stack.addArrangedSubview(createOSCSettingsView())

    stack.addArrangedSubview(createSidebarSettingsView())

    UserDefaults.standard.addObserver(self, forKeyPath: Preference.Key.edgeToEdgeVideo.rawValue, options: .new, context: nil)
    UserDefaults.standard.addObserver(self, forKeyPath: Preference.Key.unlockWindowAspectRatio.rawValue, options: .new, context: nil)

    documentView = FlippedView()
    documentView!.translatesAutoresizingMaskIntoConstraints = false
    documentView!.padding(.top, .leading, .trailing, from: contentView)
    documentView!.addSubview(stack)
    stack.padding(.all(.sidebarMargin))
  }
  
  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func updateVideoSettingsStack() {
    if Preference.bool(for: .edgeToEdgeVideo) {
      videoSettingsStack.setVisibilityPriority(.mustHold, for: lockWindowAspectStack)
    } else {
      videoSettingsStack.setVisibilityPriority(.notVisible, for: lockWindowAspectStack)
    }
    // remove black bar button
    if Preference.unlockWindowAspectRatio {
      videoSettingsStack.setVisibilityPriority(.mustHold, for: removeBlackBarBtn)
    } else {
      videoSettingsStack.setVisibilityPriority(.notVisible, for: removeBlackBarBtn)
    }
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    updateVideoSettingsStack()
  }

  @objc private func removeBlackBars(_ sender: AnyObject) {
    player.mainWindow.removeVideoViewBlackBars()
  }

  private func createOSCSettingsView() -> NSView {
    let container = NSView()
    container.setContentHuggingPriority(.init(200), for: .horizontal)

    self.oscLayoutSelector = OSCLayoutSelector()

    let label = createSectionTitle("On Screen Controller")
    let stack = ui.hStack(oscLayoutSelector.views)


    container.addSubview(label)
    container.addSubview(stack)
    label.padding(.top, .leading, .trailing(greaterThan: 0))
    stack.padding(.bottom(8), .horizontal(greaterThan: 0)).center(.x)
      .spacing(.top(.stackViewSpacing), to: label)

    return container
  }

  private func createSectionTitle(_ text: String) -> NSView {
    func separator() -> NSBox {
      let box = NSBox()
      box.boxType = .separator
      box.size(height: 1)
      return box
    }

    let a = separator()
    let b = separator()

    let label = ui.hStack(
      a,
      ui.label(text, font: .boldSystemFont(ofSize: 12), isSecondary: true),
      b,
    )
    a.widthAnchor.constraint(equalTo: b.widthAnchor).isActive = true
    return label
  }

  private func createSidebarSettingsView() -> NSView {
    let container = NSView()
    container.setContentHuggingPriority(.init(200), for: .horizontal)

    let label = createSectionTitle("Sidebar Position")
    let config = [
      ("gearshape.fill", "Settings", Preference.Key.sidebarSettingsDisplayAtLeading),
      ("list.bullet.rectangle.fill", "Playlist and Chapters", Preference.Key.sidebarPlaylistDisplayAtLeading),
      ("puzzlepiece.extension.fill", "Plugins", Preference.Key.sidebarPluginsDisplayAtLeading),
    ]
    let stack = ui.vStack(
      spacing: .stackViewSubListSpacing,
      config.map { img, text, key in
        ui.hStack(
          ui.image(img),
          ui.label(text),
          ui.flexibleSpace(),
          SidebarPosSwitch(key),
        )
      }
    )

    container.addSubview(label)
    container.addSubview(stack)
    label.padding(.top, .leading, .trailing(greaterThan: 0))
    stack.padding(.bottom(8), .horizontal)
      .spacing(.top(.stackViewSpacing), to: label)

    return container
  }
}


fileprivate class SideBarButton: NSView {
  weak var target: AnyObject?
  var action: Selector?

  var isHighlighted = false {
    didSet {
      (layer as? CAGradientLayer)?.colors = [
        NSColor.gray.withAlphaComponent(isHighlighted ? 0.15 : 0.1).cgColor,
        NSColor.gray.withAlphaComponent(isHighlighted ? 0.2 : 0.15).cgColor
      ]
    }
  }

  init(_ text: String, image: NSImage? = nil) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    let background = CAGradientLayer()
    background.borderColor = NSColor.separatorColor.cgColor
    background.borderWidth = 1
    background.cornerRadius = 8
    background.colors = [
      NSColor.gray.withAlphaComponent(0.1).cgColor,
      NSColor.gray.withAlphaComponent(0.15).cgColor
    ]
    background.locations = [0, 1]
    background.startPoint = .zero
    background.endPoint = .init(x: 0, y: 1)
    layer = background

    let container = NSStackView()
    container.translatesAutoresizingMaskIntoConstraints = false
    container.orientation = .horizontal
    container.spacing = 8
    container.alignment = .firstBaseline
    if let image {
      let imageView = NSImageView(image: image)
      container.addArrangedSubview(imageView)
    }
    let label = NSTextField(labelWithString: text)
    container.addArrangedSubview(label)

    addSubview(container)
    container.center()
  }

  override func mouseDown(with event: NSEvent) {
    isHighlighted = true
  }

  override func mouseUp(with event: NSEvent) {
    isHighlighted = false
    let pt = convert(event.locationInWindow, from: nil)
    guard bounds.contains(pt), let target, let action else { return }
    NSApp.sendAction(action, to: target, from: self)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}


fileprivate class Container: NSBox {
  init(_ view: NSView, _ block: (NSView) -> Void) {
    super.init(frame: .zero)
    contentView = view
    translatesAutoresizingMaskIntoConstraints = false
    boxType = .custom
    borderColor = .separatorColor
    cornerRadius = 8
    fillColor = .gray.withAlphaComponent(0.1)
    block(view)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}


fileprivate class OSCLayoutSelector: NSBox {
  class Item: NSBox {
    let position: Preference.OSCPosition

    init(_ position: Preference.OSCPosition) {
      self.position = position
      super.init(frame: .zero)
      translatesAutoresizingMaskIntoConstraints = false
      boxType = .custom
      cornerRadius = 8
    }
    
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
    
    var isActive: Bool = false {
      didSet {
        animator().borderColor = isActive ? .controlAccentColor : .separatorColor
        animator().borderWidth = isActive ? 2 : 1
        animator().fillColor = isActive ? .controlAccentColor.withAlphaComponent(0.1) :
          .gray.withAlphaComponent(0.1)
      }
    }

    override func mouseDown(with event: NSEvent) {
      Preference.set(position.rawValue, for: .oscPosition)
    }
  }

  let ui = UIHelper()
  var views: [Item]!

  init() {
    super.init(frame: .zero)

    self.views = Preference.OSCPosition.allCases.map(createView)

    updateItems()
    UserDefaults.standard.addObserver(self, forKeyPath: Preference.Key.oscPosition.rawValue, options: .new, context: nil)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath, keyPath == Preference.Key.oscPosition.rawValue else { return }
    updateItems()
  }

  func updateItems() {
    guard let position = Preference.OSCPosition(key: .oscPosition) else { return }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.1
      views.forEach {
        $0.isActive = $0.position == position
      }
    }
  }

  private func createView(_ position: Preference.OSCPosition) -> Item {
    let content = ui.vStack(
      align: .centerX,
      ui.image("osc.\(position.description)", width: 40, height: 28),
      ui.label(NSLocalizedString("osc_pos.\(position.description)", comment: ""), isSmall: true)
    )
    content.distribution = .fillEqually
    let item = Item(position)
    item.contentView = content
    content.padding(.all(12))
    return item
  }
}


fileprivate class SidebarPosSwitch: NSSegmentedControl {
  private let key: Preference.Key

  init(_ key: Preference.Key) {
    self.key = key
    super.init(frame: .zero)

    segmentCount = 2
    setTag(0, forSegment: 0)
    setTag(1, forSegment: 1)
    setImage(.sf("sidebar.leading"), forSegment: 0)
    setImage(.sf("sidebar.trailing"), forSegment: 1)

    UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .initial, context: nil)
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard keyPath == key.rawValue else { return }
    selectSegment(withTag: Preference.bool(for: key) ? 0 : 1)
  }

  override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
    let isLeading = (selectedTag() == 0)
    Preference.set(isLeading, for: key)
    return true
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
