//
//  SidebarLayoutPane.swift
//  iina
//
//  Created by Hechen Li on 2026-06-03.
//  Copyright © 2026 lhc. All rights reserved.
//


fileprivate extension LayoutValue {
  static let sidebarMargin = LayoutValue(18, 12)
  static let stackViewSpacing = LayoutValue(16, 10)
}


class SidebarLayoutPane: SidebarScrollView {
  let ui = UIHelper()
  weak var player: PlayerCore!

  private var lockAspectSwitch: NSSwitch!
  private var oscLayoutSelector: OSCLayoutSelector!

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

    stack.addArrangedSubview(ui.hStack(
      ui.image("lock.rectangle", size: 20),
      ui.label("Lock Window Aspect Ratio"),
      ui.flexibleSpace(),
      createLockAspectSwitch()
    ))

    stack.addArrangedSubview(createOSCSettingsView())

    stack.addArrangedSubview(ui.hStack(
      ui.image("custom.arrow.up.left.and.down.right.and.arrow.up.right.and.down.left.rectangle", size: 20),
      ui.label("Edge-to-Edge Video"),
      ui.flexibleSpace(),
      ui.toggleButton(bindTo: .edgeToEdgeVideo, isSmall: true)
    ))

    documentView = FlippedView()
    documentView!.translatesAutoresizingMaskIntoConstraints = false
    documentView!.padding(.top, .leading, .trailing, from: contentView)
    documentView!.addSubview(stack)
    stack.padding(.all(.sidebarMargin))
  }
  
  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    updateAspectSwitch()
  }

  private func createLockAspectSwitch() -> NSSwitch {
    self.lockAspectSwitch = NSSwitch()
    lockAspectSwitch.controlSize = .small
    lockAspectSwitch.target = self
    lockAspectSwitch.action = #selector(lockAspectSwitchAction(_:))
    UserDefaults.standard.addObserver(self, forKeyPath: Preference.Key.edgeToEdgeVideo.rawValue, options: .new, context: nil)
    UserDefaults.standard.addObserver(self, forKeyPath: Preference.Key.unlockWindowAspectRatio.rawValue, options: .new, context: nil)
    updateAspectSwitch()
    return lockAspectSwitch
  }

  @objc private func lockAspectSwitchAction(_ sender: NSSwitch) {
    Preference.set(sender.state == .off, for: .unlockWindowAspectRatio)
  }

  private func updateAspectSwitch() {
    if Preference.bool(for: .edgeToEdgeVideo) {
      lockAspectSwitch.isEnabled = true
      lockAspectSwitch.state = Preference.bool(for: .unlockWindowAspectRatio) ? .off : .on
    } else {
      lockAspectSwitch.isEnabled = false
      lockAspectSwitch.state = .off
    }
  }

  private func createOSCSettingsView() -> NSView {
    let container = NSView()
    container.setContentHuggingPriority(.defaultHigh, for: .horizontal)

    self.oscLayoutSelector = OSCLayoutSelector()

    let label = ui.label("On Screen Controller", font: .boldSystemFont(ofSize: 13), isSecondary: true)
    let stack = ui.hStack(oscLayoutSelector.views)

    container.addSubview(label)
    container.addSubview(stack)
    label.padding(.top(8), .leading, .trailing(greaterThan: 0))
    stack.padding(.bottom(8), .horizontal(greaterThan: 0)).center(.x)
      .spacing(.top(.stackViewSpacing), to: label)

    return container
  }

  private func createSidebarSettingsView() -> NSView {
    let container = NSView()
    container.setContentHuggingPriority(.defaultHigh, for: .horizontal)

    return container
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
