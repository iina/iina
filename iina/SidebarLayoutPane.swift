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
  static let videoSettingsSpacing = LayoutValue(12, 8)
  static let sidebarSettingsSpacing = LayoutValue(10, 6)
  static let liquidGlassSettingsSpacing = LayoutValue(6, 5)
}


class SidebarLayoutPane: SidebarScrollView {
  let ui = UIHelper()
  let prefObserver = Preference.Observer()
  weak var player: PlayerCore!

  private var videoSettingsStack: NSStackView!
  private var themeSettingStack: NSStackView!
  private var lockAspectSwitch: NSSwitch!
  private var lockWindowAspectStack: NSStackView!
  private var dockedUIStack: NSStackView!
  private var oscLayoutSelector: OSCLayoutSelector!
  private var removeBlackBarBtn: SideBarButton!

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    drawsBackground = false
    
    let stack = ui.vStack(spacing: .stackViewSpacing)

    themeSettingStack = ui.vStack(
      spacing: .videoSettingsSpacing,
      ui.hStack(
        ui.image("lightspectrum.horizontal", size: 20),
        ui.label("Theme"),
        ui.flexibleSpace(),
        ThemeSwitch(.themeMaterial),
      )
    )

    if #available(macOS 26.0, *) {
      themeSettingStack.addArrangedSubview(ui.vStack(
        spacing: .videoSettingsSpacing,
        ui.hStack(
          ui.image("liquid.glass", size: 20),
          ui.label("Liquid Glass"),
          ui.flexibleSpace(),
        ),
        ui.vStack(
          spacing: .liquidGlassSettingsSpacing,
          ui.hStack(
            ui.space(),
            ui.image("osd", size: 16),
            ui.label("On Screen Display", isSmall: true),
            ui.flexibleSpace(),
            ui.toggleButton(bindTo: .useLiquidGlassOSD, size: .mini)
          ),
          ui.hStack(
            ui.space(),
            ui.image("osc.floating", size: 16),
            ui.label("On Screen Controller", isSmall: true),
            ui.flexibleSpace(),
            ui.toggleButton(bindTo: .useLiquidGlassOSC, size: .mini)
          ),
          ui.hStack(
            ui.space(),
            ui.image("sidebar.squares.trailing", size: 16),
            ui.label("Sidebar", isSmall: true),
            ui.flexibleSpace(),
            ui.toggleButton(bindTo: .useLiquidGlassSidebar, size: .mini)
          ),
        )
      ))
    }

    stack.addArrangedSubview(Container(themeSettingStack) {
      $0.padding(.all(.containerPadding))
    })

    stack.addArrangedSubview(Container(ui.hStack(
      ui.image("rectangle.grid.3x2.fill", size: 20),
      ui.label("Compact Interface"),
      ui.flexibleSpace(),
      ui.toggleButton(bindTo: .compactUI, size: .small)
    )) {
      $0.padding(.all(.containerPadding))
    })

//    stack.addArrangedSubview(createSectionTitle("Video"))

    videoSettingsStack = ui.vStack(spacing: .videoSettingsSpacing)

    videoSettingsStack.addArrangedSubview(ui.hStack(
      ui.image("custom.arrow.up.left.and.down.right.and.arrow.up.right.and.down.left.rectangle", size: 20),
      ui.label("Edge-to-Edge Video"),
      ui.flexibleSpace(),
      ui.toggleButton(bindTo: .edgeToEdgeVideo, size: .small)
    ))

    self.lockWindowAspectStack = ui.hStack(
      ui.image("lock.rectangle", size: 20),
      ui.label("Lock Window Aspect Ratio"),
      ui.flexibleSpace(),
      ui.toggleButton(bindTo: .unlockWindowAspectRatio, size: .small, inverted: true)
    )
    videoSettingsStack.addArrangedSubview(lockWindowAspectStack)

    self.dockedUIStack = ui.hStack(
      ui.image("dock.arrow.down.rectangle", size: 20),
      ui.label("Docked Control Bar and Titlebar"),
      ui.flexibleSpace(),
      ui.toggleButton(bindTo: .dockedControlBarAndTitlebar, size: .small)
    )
    videoSettingsStack.addArrangedSubview(dockedUIStack)

    self.removeBlackBarBtn = SideBarButton("Remove black bars", image: .removeBlackbars)
    removeBlackBarBtn.target = self
    removeBlackBarBtn.action = #selector(removeBlackBars)
    removeBlackBarBtn.size(height: 32)
    videoSettingsStack.addArrangedSubview(removeBlackBarBtn)
    removeBlackBarBtn.padding(.horizontal)

    updateVideoSettingsStack()

    stack.addArrangedSubview(Container(videoSettingsStack) {
      $0.padding(.all(.containerPadding))
    })

    stack.addArrangedSubview(createOSCSettingsView())

    stack.addArrangedSubview(createSidebarSettingsView())

    prefObserver.addAll(
      .edgeToEdgeVideo,
      .unlockWindowAspectRatio,
      .dockedControlBarAndTitlebar,
    ) { [unowned self] _ in
      updateVideoSettingsStack()
    }

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
      videoSettingsStack.setVisibilityPriority(.notVisible, for: dockedUIStack)
    } else {
      videoSettingsStack.setVisibilityPriority(.notVisible, for: lockWindowAspectStack)
      videoSettingsStack.setVisibilityPriority(.mustHold, for: dockedUIStack)
    }
    // remove black bar button
    if Preference.unlockWindowAspectRatio {
      videoSettingsStack.setVisibilityPriority(.mustHold, for: removeBlackBarBtn)
    } else {
      videoSettingsStack.setVisibilityPriority(.notVisible, for: removeBlackBarBtn)
    }
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
      spacing: .sidebarSettingsSpacing,
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
  private let prefObserver = Preference.Observer()

  init() {
    super.init(frame: .zero)

    self.views = Preference.OSCPosition.allCases.map(createView)

    prefObserver.add(.oscPosition, block: { [unowned self] _ in updateItems() }, runNow: true)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
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


fileprivate class ThemeSwitch: NSSegmentedControl {
  private let key: Preference.Key
  let prefObserver = Preference.Observer()

  init(_ key: Preference.Key) {
    self.key = key
    super.init(frame: .zero)

    segmentCount = 3
    setTag(0, forSegment: 0)
    setTag(2, forSegment: 1)
    setTag(4, forSegment: 2)
    setImage(.sf("moonphase.full.moon"), forSegment: 0)
    setLabel("Dark", forSegment: 0)
    setImage(.sf("moonphase.new.moon"), forSegment: 1)
    setLabel("Light", forSegment: 1)
    setImage(.sf("moonphase.first.quarter"), forSegment: 2)
    setLabel("Auto", forSegment: 2)

    prefObserver.add(key, block: { [unowned self] _ in
      selectSegment(withTag: Preference.integer(for: key))
    }, runNow: true)
  }

  override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
    Preference.set(selectedTag(), for: key)
    return true
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}


fileprivate class SidebarPosSwitch: NSSegmentedControl {
  private let key: Preference.Key
  let prefObserver = Preference.Observer()

  init(_ key: Preference.Key) {
    self.key = key
    super.init(frame: .zero)

    segmentCount = 2
    setTag(0, forSegment: 0)
    setTag(1, forSegment: 1)
    setImage(.sf("sidebar.leading"), forSegment: 0)
    setImage(.sf("sidebar.trailing"), forSegment: 1)

    prefObserver.add(key, block: { [unowned self] _ in
      selectSegment(withTag: Preference.bool(for: key) ? 0 : 1)
    }, runNow: true)
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
