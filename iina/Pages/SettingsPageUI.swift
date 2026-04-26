//
//  SettingsPageUI.swift
//  iina
//
//  Created by Hechen Li on 6/13/25.
//  Copyright © 2025 lhc. All rights reserved.
//

class SettingsPageUI: SettingsPage {
  private lazy var windowInitialSizeView: WindowInitialSizeView = WindowInitialSizeView(l10n: localizationContext)
  private lazy var windowInitialPositionView: WindowInitialPositionView = WindowInitialPositionView(l10n: localizationContext)
  private lazy var resizeWindowView: ResizeWindowView = ResizeWindowView(l10n: localizationContext)
  private lazy var oscLayoutView: OSCLayoutView = OSCLayoutView(l10n: localizationContext)
  private lazy var oscToolbarView: OSCToolbarView = OSCToolbarView(l10n: localizationContext)

  override var title: String {
    return NSLocalizedString("preference.ui", comment: "UI")
  }

  override var image: NSImage {
    return makeSymbol("macwindow", fallbackImage: "pref_ui")
  }

  override var localizationTable: String {
    "SettingsUILocalizable"
  }

  override func content() -> NSView {
    return sections {
      sectionAppearance()
      sectionWindow()
      sectionOSC()
      sectionOSD()
      sectionThumbnail()
      sectionPIP()
      sectionAccessibility()
    }
  }

  private func sectionAppearance() -> [NSView] {
    return section {
      SettingsListView(title: .text_Appearance) {
        SettingsItem.PopupButton()
          .image(name: "moonphase.first.quarter")
          .bindTo(.themeMaterial, ofType: Preference.Theme.self)
      }
    }
  }

  private func sectionWindow() -> [NSView] {
    return section {
      SettingsListView(title: .text_Window) {
        SettingsItem.Switch(title: .text_InitialWindowSize)
          .image(name: "custom.arrow.up.left.and.down.right.and.arrow.up.right.and.down.left.rectangle")
          .withExpandingDetailView(windowInitialSizeView.container)
          .bindExpandableView()
        SettingsItem.Switch(title: .text_InitialWindowPosition)
          .image(name: "arrow.up.and.down.and.arrow.left.and.right")
          .withExpandingDetailView(windowInitialPositionView.container)
          .bindExpandableView()
      }

      SettingsListView {
        SettingsItem.PopupButton()
          .image(name: "arrow.up.left.bottomright.rectangle")
          .bindTo(.resizeWindowOption, ofType: Preference.ResizeWindowOption.self)
          .withDetailView(resizeWindowView.view)
      }

      SettingsListView {
        SettingsItem.Switch()
          .image(name: "desktopcomputer")
          .bindTo(.usePhysicalResolution)
      }

      SettingsListView {
        SettingsItem.Switch()
          .image(name: "square.2.layers.3d.top.filled")
          .bindTo(.alwaysFloatOnTop)
        SettingsItem.Switch()
          .image(name: "pin.square")
          .bindTo(.alwaysShowOnTopIcon)
      }
    }
  }

  private func sectionOSC() -> [NSView] {
    return section {
      SettingsListView(title: .text_OnScreenController) {
        SettingsItem.General(title: .text_Layout)
          .image(name: "menubar.dock.rectangle")
          .withDetailView(oscLayoutView.view)
        SettingsItem.General(title: .text_Toolbar)
          .image(name: "ellipsis.rectangle")
          .withDetailView(oscToolbarView.view)
      }

      SettingsListView() {
        SettingsItem.PopupButton()
          .image(name: "forward.fill")
          .bindTo(.arrowButtonAction, ofType: Preference.ArrowButtonAction.self)
        SettingsItem.Input()
          .image(name: "timer")
          .bindTo(.controlBarAutoHideTimeout)
          .trailingLabel(.text_s)
      }

      SettingsListView {
        SettingsItem.Switch()
          .image(name: "arrow.right.and.line.vertical.and.arrow.left")
          .bindTo(.controlBarStickToCenter)
        SettingsItem.Switch()
          .image(name: "ruler")
          .bindTo(.showChapterPos)
        SettingsItem.Switch()
          .image(name: "slider.horizontal.below.square.and.square.filled")
          .bindTo(.showRemainingTime)
        SettingsItem.Switch()
          .bindTo(.scaleRemainingTime)
        SettingsItem.Switch()
          .image(name: "custom.computermouse.slash")
          .bindTo(.disablePlaySliderScrolling)
        SettingsItem.Switch()
          .bindTo(.disableVolumeSliderScrolling)
      }
    }
  }

  private func sectionOSD() -> [NSView] {
    return section {
      SettingsListView(title: .text_OnScreenDisplay) {
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

      SettingsListView() {
        SettingsItem.Input(title: .controlBarAutoHideTimeoutLabel)
          .image(name: "timer")
          .bindTo(.osdAutoHideTimeout)
          .trailingLabel(.text_s)
        SettingsItem.Input()
          .image(name: "textformat.size")
          .bindTo(.osdTextSize)
          .trailingLabel(.text_pt)
        SettingsItem.Switch()
          .image(name: "info.bubble")
          .bindTo(.displayTimeAndBatteryInFullScreen)
      }
    }
  }

  private func sectionThumbnail() -> [NSView] {
    return section {
      SettingsListView(title: .text_ThumbnailPreview) {
        SettingsItem.Switch()
          .image(name: "custom.photo.bubble.left")
          .bindTo(.enableThumbnailPreview)
          .withDetailView {
            SettingsItem.Input()
              .bindTo(.maxThumbnailPreviewCacheSize)
              .trailingLabel(.text_MB)
            SettingsItem.Switch()
              .bindTo(.enableThumbnailForRemoteFiles)
          }
        SettingsItem.Input()
          .bindTo(.thumbnailWidth)
          .trailingLabel(.text_pt)
          .hasDescription()
      }
    }
  }

  private func sectionPIP() -> [NSView] {
    return section {
      SettingsListView(title: .text_PictureinnPicture) {
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

  private func sectionAccessibility() -> [NSView] {
    return section {
      SettingsListView(title: .text_Accessibility) {
        SettingsItem.Switch()
          .image(name: "accessibility")
          .bindTo(.disableAnimations)
          .hasDescription()
          .withHelpLink(AppData.disableAnimationsHelpLink)
      }
    }
  }
}


fileprivate class WindowInitialSizeView: WithSettingsLocalizationContext {
  var l10n: SettingsLocalization.Context!
  let container: NSView
  let view: NSStackView
  lazy var ui: SettingsUIHelper = SettingsUIHelper(l10n)

  lazy var popupButtonDim: NSPopUpButton = ui.popupButton([
    (.text_Width, 0), (.text_Height, 1)
  ])

  lazy var popupButtonUnit: NSPopUpButton = ui.popupButton([
    (.text_point, 0), (.text_ofScreen, 1)
  ])

  lazy var textField: NSTextField = ui.textInput(value: "1280", width: 64)

  init(l10n: SettingsLocalization.Context) {
    self.l10n = l10n
    self.container = NSView()
    self.view = NSStackView()
    self.view.translatesAutoresizingMaskIntoConstraints = false
    self.view.orientation = .horizontal
    self.view.alignment = .firstBaseline

    view.addArrangedSubview(popupButtonDim)
    view.addArrangedSubview(textField)
    view.addArrangedSubview(popupButtonUnit)

    container.addSubview(view)
    view.padding(.bottom(8), .top(0), .leading(SettingsSubListView.padding), .trailing(0))
  }
}


fileprivate class WindowInitialPositionView: WithSettingsLocalizationContext {
  var l10n: SettingsLocalization.Context!
  let container: NSView
  let view: NSStackView
  lazy var ui: SettingsUIHelper = SettingsUIHelper(l10n)

  lazy var popupButtonXPos: NSPopUpButton = ui.popupButton([
    (.text_left, 0), (.text_right, 1)
  ])

  lazy var popupButtonYPos: NSPopUpButton = ui.popupButton([
    (.text_left, 0), (.text_right, 1)
  ])

  lazy var popupButtonXUnit: NSPopUpButton = ui.popupButton([
    (.text_point, 0), (.text_ofScreen, 1)
  ])

  lazy var popupButtonYUnit: NSPopUpButton = ui.popupButton([
    (.text_point, 0), (.text_ofScreen, 1)
  ])

  lazy var textFieldX: NSTextField = ui.textInput(value: "20", width: 64)

  lazy var textFieldY: NSTextField = ui.textInput(value: "20", width: 64)

  init(l10n: SettingsLocalization.Context) {
    self.l10n = l10n
    self.container = NSView()
    self.view = NSStackView()
    self.view.translatesAutoresizingMaskIntoConstraints = false
    self.view.orientation = .vertical
    self.view.alignment = .leading

    view.addArrangedSubview(
      ui.hStack(ui.image("arrow.left.to.line"), ui.label(.text_XOffset), textFieldX, popupButtonXUnit)
    )
    view.addArrangedSubview(
      ui.hStack(ui.space(width: 16), ui.label(.text_toThe), popupButtonXPos, ui.label(.text_sideOfTheScreen))
    )
    view.addArrangedSubview(
      ui.hStack(ui.image("arrow.up.to.line"), ui.label(.text_YOffset), textFieldY, popupButtonYUnit)
    )
    view.addArrangedSubview(
      ui.hStack(ui.space(width: 16), ui.label(.text_toThe), popupButtonYPos, ui.label(.text_sideOfTheScreen))
    )

    container.addSubview(view)
    view.padding(.bottom(8), .top(0), .leading(SettingsSubListView.padding), .trailing(0))
  }
}


fileprivate class ResizeWindowView: WithSettingsLocalizationContext {
  var l10n: SettingsLocalization.Context!
  lazy var ui: SettingsUIHelper = SettingsUIHelper(l10n)

  let view: NSView

  init(l10n: SettingsLocalization.Context) {
    self.l10n = l10n
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
}


fileprivate class OSCLayoutView: WithSettingsLocalizationContext {
  var l10n: SettingsLocalization.Context!
  lazy var ui: SettingsUIHelper = SettingsUIHelper(l10n)

  let view: NSView
  let imageViews: [NSImageView]

  init(l10n: SettingsLocalization.Context) {
    self.l10n = l10n
    self.view = NSView()
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    self.imageViews = [
      NSImageView(image: .init(named: "osc_float")!),
      NSImageView(image: .init(named: "osc_top")!),
      NSImageView(image: .init(named: "osc_bottom")!),
    ]

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
    SettingsUIHelper.hEquallySpaced(imageViews, 8, leading: SettingsSubListView.padding, trailing: 8)

    let buttons = ui.radioGroup(.oscPosition, size: .regular, [
      (.oscPositionItem0, 0), (.oscPositionItem1, 1), (.oscPositionItem2, 2)
    ])

    for (i, btn) in buttons.enumerated() {
      container.addSubview(btn)
      btn.spacing(to: imageViews[i], .top(8)).padding(.bottom(12))
        .center(with: imageViews[i], x: true)
    }

    view.addSubview(container)
    container.padding(.vertical).center(x: true)
  }
}


private class OSCToolbarView: WithSettingsLocalizationContext {
  var l10n: SettingsLocalization.Context!
  lazy var ui: SettingsUIHelper = SettingsUIHelper(l10n)

  let view: NSView
  let oscToolbarStackView: NSStackView
  let customizeButton: NSButton
  private let toolbarSettingsSheetController = PrefOSCToolbarSettingsSheetController()

  init(l10n: SettingsLocalization.Context) {
    self.l10n = l10n
    self.view = NSView()
    self.oscToolbarStackView = NSStackView()
    self.customizeButton = NSButton(title: l10n.localized(.text_Customize), target: nil, action: nil)
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
    customizeButton.center(with: box, y: true)
    SettingsUIHelper.hEquallySpaced([box, customizeButton], 8, leading: SettingsSubListView.padding, trailing: 8)

    view.addSubview(container)
    container.padding(.vertical).center(x: true)
    updateOSCToolbarButtons()
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
}
