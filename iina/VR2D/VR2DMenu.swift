//
//  VR2DMenu.swift
//  iina
//
//  The VR2D entry in the Video menu, built in code rather than in the xib so
//  that syncing this fork with upstream never turns into a nib merge.
//
//  It sits with Aspect Ratio, Crop and Rotation and works the way they do: a
//  list of values with a tick on the current one, the first of which turns the
//  whole thing off. So there is no separate on/off command — choosing "Off" is
//  the off switch, exactly as Crop's "None" is.
//
//  The submenus carry the keyboard shortcuts. AppKit matches a menu's key
//  equivalents before the key event reaches the window, so IINA's own key
//  handling is untouched and the shortcut is always visible next to the command
//  it runs.
//

import Cocoa

class VR2DMenuController: NSObject, NSMenuDelegate {

  static let offTag = -2
  static let autoTag = -1

  private let rootItem = NSMenuItem()
  private var offItem = NSMenuItem()
  private var fisheyeItem = NSMenuItem()

  private var projectionItems: [(item: NSMenuItem, projection: VR2DProjection?)] = []
  private var fisheyeFovItems: [(item: NSMenuItem, fov: Double)] = []
  private var layoutItems: [(item: NSMenuItem, layout: VR2DLayout?, swapEyes: Bool)] = []
  private var eyeItems: [(item: NSMenuItem, eye: VR2DEye)] = []

  /// Add the VR2D entry to the Video menu, next to the other commands that
  /// change how the frame is mapped onto the screen.
  init(videoMenu: NSMenu, after rotationMenu: NSMenu?) {
    super.init()

    rootItem.title = NSLocalizedString("vr2d.menu", comment: "VR Video")
    let menu = NSMenu()
    menu.delegate = self
    rootItem.submenu = menu

    // Off first, then the projections — the same shape as Crop's "None"
    // followed by its sizes.
    offItem = NSMenuItem(title: NSLocalizedString("vr2d.off", comment: "Off"),
                         action: #selector(MainWindowController.menuVR2DSetProjection(_:)),
                         keyEquivalent: "")
    offItem.tag = VR2DMenuController.offTag
    menu.addItem(offItem)
    menu.addItem(projectionItem(NSLocalizedString("vr2d.auto_plain", comment: "Auto"), nil))
    menu.addItem(.separator())
    menu.addItem(projectionItem(NSLocalizedString("vr2d.projection.he", comment: "180 Equirectangular"),
                                .halfEquirect))
    menu.addItem(projectionItem(NSLocalizedString("vr2d.projection.e", comment: "360 Equirectangular"),
                                .equirect))
    menu.addItem(fisheyeMenu())
    menu.addItem(projectionItem(NSLocalizedString("vr2d.projection.eac", comment: "Equi-Angular Cubemap"),
                                .eac))
    menu.addItem(.separator())
    menu.addItem(layoutMenu())
    menu.addItem(eyeMenu())
    menu.addItem(lookAroundMenu())

    // Straight after Rotation: it is the same kind of thing, whereas flip and
    // mirror are their own little group.
    let index = rotationMenu.map { videoMenu.indexOfItem(withSubmenu: $0) } ?? -1
    if index >= 0 {
      videoMenu.insertItem(rootItem, at: index + 1)
    } else {
      videoMenu.addItem(rootItem)
    }
  }

  // MARK: - Construction

  /// One row of the projection list. A `nil` projection means "auto", i.e. use
  /// whatever detection worked out.
  private func projectionItem(_ title: String, _ projection: VR2DProjection?) -> NSMenuItem {
    let item = NSMenuItem(title: title,
                          action: #selector(MainWindowController.menuVR2DSetProjection(_:)),
                          keyEquivalent: "")
    item.tag = projection?.rawValue ?? VR2DMenuController.autoTag
    projectionItems.append((item, projection))
    return item
  }

  /// Fisheye is a projection like the others, but the lens angle only means
  /// anything here, so it gets a submenu rather than another row further down.
  private func fisheyeMenu() -> NSMenuItem {
    fisheyeItem.title = NSLocalizedString("vr2d.projection.fisheye", comment: "Fisheye")
    let menu = NSMenu()
    for fov in [180.0, 190.0, 200.0, 220.0] {
      let item = NSMenuItem(title: "\(Int(fov))\(Constants.String.degree)",
                            action: #selector(MainWindowController.menuVR2DSetFisheyeFov(_:)),
                            keyEquivalent: "")
      item.tag = Int(fov)
      menu.addItem(item)
      fisheyeFovItems.append((item, fov))
    }
    fisheyeItem.submenu = menu
    return fisheyeItem
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
      let item = NSMenuItem(title: eye == .left
                              ? NSLocalizedString("vr2d.eye.left", comment: "Left")
                              : NSLocalizedString("vr2d.eye.right", comment: "Right"),
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
      (NSLocalizedString("vr2d.look_up", comment: "Look Up"),
       String(UnicodeScalar(NSUpArrowFunctionKey)!), 0),
      (NSLocalizedString("vr2d.look_down", comment: "Look Down"),
       String(UnicodeScalar(NSDownArrowFunctionKey)!), 1),
      (NSLocalizedString("vr2d.look_left", comment: "Look Left"),
       String(UnicodeScalar(NSLeftArrowFunctionKey)!), 2),
      (NSLocalizedString("vr2d.look_right", comment: "Look Right"),
       String(UnicodeScalar(NSRightArrowFunctionKey)!), 3),
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

  /// Called before the menu is shown, so the ticks always say what VR2D
  /// currently believes.
  func refresh() {
    let vr2d = PlayerCore.active.vr2d
    let detected = vr2d.detection
    let isAuto = vr2d.isEnabled && vr2d.source == detected.source

    offItem.state = vr2d.isEnabled ? .off : .on

    for (item, projection) in projectionItems {
      guard let projection else {
        item.title = String(format: NSLocalizedString("vr2d.auto", comment: "Auto (%@)"),
                            VR2DDetect.summarize(detected.source))
        item.state = isAuto ? .on : .off
        continue
      }
      item.state = vr2d.isEnabled && !isAuto && vr2d.source.projection == projection ? .on : .off
    }

    fisheyeItem.state = vr2d.isEnabled && !isAuto && vr2d.source.projection == .fisheye ? .on : .off
    for (item, fov) in fisheyeFovItems {
      item.state = fisheyeItem.state == .on && vr2d.source.inHFov == fov ? .on : .off
    }

    for (item, layout, swapEyes) in layoutItems {
      guard let layout else {
        item.title = String(format: NSLocalizedString("vr2d.auto", comment: "Auto (%@)"),
                            description(of: detected.source.layout,
                                        swapEyes: detected.source.swapEyes))
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
    case .mono:
      return NSLocalizedString("vr2d.layout.mono", comment: "Monoscopic")
    case .sbs:
      return swapEyes
        ? NSLocalizedString("vr2d.layout.sbs_swapped", comment: "Side by Side, Right Eye First")
        : NSLocalizedString("vr2d.layout.sbs", comment: "Side by Side")
    case .tb:
      return swapEyes
        ? NSLocalizedString("vr2d.layout.tb_swapped", comment: "Over Under, Bottom Eye First")
        : NSLocalizedString("vr2d.layout.tb", comment: "Over Under")
    }
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    refresh()
  }
}

// MARK: - Actions

extension MainWindowController {

  @objc func menuVR2DSetProjection(_ sender: NSMenuItem) {
    switch sender.tag {
    case VR2DMenuController.offTag: player.vr2d.setEnabled(false)
    case VR2DMenuController.autoTag: player.vr2d.selectProjection(nil)
    default: player.vr2d.selectProjection(VR2DProjection(rawValue: sender.tag))
    }
  }

  @objc func menuVR2DSetFisheyeFov(_ sender: NSMenuItem) {
    player.vr2d.selectFisheye(fov: Double(sender.tag))
  }

  @objc func menuVR2DCycleProjection(_ sender: NSMenuItem) {
    player.vr2d.cycleProjection()
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
