//
//  VR2DMenu.swift
//  iina
//
//  The VR2D section of the Video menu, built in code rather than in the xib so
//  that syncing this fork with upstream never turns into a nib merge.
//
//  The menu is also where the keyboard shortcuts live. AppKit matches a menu's
//  key equivalents before the key event reaches the window, so there is no need
//  to touch IINA's own key handling — and the shortcut is always visible next
//  to the command it runs, which is the part a hidden binding gets wrong.
//

import Cocoa

class VR2DMenuController: NSObject, NSMenuDelegate {

  private let toggleItem = NSMenuItem()
  private let submenuItem = NSMenuItem()

  private var projectionItems: [(item: NSMenuItem, projection: VR2DProjection?)] = []
  private var layoutItems: [(item: NSMenuItem, layout: VR2DLayout?, swapEyes: Bool)] = []
  private var eyeItems: [(item: NSMenuItem, eye: VR2DEye)] = []
  private var fisheyeFovItem = NSMenuItem()

  /// Add the VR2D commands to the end of IINA's Video menu.
  init(videoMenu: NSMenu) {
    super.init()

    toggleItem.title = NSLocalizedString("vr2d.flatten", comment: "Flatten VR Video")
    toggleItem.action = #selector(MainWindowController.menuToggleVR2D(_:))
    toggleItem.keyEquivalent = "v"
    toggleItem.keyEquivalentModifierMask = [.option, .shift]

    submenuItem.title = NSLocalizedString("vr2d.menu", comment: "VR Video")
    let submenu = NSMenu()
    submenu.delegate = self
    submenuItem.submenu = submenu

    submenu.addItem(projectionMenu())
    submenu.addItem(layoutMenu())
    submenu.addItem(eyeMenu())
    submenu.addItem(.separator())
    submenu.addItem(lookAroundMenu())

    videoMenu.addItem(.separator())
    videoMenu.addItem(toggleItem)
    videoMenu.addItem(submenuItem)
  }

  // MARK: - Construction

  private func projectionMenu() -> NSMenuItem {
    let root = NSMenuItem()
    root.title = NSLocalizedString("vr2d.projection", comment: "Projection")
    let menu = NSMenu()

    let next = NSMenuItem(title: NSLocalizedString("vr2d.next", comment: "Try the Next One"),
                          action: #selector(MainWindowController.menuVR2DCycleProjection(_:)),
                          keyEquivalent: "p")
    next.keyEquivalentModifierMask = [.option]
    menu.addItem(next)
    menu.addItem(.separator())

    let choices: [(String, VR2DProjection?)] = [
      (NSLocalizedString("vr2d.auto_plain", comment: "Auto"), nil),
      (NSLocalizedString("vr2d.projection.he", comment: "180 Equirectangular"), .halfEquirect),
      (NSLocalizedString("vr2d.projection.e", comment: "360 Equirectangular"), .equirect),
      (NSLocalizedString("vr2d.projection.fisheye", comment: "Fisheye"), .fisheye),
      (NSLocalizedString("vr2d.projection.eac", comment: "Equi-Angular Cubemap"), .eac),
    ]
    for (title, projection) in choices {
      let item = NSMenuItem(title: title,
                            action: #selector(MainWindowController.menuVR2DSetProjection(_:)),
                            keyEquivalent: "")
      item.tag = projection?.rawValue ?? -1
      menu.addItem(item)
      projectionItems.append((item, projection))
    }

    menu.addItem(.separator())
    fisheyeFovItem.title = NSLocalizedString("vr2d.lens_angle", comment: "Lens Angle")
    fisheyeFovItem.action = #selector(MainWindowController.menuVR2DCycleFisheyeFov(_:))
    menu.addItem(fisheyeFovItem)

    root.submenu = menu
    return root
  }

  private func layoutMenu() -> NSMenuItem {
    let root = NSMenuItem()
    root.title = NSLocalizedString("vr2d.layout", comment: "Stereo Layout")
    let menu = NSMenu()

    let next = NSMenuItem(title: NSLocalizedString("vr2d.next", comment: "Try the Next One"),
                          action: #selector(MainWindowController.menuVR2DCycleLayout(_:)),
                          keyEquivalent: "l")
    next.keyEquivalentModifierMask = [.option]
    menu.addItem(next)
    menu.addItem(.separator())

    let choices: [(String, VR2DLayout?, Bool)] = [
      (NSLocalizedString("vr2d.auto_plain", comment: "Auto"), nil, false),
      (NSLocalizedString("vr2d.layout.mono", comment: "Monoscopic"), .mono, false),
      (NSLocalizedString("vr2d.layout.sbs", comment: "Side by Side"), .sbs, false),
      (NSLocalizedString("vr2d.layout.sbs_swapped", comment: "Side by Side, Right Eye First"), .sbs, true),
      (NSLocalizedString("vr2d.layout.tb", comment: "Over Under"), .tb, false),
      (NSLocalizedString("vr2d.layout.tb_swapped", comment: "Over Under, Bottom Eye First"), .tb, true),
    ]
    for (index, choice) in choices.enumerated() {
      let item = NSMenuItem(title: choice.0,
                            action: #selector(MainWindowController.menuVR2DSetLayout(_:)),
                            keyEquivalent: "")
      item.tag = index
      menu.addItem(item)
      layoutItems.append((item, choice.1, choice.2))
    }

    root.submenu = menu
    return root
  }

  private func eyeMenu() -> NSMenuItem {
    let root = NSMenuItem()
    root.title = NSLocalizedString("vr2d.eye", comment: "Eye")
    let menu = NSMenu()

    let swap = NSMenuItem(title: NSLocalizedString("vr2d.eye.swap", comment: "Swap"),
                          action: #selector(MainWindowController.menuVR2DSwapEye(_:)),
                          keyEquivalent: "e")
    swap.keyEquivalentModifierMask = [.option]
    menu.addItem(swap)
    menu.addItem(.separator())

    for (index, eye) in [VR2DEye.left, .right].enumerated() {
      let item = NSMenuItem(title: eye == .left ? NSLocalizedString("vr2d.eye.left", comment: "Left") : NSLocalizedString("vr2d.eye.right", comment: "Right"),
                            action: #selector(MainWindowController.menuVR2DSetEye(_:)),
                            keyEquivalent: "")
      item.tag = index
      menu.addItem(item)
      eyeItems.append((item, eye))
    }

    root.submenu = menu
    return root
  }

  private func lookAroundMenu() -> NSMenuItem {
    let root = NSMenuItem()
    root.title = NSLocalizedString("vr2d.look_around", comment: "Look Around")
    let menu = NSMenu()

    // Tags carry the direction so one action serves all four keys.
    let directions: [(String, String, Int)] = [
      (NSLocalizedString("vr2d.look_up", comment: "Look Up"), String(UnicodeScalar(NSUpArrowFunctionKey)!), 0),
      (NSLocalizedString("vr2d.look_down", comment: "Look Down"), String(UnicodeScalar(NSDownArrowFunctionKey)!), 1),
      (NSLocalizedString("vr2d.look_left", comment: "Look Left"), String(UnicodeScalar(NSLeftArrowFunctionKey)!), 2),
      (NSLocalizedString("vr2d.look_right", comment: "Look Right"), String(UnicodeScalar(NSRightArrowFunctionKey)!), 3),
    ]
    for (title, key, tag) in directions {
      let item = NSMenuItem(title: title,
                            action: #selector(MainWindowController.menuVR2DPan(_:)),
                            keyEquivalent: key)
      item.keyEquivalentModifierMask = [.option, .shift]
      item.tag = tag
      menu.addItem(item)
    }

    menu.addItem(.separator())

    let zoomIn = NSMenuItem(title: NSLocalizedString("vr2d.zoom_in", comment: "Zoom In"),
                            action: #selector(MainWindowController.menuVR2DZoom(_:)),
                            keyEquivalent: "=")
    zoomIn.keyEquivalentModifierMask = [.option]
    zoomIn.tag = -1
    menu.addItem(zoomIn)

    let zoomOut = NSMenuItem(title: NSLocalizedString("vr2d.zoom_out", comment: "Zoom Out"),
                             action: #selector(MainWindowController.menuVR2DZoom(_:)),
                             keyEquivalent: "-")
    zoomOut.keyEquivalentModifierMask = [.option]
    zoomOut.tag = 1
    menu.addItem(zoomOut)

    menu.addItem(.separator())

    let recentre = NSMenuItem(title: NSLocalizedString("vr2d.recentre", comment: "Recentre"),
                              action: #selector(MainWindowController.menuVR2DRecentre(_:)),
                              keyEquivalent: "0")
    recentre.keyEquivalentModifierMask = [.option]
    menu.addItem(recentre)

    root.submenu = menu
    return root
  }

  // MARK: - State

  /// Called before the Video menu is shown, so the ticks and the `Auto`
  /// descriptions always say what VR2D currently believes.
  func refresh() {
    let vr2d = PlayerCore.active.vr2d
    toggleItem.state = vr2d.isEnabled ? .on : .off

    let detected = vr2d.detection
    for (item, projection) in projectionItems {
      item.state = projection == vr2d.source.projection ? .on : .off
      if projection == nil {
        item.title = String(format: NSLocalizedString("vr2d.auto", comment: "Auto (%@)"), VR2DDetect.summarize(detected.source))
        // "Auto" is ticked only when nothing has been overridden.
        item.state = vr2d.source == detected.source ? .on : .off
      }
    }
    // Ticking a specific projection as well as Auto would be misleading.
    if projectionItems.first?.item.state == .on {
      for (item, projection) in projectionItems where projection != nil { item.state = .off }
    }

    fisheyeFovItem.title = vr2d.source.projection == .fisheye
      ? String(format: NSLocalizedString("vr2d.lens_angle.value", comment: "Lens Angle - %d"), Int(vr2d.source.inHFov))
      : NSLocalizedString("vr2d.lens_angle", comment: "Lens Angle")

    for (item, layout, swapEyes) in layoutItems {
      guard let layout else {
        item.title = "Auto (\(description(of: detected.source.layout, swapEyes: detected.source.swapEyes)))"
        item.state = vr2d.source.layout == detected.source.layout
          && vr2d.source.swapEyes == detected.source.swapEyes ? .on : .off
        continue
      }
      item.state = layout == vr2d.source.layout && swapEyes == vr2d.source.swapEyes ? .on : .off
    }

    for (item, eye) in eyeItems {
      item.state = eye == vr2d.eye ? .on : .off
    }
  }

  private func description(of layout: VR2DLayout, swapEyes: Bool) -> String {
    switch layout {
    case .mono: return "monoscopic"
    case .sbs: return swapEyes ? "side by side, right eye first" : "side by side"
    case .tb: return swapEyes ? "over under, bottom eye first" : "over under"
    }
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    refresh()
  }
}

// MARK: - Actions

extension MainWindowController {

  @objc func menuToggleVR2D(_ sender: NSMenuItem) {
    player.vr2d.toggle()
  }

  @objc func menuVR2DCycleProjection(_ sender: NSMenuItem) {
    player.vr2d.cycleProjection()
  }

  @objc func menuVR2DSetProjection(_ sender: NSMenuItem) {
    player.vr2d.setProjection(VR2DProjection(rawValue: sender.tag))
  }

  @objc func menuVR2DCycleFisheyeFov(_ sender: NSMenuItem) {
    player.vr2d.cycleFisheyeFov()
  }

  @objc func menuVR2DCycleLayout(_ sender: NSMenuItem) {
    player.vr2d.cycleLayout()
  }

  @objc func menuVR2DSetLayout(_ sender: NSMenuItem) {
    let choices: [(VR2DLayout?, Bool)] = [
      (nil, false), (.mono, false), (.sbs, false), (.sbs, true), (.tb, false), (.tb, true),
    ]
    guard choices.indices.contains(sender.tag) else { return }
    let choice = choices[sender.tag]
    player.vr2d.setLayout(choice.0, swapEyes: choice.1)
  }

  @objc func menuVR2DSwapEye(_ sender: NSMenuItem) {
    player.vr2d.swapEye()
  }

  @objc func menuVR2DSetEye(_ sender: NSMenuItem) {
    player.vr2d.setEye(sender.tag == 1 ? .right : .left)
  }

  @objc func menuVR2DPan(_ sender: NSMenuItem) {
    let step = Preference.double(for: .vr2dKeyboardStep)
    switch sender.tag {
    case 0: player.vr2d.panBy(yaw: 0, pitch: step)
    case 1: player.vr2d.panBy(yaw: 0, pitch: -step)
    case 2: player.vr2d.panBy(yaw: -step, pitch: 0)
    default: player.vr2d.panBy(yaw: step, pitch: 0)
    }
  }

  @objc func menuVR2DZoom(_ sender: NSMenuItem) {
    player.vr2d.zoom(notches: Double(sender.tag))
  }

  @objc func menuVR2DRecentre(_ sender: NSMenuItem) {
    player.vr2d.resetView()
  }
}
