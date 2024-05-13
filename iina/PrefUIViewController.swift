//
//  PrefUIViewController.swift
//  iina
//
//  Created by lhc on 25/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate let SizeWidthTag = 0
fileprivate let SizeHeightTag = 1
fileprivate let UnitPointTag = 0
fileprivate let UnitPercentTag = 1
fileprivate let SideLeftTag = 0
fileprivate let SideRightTag = 1
fileprivate let SideTopTag = 0
fileprivate let SideBottomTag = 1

@objcMembers
class PrefUIViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefUIViewController")
  }

  var preferenceTabTitle: String {
    return NSLocalizedString("preference.ui", comment: "UI")
  }

  var preferenceTabImage: NSImage {
    return NSImage(named: NSImage.Name("pref_ui"))!
  }

  static var oscToolbarButtons: [Preference.ToolBarButton] {
    get {
      return (Preference.array(for: .controlBarToolbarButtons) as? [Int] ?? []).compactMap(Preference.ToolBarButton.init(rawValue:))
    }
  }

  override var sectionViews: [NSView] {
    return [sectionAppearanceView, sectionWindowView, sectionOSCView, sectionOSDView, sectionThumbnailView, sectionPictureInPictureView, sectionAnimationsView]
  }

  private let toolbarSettingsSheetController = PrefOSCToolbarSettingsSheetController()

  @IBOutlet var sectionAppearanceView: NSView!
  @IBOutlet var sectionWindowView: NSView!
  @IBOutlet var sectionOSCView: NSView!
  @IBOutlet var sectionOSDView: NSView!
  @IBOutlet var sectionThumbnailView: NSView!
  @IBOutlet var sectionPictureInPictureView: NSView!
  @IBOutlet var sectionAnimationsView: NSView!

  @IBOutlet weak var themeMenu: NSMenu!
  @IBOutlet weak var oscPreviewImageView: NSImageView!
  @IBOutlet weak var oscPositionPopupButton: NSPopUpButton!
  @IBOutlet weak var oscToolbarStackView: NSStackView!

  @IBOutlet weak var windowSizeCheckBox: NSButton!
  @IBOutlet weak var windowSizeTypePopUpButton: NSPopUpButton!
  @IBOutlet weak var windowSizeValueTextField: NSTextField!
  @IBOutlet weak var windowSizeUnitPopUpButton: NSPopUpButton!
  @IBOutlet weak var windowSizeBox: NSBox!
  @IBOutlet weak var windowPosCheckBox: NSButton!
  @IBOutlet weak var windowPosXOffsetTextField: NSTextField!
  @IBOutlet weak var windowPosXUnitPopUpButton: NSPopUpButton!
  @IBOutlet weak var windowPosXAnchorPopUpButton: NSPopUpButton!
  @IBOutlet weak var windowPosYOffsetTextField: NSTextField!
  @IBOutlet weak var windowPosYUnitPopUpButton: NSPopUpButton!
  @IBOutlet weak var windowPosYAnchorPopUpButton: NSPopUpButton!
  @IBOutlet weak var windowPosBox: NSBox!

  @IBOutlet weak var windowResizeAlwaysButton: NSButton!
  @IBOutlet weak var windowResizeOnlyWhenOpenButton: NSButton!
  @IBOutlet weak var windowResizeNeverButton: NSButton!
  
  @IBOutlet weak var pipDoNothing: NSButton!
  @IBOutlet weak var pipHideWindow: NSButton!
  @IBOutlet weak var pipMinimizeWindow: NSButton!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    oscPositionPopupBtnAction(oscPositionPopupButton)
    oscToolbarStackView.wantsLayer = true
    updateOSCToolbarButtons()
    setupGeometryRelatedControls()
    setupResizingRelatedControls()
    setupPipBehaviorRelatedControls()

    let removeThemeMenuItemWithTag = { (tag: Int) in
      if let item = self.themeMenu.item(withTag: tag) {
        self.themeMenu.removeItem(item)
      }
    }
    if #available(macOS 10.14, *) {
      removeThemeMenuItemWithTag(Preference.Theme.mediumLight.rawValue)
      removeThemeMenuItemWithTag(Preference.Theme.ultraDark.rawValue)
    } else {
      removeThemeMenuItemWithTag(Preference.Theme.system.rawValue)
    }
  }

  @IBAction func oscPositionPopupBtnAction(_ sender: NSPopUpButton) {
    var name: NSImage.Name
    switch sender.selectedTag() {
    case 0:
      name = "osc_float"
    case 1:
      name = "osc_top"
    case 2:
      name = "osc_bottom"
    default:
      name = "osc_float"
    }
    oscPreviewImageView.image = NSImage(named: name)
  }

  @IBAction func updateGeometryValue(_ sender: AnyObject) {
    var geometry = ""
    // size
    if windowSizeCheckBox.state == .on {
      setSubViews(of: windowSizeBox, enabled: true)
      geometry += windowSizeTypePopUpButton.selectedTag() == SizeWidthTag ? "" : "x"
      geometry += windowSizeValueTextField.stringValue
      geometry += windowSizeUnitPopUpButton.selectedTag() == UnitPointTag ? "" : "%"
    } else {
      setSubViews(of: windowSizeBox, enabled: false)
    }
    // position
    if windowPosCheckBox.state == .on {
      setSubViews(of: windowPosBox, enabled: true)
      geometry += windowPosXAnchorPopUpButton.selectedTag() == SideLeftTag ? "+" : "-"
      geometry += windowPosXOffsetTextField.stringValue
      geometry += windowPosXUnitPopUpButton.selectedTag() == UnitPointTag ? "" : "%"
      geometry += windowPosYAnchorPopUpButton.selectedTag() == SideBottomTag ? "+" : "-"
      geometry += windowPosYOffsetTextField.stringValue
      geometry += windowPosYUnitPopUpButton.selectedTag() == UnitPointTag ? "" : "%"
    } else {
      setSubViews(of: windowPosBox, enabled: false)
    }
    Preference.set(geometry, for: .initialWindowSizePosition)
  }

  @IBAction func setupResizingRelatedControls(_ sender: NSButton) {
    Preference.set(sender.tag, for: .resizeWindowTiming)
  }

  @IBAction func setupPipBehaviorRelatedControls(_ sender: NSButton) {
    Preference.set(sender.tag, for: .windowBehaviorWhenPip)
  }

  @IBAction func customizeOSCToolbarAction(_ sender: Any) {
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

  private func updateOSCToolbarButtons() {
    oscToolbarStackView.views.forEach { oscToolbarStackView.removeView($0) }
    let buttons = PrefUIViewController.oscToolbarButtons
    for buttonType in buttons {
      let button = NSImageView()
      button.image = buttonType.image()
      button.translatesAutoresizingMaskIntoConstraints = false
      Utility.quickConstraints(["H:[btn(\(Preference.ToolBarButton.frameHeight))]", "V:[btn(\(Preference.ToolBarButton.frameHeight))]"], ["btn": button])
      oscToolbarStackView.addView(button, in: .trailing)
    }
  }

  private func setupGeometryRelatedControls() {
    let geometryString = Preference.string(for: .initialWindowSizePosition) ?? ""
    if let geometry = GeometryDef.parse(geometryString) {
      // size
      if let h = geometry.h {
        windowSizeCheckBox.state = .on
        setSubViews(of: windowSizeBox, enabled: true)
        windowSizeTypePopUpButton.selectItem(withTag: SizeHeightTag)
        let isPercent = h.hasSuffix("%")
        windowSizeUnitPopUpButton.selectItem(withTag: isPercent ? UnitPercentTag : UnitPointTag)
        windowSizeValueTextField.stringValue = isPercent ? String(h.dropLast()) : h
      } else if let w = geometry.w {
        windowSizeCheckBox.state = .on
        setSubViews(of: windowSizeBox, enabled: true)
        windowSizeTypePopUpButton.selectItem(withTag: SizeWidthTag)
        let isPercent = w.hasSuffix("%")
        windowSizeUnitPopUpButton.selectItem(withTag: isPercent ? UnitPercentTag : UnitPointTag)
        windowSizeValueTextField.stringValue = isPercent ? String(w.dropLast()) : w
      } else {
        windowSizeCheckBox.state = .off
        setSubViews(of: windowSizeBox, enabled: false)
      }
      // position
      if let x = geometry.x, let xSign = geometry.xSign, let y = geometry.y, let ySign = geometry.ySign {
        windowPosCheckBox.state = .on
        setSubViews(of: windowPosBox, enabled: true)
        let xIsPercent = x.hasSuffix("%")
        windowPosXAnchorPopUpButton.selectItem(withTag: xSign == "+" ? SideLeftTag : SideRightTag)
        windowPosXOffsetTextField.stringValue = xIsPercent ? String(x.dropLast()) : x
        windowPosXUnitPopUpButton.selectItem(withTag: xIsPercent ? UnitPercentTag : UnitPointTag)
        let yIsPercent = y.hasSuffix("%")
        windowPosYAnchorPopUpButton.selectItem(withTag: ySign == "+" ? SideBottomTag : SideTopTag)
        windowPosYOffsetTextField.stringValue = yIsPercent ? String(y.dropLast()) : y
        windowPosYUnitPopUpButton.selectItem(withTag: yIsPercent ? UnitPercentTag : UnitPointTag)
      } else {
        windowPosCheckBox.state = .off
        setSubViews(of: windowPosBox, enabled: false)
      }
    } else {
      windowSizeCheckBox.state = .off
      windowPosCheckBox.state = .off
      setSubViews(of: windowPosBox, enabled: false)
      setSubViews(of: windowSizeBox, enabled: false)
    }
  }

  private func setupResizingRelatedControls() {
    let resizeOption = Preference.enum(for: .resizeWindowTiming) as Preference.ResizeWindowTiming
    ([windowResizeNeverButton, windowResizeOnlyWhenOpenButton, windowResizeAlwaysButton] as [NSButton])
      .first { $0.tag == resizeOption.rawValue }?.state = .on
  }

  private func setupPipBehaviorRelatedControls() {
    let pipBehaviorOption = Preference.enum(for: .windowBehaviorWhenPip) as Preference.WindowBehaviorWhenPip
    ([pipDoNothing, pipHideWindow, pipMinimizeWindow] as [NSButton])
        .first { $0.tag == pipBehaviorOption.rawValue }?.state = .on
  }

  private func setSubViews(of view: NSBox, enabled: Bool) {
    view.contentView?.subviews.forEach { ($0 as? NSControl)?.isEnabled = enabled }
  }
}

@objc(ResizeTimingTransformer) class ResizeTimingTransformer: ValueTransformer {

  static override func allowsReverseTransformation() -> Bool {
    return false
  }

  static override func transformedValueClass() -> AnyClass {
    return NSNumber.self
  }

  override func transformedValue(_ value: Any?) -> Any? {
    guard let timing = value as? NSNumber else { return nil }
    return timing != 2
  }
}

