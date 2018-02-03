//
//  PrefUIViewController.swift
//  iina
//
//  Created by lhc on 25/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import MASPreferences

fileprivate let SizeWidthTag = 0
fileprivate let SizeHeightTag = 1
fileprivate let UnitPointTag = 0
fileprivate let UnitPercentTag = 1
fileprivate let SideLeftTag = 0
fileprivate let SideRightTag = 1
fileprivate let SideTopTag = 0
fileprivate let SideBottomTag = 1

@objcMembers
class PrefUIViewController: NSViewController, MASPreferencesViewController {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefUIViewController")
  }

  var viewIdentifier: String = "PrefUIViewController"

  var toolbarItemImage: NSImage? {
    get {
      return #imageLiteral(resourceName: "toolbar_play")
    }
  }

  var toolbarItemLabel: String? {
    get {
      view.layoutSubtreeIfNeeded()
      return NSLocalizedString("preference.ui", comment: "UI")
    }
  }

  var hasResizableWidth: Bool = false
  var hasResizableHeight: Bool = false

  private let toolbarSettingsSheetController = PrefOSCToolbarSettingsSheetController()

  @IBOutlet weak var oscPreviewImageView: NSImageView!
  @IBOutlet weak var oscPositionPopupButton: NSPopUpButton!
  @IBOutlet weak var oscToolbarStackView: NSStackView!
  @IBOutlet weak var thumbCacheSizeLabel: NSTextField!
  
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


  override func viewDidLoad() {
    super.viewDidLoad()
    oscPositionPopupBtnAction(oscPositionPopupButton)
    oscToolbarStackView.wantsLayer = true
    oscToolbarStackView.layer?.backgroundColor = NSColor(calibratedWhite: 0.5, alpha: 0.2).cgColor
    oscToolbarStackView.layer?.cornerRadius = 4
    updateOSCToolbarButtons()
    setupGeometryRelatedControls()
    setupResizingRelatedControls()
  }

  @IBAction func oscPositionPopupBtnAction(_ sender: NSPopUpButton) {
    var name: String
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
    oscPreviewImageView.image = NSImage(named: NSImage.Name(rawValue: name))
  }

  @IBAction func clearCacheBtnAction(_ sender: AnyObject) {
    if Utility.quickAskPanel("clear_cache") {
      try? FileManager.default.removeItem(atPath: Utility.thumbnailCacheURL.path)
      Utility.createDirIfNotExist(url: Utility.thumbnailCacheURL)
      updateThumbnailCacheStat()
      Utility.showAlert("clear_cache.success", style: .informational)
    }
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

  @IBAction func customizeOSCToolbarAction(_ sender: Any) {
    view.window?.beginSheet(toolbarSettingsSheetController.window!) { response in
      return
    }
  }

  override func viewDidAppear() {
    DispatchQueue.main.async {
      self.updateThumbnailCacheStat()
    }
  }

  private func updateOSCToolbarButtons() {
    let buttons = (Preference.array(for: .controlBarToolbarButtons) as? [Int] ?? []).flatMap(Preference.ToolBarButton.init(rawValue:))
    for buttonType in buttons {
      let button = NSImageView()
      button.image = buttonType.image()
      let buttonWidth = buttons.count == 5 ? "20" : "24"
      oscToolbarStackView.addView(button, in: .trailing)
      Utility.quickConstraints(["H:[btn(\(buttonWidth))]", "V:[btn(24)]"], ["btn": button])
    }

  }

  private func updateThumbnailCacheStat() {
    thumbCacheSizeLabel.stringValue = FileSize.format(CacheManager.shared.getCacheSize(), unit: .b)
  }

  private func setupGeometryRelatedControls() {
    let geometryString = Preference.string(for: .initialWindowSizePosition) ?? ""
    if let geometry = GeometryDef.parse(geometryString) {
      // size
      if let h = geometry.h {
        windowSizeCheckBox.state = .on
        setSubViews(of: windowPosBox, enabled: true)
        windowSizeTypePopUpButton.selectItem(withTag: SizeHeightTag)
        let isPercent = h.hasSuffix("%")
        windowSizeUnitPopUpButton.selectItem(withTag: isPercent ? UnitPercentTag : UnitPointTag)
        windowSizeValueTextField.stringValue = isPercent ? String(h.dropLast()) : h
      } else if let w = geometry.w {
        windowSizeCheckBox.state = .on
        setSubViews(of: windowPosBox, enabled: true)
        windowSizeTypePopUpButton.selectItem(withTag: SizeWidthTag)
        let isPercent = w.hasSuffix("%")
        windowSizeUnitPopUpButton.selectItem(withTag: isPercent ? UnitPercentTag : UnitPointTag)
        windowSizeValueTextField.stringValue = isPercent ? String(w.dropLast()) : w
      } else {
        windowSizeCheckBox.state = .off
        setSubViews(of: windowPosBox, enabled: false)
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

  private func setSubViews(of view: NSBox, enabled: Bool) {
    view.contentView?.subviews.forEach { ($0 as? NSControl)?.isEnabled = enabled }
  }
}
