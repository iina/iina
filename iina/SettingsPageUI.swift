//
//  SettingsPageUI.swift
//  iina
//
//  Created by Hechen Li on 6/13/25.
//  Copyright © 2025 lhc. All rights reserved.
//

fileprivate let ui = SettingsUIHelper.sharedUI

class SettingsPageUI: SettingsPage {
  private lazy var windowGeometryConfigurationItem = WindowGeometryConfigurationItem(geometryBindings: geometryBindings)
  private lazy var resizeWindowView: ResizeWindowView = ResizeWindowView()
  private lazy var oscLayoutView: OSCLayoutView = OSCLayoutView()
  private lazy var oscToolbarView: OSCToolbarView = OSCToolbarView()

  private lazy var geometryBindings = GeometryBindings()
  private lazy var accentColorItem: AccentColorSettingsItem = {
    let item = AccentColorSettingsItem()
      .image(name: "paintpalette")
    item.didCommitChange = { [weak item] in
      guard let window = item?.window as? SettingsWindow else { return }
      AppRestart.confirmSettingsChange(in: window)
    }
    return item
  }()

  override var identifier: String {
    "ui"
  }

  override var title: String {
    return NSLocalizedString("preference.ui", comment: "UI")
  }

  override var image: NSImage {
    return .sf("macwindow", withConfiguration: symbolConfiguration)!
  }

  override var localizationTable: String {
    "SettingsUILocalizable"
  }

  override var helpInfo: String? {
    ui.localized("more_ui_settings")
  }

  override func pageLoaded() {
    geometryBindings.updateControls()
  }

  override func content() -> [SettingsSection] {
    return sections {
      sectionAppearance()
      sectionWindow()
      sectionOSC()
      sectionSidebar()
      sectionOSD()
      sectionThumbnail()
      sectionPIP()
      sectionAccessibility()
    }
  }

  private func sectionAppearance() -> SettingsSection {
    return section {
      SettingsList(title: .text_Appearance) {
        SettingsItem.PopupButton()
          .image(name: "moonphase.first.quarter")
          .bindTo(.themeMaterial, ofType: Preference.Theme.self)
        accentColorItem
        if #available(macOS 26.0, *) { 
          SettingsItem.General(title: .general("sidebar.liquid_glass"))
            .image(name: ["capsule.on.rectangle.liquid.glass", "liquid.glass"])
            .withExpandingDetailView {
              SettingsItem.Switch(title: .text_OnScreenDisplay)
                .bindTo(.useLiquidGlassOSD)
              SettingsItem.Switch(title: .text_OnScreenController)
                .bindTo(.useLiquidGlassOSC)
              SettingsItem.Switch(title: .general("sidebar.sidebar"))
                .bindTo(.useLiquidGlassSidebar)
            }
        }
        SettingsItem.Switch(title: .general("sidebar.compact_interface"))
          .image(name: "rectangle.grid.3x2.fill")
          .bindTo(.compactUI)
      }
    }
  }

  private func sectionWindow() -> SettingsSection {
    return section {
      SettingsList(title: .text_Window) {
        SettingsItem.Switch(title: .text_InitialWindowSize)
          .image(name: "arrow.up.left.and.arrow.down.right")
          .bindToCustom { [weak self] in self?.geometryBindings.bindSizeSwitch($0) }
        SettingsItem.Switch(title: .text_InitialWindowPosition)
          .image(name: "arrow.up.and.down.and.arrow.left.and.right")
          .bindToCustom { [weak self] in self?.geometryBindings.bindPositionSwitch($0) }
        windowGeometryConfigurationItem
      }

      SettingsList {
        SettingsItem.PopupButton()
          .image(name: "arrow.up.left.bottomright.rectangle")
          .bindTo(.resizeWindowOption, ofType: Preference.ResizeWindowOption.self)
          .withDetailView(resizeWindowView)
      }

      SettingsList {
        SettingsItem.Switch()
          .image(name: "desktopcomputer")
          .bindTo(.usePhysicalResolution)
      }

      SettingsList {
        SettingsItem.Switch()
          .image(name: "square.2.layers.3d.top.filled")
          .bindTo(.alwaysFloatOnTop)
        SettingsItem.Switch()
          .image(name: "pin.square")
          .bindTo(.alwaysShowOnTopIcon)
      }
    }
  }

  private func sectionOSC() -> SettingsSection {
    return section {
      SettingsList(title: .text_OnScreenController) {
        SettingsItem.General(title: .text_Layout)
          .image(name: "menubar.dock.rectangle")
          .withDetailView(oscLayoutView)
        SettingsItem.General(title: .text_Toolbar)
          .image(name: "ellipsis.rectangle")
          .withDetailView(oscToolbarView)
      }

      OSCArrowSettingsList()

      SettingsList {
        SettingsItem.Switch()
          .image(name: "ruler")
          .bindTo(.showChapterPos)
        SettingsItem.Switch()
          .image(name: "slider.horizontal.below.square.and.square.filled")
          .bindTo(.showRemainingTime)
          .withDetailView {
            SettingsItem.Switch()
              .bindTo(.scaleRemainingTime)
          }
        SettingsItem.Switch()
          .image(name: "custom.computermouse.slash")
          .bindTo(.disablePlaySliderScrolling)
        SettingsItem.Switch()
          .bindTo(.disableVolumeSliderScrolling)
      }
    }
  }

  private func sectionSidebar() -> SettingsSection {
    return section {
      SettingsList(title: .general("sidebar.sidebar_position")) {
        SettingsItem.General(title: .general("sidebar.settings"))
          .image(name: "gearshape.fill")
          .withValueView(SidebarPosSwitch(.sidebarSettingsDisplayAtLeading))
        SettingsItem.General(title: .general("sidebar.playlist_and_chapters"))
          .image(name: "list.bullet.rectangle.fill")
          .withValueView(SidebarPosSwitch(.sidebarPlaylistDisplayAtLeading))
        SettingsItem.General(title: .general("sidebar.plugins"))
          .image(name: "puzzlepiece.extension.fill")
          .withValueView(SidebarPosSwitch(.sidebarPluginsDisplayAtLeading))
      }
    }
  }

  private func sectionOSD() -> SettingsSection {
    return section {
      SettingsList(title: .text_OnScreenDisplay) {
        SettingsItem.Switch()
          .image(name: ["inset.filled.topleft.rectangle", "app.badge"])
          .bindTo(.enableOSD)
        SettingsItem.General(title: .text_SuppressMessagesFor)
          .withExpandingDetailView {
            SettingsItem.Switch()
              .bindTo(.disableOSDFileStartMsg)
            SettingsItem.Switch()
              .bindTo(.disableOSDPauseResumeMsgs)
            SettingsItem.Switch()
              .bindTo(.disableOSDSeekMsg)
            SettingsItem.Switch()
              .bindTo(.disableOSDSpeedMsg)
          }
      }

      SettingsList() {
        SettingsItem.Input(title: .controlBarAutoHideTimeoutLabel)
          .image(name: "timer")
          .bindTo(.osdAutoHideTimeout)
          .range(0...Double(Int.max), allowsFloats: true)
          .trailingLabel(.text_s)
        SettingsItem.Input()
          .image(name: "textformat.size")
          .bindTo(.osdTextSize)
          .range(1...500)
          .trailingLabel(.text_pt)
        SettingsItem.Switch()
          .image(name: "info.bubble")
          .bindTo(.displayTimeAndBatteryInFullScreen)
      }
    }
  }

  private func sectionThumbnail() -> SettingsSection {
    return section {
      SettingsList(title: .text_ThumbnailPreview) {
        SettingsItem.Switch()
          .image(name: "custom.photo.bubble.left")
          .bindTo(.enableThumbnailPreview)
          .withDetailView {
            SettingsItem.Input()
              .bindTo(.maxThumbnailPreviewCacheSize)
              .range(0...Double(Int.max))
              .trailingLabel(.text_MB)
            SettingsItem.Switch()
              .bindTo(.enableThumbnailForRemoteFiles)
            SettingsItem.Input()
              .bindTo(.thumbnailWidth)
              .range(1...2000)
              .trailingLabel(.text_pt)
              .hasDescription()
          }
      }
    }
  }

  private func sectionPIP() -> SettingsSection {
    return section {
      SettingsList(title: .text_PictureinnPicture) {
        SettingsItem.General(title: .text_WhenEnteringPIP)
          .image(name: "pip.enter")
          .withDetailView {
            SettingsItem.PopupButton()
              .bindTo(.windowBehaviorWhenPip, ofType: Preference.WindowBehaviorWhenPip.self)
            SettingsItem.Switch()
              .bindTo(.pauseWhenPip)
          }
        SettingsItem.Switch()
          .image(name: "pip.swap")
          .bindTo(.togglePipByMinimizingWindow)
          .withDetailView {
            SettingsItem.Switch()
              .bindTo(.togglePipByMinimizingWindowForVideoOnly)
          }
      }
    }
  }

  private func sectionAccessibility() -> SettingsSection {
    return section {
      SettingsList(title: .text_Accessibility) {
        SettingsItem.Switch()
          .image(name: "accessibility")
          .bindTo(.disableAnimations)
          .hasDescription()
          .withHelpLink(AppData.disableAnimationsHelpLink)
      }
    }
  }
}


fileprivate class GeometryBindings: NSObject {
  private let prefObserver = Preference.Observer()
  private var geometry = GeometryBindings.loadGeometry()
  private var windowSizeSwitch: SettingsItem.Switch?
  private var windowPositionSwitch: SettingsItem.Switch?

  override init() {
    super.init()
    prefObserver.add(.initialWindowSizePosition) { [weak self] _ in
      self?.updateControls()
    }
  }

  func bindSizeSwitch(_ control: SettingsItem.Switch) {
    windowSizeSwitch = control
    control.stateChangeCallback = { [weak self, weak control] _ in
      guard let self, let control else { return }
      self.geometry.sizeEnabled = control.nsSwitch.state == .on
      self.persistGeometry()
    }
  }

  func bindPositionSwitch(_ control: SettingsItem.Switch) {
    windowPositionSwitch = control
    control.stateChangeCallback = { [weak self, weak control] _ in
      guard let self, let control else { return }
      self.geometry.positionEnabled = control.nsSwitch.state == .on
      self.persistGeometry()
    }
  }

  func configurationDraft() -> InitialWindowGeometry {
    updateControls()
    return geometry
  }

  func save(_ draft: InitialWindowGeometry) {
    geometry = draft
    persistGeometry()
    updateControls()
  }

  private static func loadGeometry() -> InitialWindowGeometry {
    let raw = Preference.string(for: .initialWindowSizePosition) ?? ""
    let active = InitialWindowGeometry(raw)
    var stored = InitialWindowGeometry(Preference.string(for: .initialWindowGeometryConfiguration) ?? "")
    stored.sizeEnabled = active.sizeEnabled
    stored.positionEnabled = active.positionEnabled
    return stored.geometryString == raw ? stored : active
  }

  private func persistGeometry() {
    var configured = geometry
    configured.sizeEnabled = true
    configured.positionEnabled = true
    Preference.set(configured.geometryString, for: .initialWindowGeometryConfiguration)
    Preference.set(geometry.geometryString, for: .initialWindowSizePosition)
  }

  func updateControls() {
    let raw = Preference.string(for: .initialWindowSizePosition) ?? ""
    if raw != geometry.geometryString { geometry = Self.loadGeometry() }
    windowSizeSwitch?.setIsOn(geometry.sizeEnabled)
    windowPositionSwitch?.setIsOn(geometry.positionEnabled)
  }
}


fileprivate class WindowGeometryConfigurationItem: SettingsItem.General {
  private let sheetController = WindowGeometrySettingsSheetController()
  private let configureButton = ui.button("windowGeometry.configureShort")
  private let geometryBindings: GeometryBindings

  init(geometryBindings: GeometryBindings) {
    self.geometryBindings = geometryBindings
    super.init(title: .init("windowGeometry.configure"))
    _ = image(name: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
    configureButton.target = self
    configureButton.action = #selector(configureGeometry)
  }

  override func getValueViews() -> [NSView] { [configureButton] }
  @objc private func configureGeometry() {
    guard let window = configureButton.window else { return }
    sheetController.present(on: window, geometry: geometryBindings.configurationDraft(),
      mediaAspect: WindowGeometryConfigurationItem.currentMediaAspect) { [weak self] draft in
      self?.geometryBindings.save(draft)
    }
  }

  static var visiblePlayers: [PlayerCore] {
    let players = PlayerCore.playerCores.filter { $0.mainWindow.isWindowLoaded && $0.mainWindow.window?.isVisible == true }
    guard !players.isEmpty else { return [] }
    let active = PlayerCore.lastActive
    return players.sorted { $0 === active && $1 !== active }
  }

  static var currentMediaAspect: CGFloat {
    guard let player = visiblePlayers.first,
          let width = player.info.displayWidth, let height = player.info.displayHeight, width > 0, height > 0 else { return 16 / 9 }
    let display = player.videoSizeForDisplay
    return CGFloat(display.0) / CGFloat(max(1, display.1))
  }

  override func registerSearchEntry(context: SettingsSearch.Context) {
    super.registerSearchEntry(context: context)
    context.add(itemID, ui.localized("windowGeometry.configure"))
  }
}


fileprivate class ResizeWindowView: SettingsContainer {
  lazy var itemID = SettingsContainerUUID.next()

  let view: NSView

  init() {
    self.view = NSView()
    let buttons = ui.radioGroup(.resizeWindowTiming, size: .regular, [
      (.text_AlwaysWhenPlaying, 0), (.text_WhenMediaIsOpenedManually, 1), (.text_DoNotResize, 2)
    ])

    buttons.forEach {
      view.addSubview($0)
      $0.padding(.leading(20))
    }
    SettingsUIHelper.vEquallySpaced(buttons, 8, top: 0, bottom: 12)
  }

  func makeView() -> NSView {
    return view
  }
}


fileprivate class OSCLayoutView: NSObject, SettingsContainer {
  lazy var itemID = SettingsContainerUUID.next()

  let view: NSView
  let imageViews: [NSImageView]
  private let configureButton = ui.button("oscDefaultPosition.configure")
  private let positionSheetController = OSCPositionSettingsSheetController()
  private let prefObserver = Preference.Observer()

  override init() {
    self.view = NSView()
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    self.imageViews = [
      NSImageView(image: .sf("osc_float_figure")!),
      NSImageView(image: .sf("osc_top_figure")!),
      NSImageView(image: .sf("osc_bottom_figure")!),
    ]
    super.init()

    imageViews.forEach { iv in
      iv.wantsLayer = true
      iv.layer?.borderWidth = 2.0
      iv.layer?.borderColor = NSColor.separatorColor.cgColor
      iv.layer?.cornerRadius = 6.0
      iv.layer?.masksToBounds = true
      iv.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(iv)
      iv.padding(.top(4)).size(width: 480 * 0.22, height: 270 * 0.22)
    }
    SettingsUIHelper.hEquallySpaced(imageViews, 8, leading: SettingsSubList.indent, trailing: 8)

    let buttons = ui.radioGroup(.oscPosition, size: .regular, [
      (.oscPositionItem0, 0), (.oscPositionItem1, 1), (.oscPositionItem2, 2)
    ])

    for (i, btn) in buttons.enumerated() {
      container.addSubview(btn)
      btn.spacing(.top(8), to: imageViews[i])
        .center(.x, with: imageViews[i])
    }

    container.addSubview(configureButton)
    configureButton.spacing(.top(12), to: buttons[0])
      .padding(.leading(SettingsSubList.indent + 8))
    configureButton.target = self
    configureButton.action = #selector(configurePosition)
    configureButton.toolTip = ui.localized("oscDefaultPosition.desc")
    let floatingBottom = container.bottomAnchor.constraint(equalTo: configureButton.bottomAnchor, constant: 12)
    let dockedBottom = container.bottomAnchor.constraint(equalTo: buttons[0].bottomAnchor, constant: 12)
    prefObserver.add(.oscPosition, runNow: true) { [weak self] _ in
      let isFloating = Preference.integer(for: .oscPosition) == Preference.OSCPosition.floating.rawValue
      self?.configureButton.isHidden = !isFloating
      floatingBottom.isActive = false
      dockedBottom.isActive = false
      (isFloating ? floatingBottom : dockedBottom).isActive = true
    }

    view.addSubview(container)
    container.padding(.vertical).center(.x)
  }

  @objc private func configurePosition() {
    guard let window = view.window else { return }
    let players = WindowGeometryConfigurationItem.visiblePlayers
    OSCPositionConfiguration.present(on: window, players: players, using: positionSheetController)
  }

  func makeView() -> NSView {
    return view
  }

  func registerSearchEntry(context: SettingsSearch.Context) {
    context.add(itemID, ui.localized("oscDefaultPosition.configure"))
  }
}


private class OSCToolbarView: SettingsContainer {
  lazy var itemID = SettingsContainerUUID.next()

  let view: NSView
  let oscToolbarStackView: NSStackView
  let customizeButton: NSButton
  private let toolbarSettingsSheetController = PrefOSCToolbarSettingsSheetController()

  init() {
    self.view = NSView()
    self.oscToolbarStackView = NSStackView()
    self.customizeButton = NSButton(title: ui.localized(.text_Customize), target: nil, action: nil)
  }

  private func updateOSCToolbarButtons() {
    oscToolbarStackView.views.forEach { oscToolbarStackView.removeView($0) }
    for buttonType in PrefUIViewController.oscToolbarButtons {
      let button = NSButton()
      OSCToolbarButton.setStyle(of: button, buttonType: buttonType)
      oscToolbarStackView.addView(button, in: .trailing)
      // Button is actually disabled so that its mouseDown goes to its superview instead
      button.isEnabled = false
      // But don't gray it out
      (button.cell! as! NSButtonCell).imageDimsWhenDisabled = false
    }
  }

  @objc func customizeOSCToolbarAction(_ sender: NSButton!) {
    toolbarSettingsSheetController.currentItemsView?.initItems(fromItems: PrefUIViewController.oscToolbarButtons)
    toolbarSettingsSheetController.currentButtonTypes = PrefUIViewController.oscToolbarButtons
    view.window?.beginSheet(toolbarSettingsSheetController.window!) { response in
      guard response == .OK else { return }
      let newItems = self.toolbarSettingsSheetController.currentButtonTypes
      let array = newItems.map { $0.rawValue }
      Preference.set(array, for: .controlBarToolbarButtons)
      self.updateOSCToolbarButtons()
    }
  }

  func makeView() -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    oscToolbarStackView.translatesAutoresizingMaskIntoConstraints = false
    oscToolbarStackView.orientation = .horizontal
    oscToolbarStackView.distribution = .gravityAreas
    oscToolbarStackView.spacing = 0

    let box = NSBox()
    box.translatesAutoresizingMaskIntoConstraints = false
    box.boxType = .primary
    box.titlePosition = .noTitle
    box.contentViewMargins = .zero
    box.addSubview(oscToolbarStackView)
    oscToolbarStackView.padding(.vertical, .leading(greaterThan: 0), .trailing(0))
    container.addSubview(box)
    box.padding(.top, .bottom(8))
    box.widthAnchor
      .constraint(equalTo: box.heightAnchor, multiplier: 5).isActive = true

    customizeButton.target = self
    customizeButton.action = #selector(customizeOSCToolbarAction(_:))
    customizeButton.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(customizeButton)
    customizeButton.center(.y, with: box)
    SettingsUIHelper.hEquallySpaced([box, customizeButton], 8, leading: SettingsSubList.indent, trailing: 8)

    view.addSubview(container)
    container.padding(.vertical).center(.x)
    updateOSCToolbarButtons()
    return view
  }
}


fileprivate class OSCArrowSettingsList: SettingsList {
  private let prefObserver = Preference.Observer()
  private weak var renderedList: SettingsList.View?
  private let seekInput = SettingsItem.Input(step: 1)
    .bindTo(.oscArrowSeekSeconds)
    .range(1...Double(Int.max))
    .trailingLabel(.text_s)
  private let autoHideInput = SettingsItem.SwitchWithInput()
    .image(name: "timer")
    .labelKey(.controlBarAutoHideTimeout)
    .bindInputTo(.controlBarAutoHideTimeout)
    .bindSwitchTo(.enableControlBarAutoHide)
    .range(0...Double(Int.max), allowsFloats: true)
    .step(1)
    .trailingLabel(.text_s)
  private var showsSeekInput = false

  init() {
    super.init(title: nil, [])
    items = [
      SettingsItem.PopupButton()
        .image(name: "forward.fill")
        .bindTo(.arrowButtonAction, ofType: Preference.ArrowButtonAction.self),
      seekInput,
      autoHideInput
    ]
    prefObserver.add(.arrowButtonAction) { [weak self] _ in
      guard let self, let list = self.renderedList else { return }
      let show = Preference.integer(for: .arrowButtonAction) == Preference.ArrowButtonAction.seek.rawValue
      guard show != self.showsSeekInput else { return }
      list.contentView?.subviews.forEach { $0.removeFromSuperview() }
      self.addItems(to: list)
    }
  }

  override func addItems(to listView: SettingsList.View) {
    renderedList = listView
    showsSeekInput = Preference.integer(for: .arrowButtonAction) == Preference.ArrowButtonAction.seek.rawValue
    let allItems = items
    if !showsSeekInput { items = items.filter { $0 !== seekInput } }
    super.addItems(to: listView)
    items = allItems
  }
}


enum OSCPositionConfiguration {
  static func present(on parent: NSWindow, players: [PlayerCore], using controller: OSCPositionSettingsSheetController) {
    let contexts = players.compactMap { player -> PositionPreviewContext? in
      guard let playerWindow = player.mainWindow.window, let content = playerWindow.contentView else { return nil }
      let title = player === players.first ? ui.localized("previewContext.window") : playerWindow.title
      let minimum = playerWindow.contentRect(forFrameRect: NSRect(origin: .zero, size: AppData.floatingOSCWindowMinSize)).size
      return PositionPreviewContext(title: title, size: content.bounds.size, minimumSize: minimum)
    }
    var appearance = FloatingOSCPreviewAppearance()
    appearance.compact = Preference.bool(for: .compactUI)
    // The preview keeps a full titlebar even while the live header is hidden or animating.
    let normalTitlebarHeight: CGFloat = if #available(macOS 26, *) { 32 } else { 28 }
    appearance.titlebarHeight = normalTitlebarHeight + (appearance.compact ? 0 : 8)
    let buttons = (Preference.array(for: .controlBarToolbarButtons) as? [Int] ?? []).compactMap(Preference.ToolBarButton.init(rawValue:))
    appearance.toolbarImages = buttons.map { $0.image() }
    if let player = players.first {
      appearance.sliderHeight = player.mainWindow.playSlider.frame.height
      appearance.transportImages = [player.mainWindow.leftArrowButton.image, player.mainWindow.playButton.image,
                                    player.mainWindow.rightArrowButton.image].compactMap { $0 }
    }
    controller.present(on: parent, contexts: contexts, appearance: appearance)
  }

}
