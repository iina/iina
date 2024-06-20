//
//  SettingsItem.swift
//  iina
//
//  Created by Hechen Li on 6/22/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Cocoa

struct SettingsItem {
  class General: NSView, WithSettingsLocalizationContext {
    var detailView: NSView?
    var isFirstItem = false
    var isLastItem = false

    var label: NSTextField!
    var desc: NSTextField!
    var labelStackView: NSStackView!
    var image: NSImageView!
    var mainView: NSView!
    var valueStackView: NSStackView!
    var expandingStackView: NSStackView?
    var disclosureButton: NSButton!

    var controlSize: NSControl.ControlSize = .regular
    var labelLocalizationKey: SettingsLocalization.Key?
    var imageName: String?
    var hasDesc: Bool = false

    var l10n: SettingsLocalization.Context!

    var verticalPadding: CGFloat {
      switch controlSize {
      case .mini: return 6
      case .small: return 8
      case .regular: return 12
      case .large: return 14
      @unknown default: return 8
      }
    }
    var isExpandable = false
    var isExpanded = false
    private var missingL10n = false

    var key: Preference.Key?

    private var backgroundView: ClickableView!

    init(title l10nKey: SettingsLocalization.Key? = nil) {
      self.labelLocalizationKey = l10nKey
      super.init(frame: NSRect())
      self.translatesAutoresizingMaskIntoConstraints = false
    }

    public func hasDescription() -> Self {
      self.hasDesc = true
      return self
    }

    public func image(name: String) -> Self {
      self.imageName = name
      return self
    }

    private func populateViews() {
      backgroundView = ClickableView()
      backgroundView.showTopRoundCorner = isFirstItem
      backgroundView.showBottomRoundCorner = isLastItem
      backgroundView.translatesAutoresizingMaskIntoConstraints = false
      self.addSubview(backgroundView)
      backgroundView.padding(.all)

      if let labelLocalizationKey = labelLocalizationKey {
        label = NSTextField(labelWithString: l10n.localized(labelLocalizationKey))
      } else if let key = key {
        let l10nKey = labelLocalizationKey ?? .init("\(key.rawValue).label")
        label = NSTextField(labelWithString: l10n.localized(l10nKey))
      } else {
        label = NSTextField(labelWithString: "# Localization Missing")
      }
      label.translatesAutoresizingMaskIntoConstraints = false
      label.controlSize = controlSize
      label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      label.lineBreakMode = .byWordWrapping
      switch controlSize {
      case .small:
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 1)
      case .mini:
        label.font = NSFont.systemFont(ofSize: 9)
      case .large:
        label.font = NSFont.systemFont(ofSize: 15)
      default:
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
      }

      labelStackView = NSStackView()
      labelStackView.translatesAutoresizingMaskIntoConstraints = false
      labelStackView.orientation = .vertical
      labelStackView.spacing = 6
      labelStackView.alignment = .leading
      labelStackView.addArrangedSubview(label)

      backgroundView.addSubview(labelStackView)

      if hasDesc, let key = key {
        let descText = l10n.localized(.init("\(key.rawValue).desc"))
        desc = NSTextField(labelWithString: descText)
        desc.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        desc.textColor = .secondaryLabelColor
        labelStackView.addArrangedSubview(desc)
      }

      image = NSImageView()
      image.translatesAutoresizingMaskIntoConstraints = false
      if let imageName = imageName {
        image.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)!
      } else {
        image.isHidden = true
      }
      backgroundView.addSubview(image)

      disclosureButton = NonClickableButton(frame: NSRect(x: 0, y: 0, width: 12, height: 12))
      disclosureButton.translatesAutoresizingMaskIntoConstraints = false
      disclosureButton.setButtonType(.pushOnPushOff)
      disclosureButton.bezelStyle = .disclosure
      disclosureButton.state = .off
      disclosureButton.title = ""
      disclosureButton.isHidden = true
      disclosureButton.target = nil
      disclosureButton.action = nil
      backgroundView.addSubview(disclosureButton)

      let valueViews = self.getValueViews()
      valueViews.forEach { view in
        view.translatesAutoresizingMaskIntoConstraints = false
        if let l10n = l10n {
          SettingsLocalization.injectContext(view, l10n)
        }
      }

      valueStackView = NSStackView()
      valueStackView.translatesAutoresizingMaskIntoConstraints = false
      valueStackView.orientation = .horizontal
      valueStackView.alignment = .centerY
      valueViews.forEach {
        valueStackView.addArrangedSubview($0)
      }
      backgroundView.addSubview(valueStackView)

      // valueStackView.padding(.top(verticalPadding + 1), .trailing(8))
      valueStackView.padding(.vertical(verticalPadding), .trailing(8)).center(y: true)
      image.size(width: 16, height: 16).center(y: true).spacing(to: labelStackView, .trailing(8))
      disclosureButton.padding(.leading(16))
        .center(y: true).spacing(to: labelStackView, .trailing(4))
      labelStackView.center(y: true).flexibleSpacingTo(view: valueStackView, trailing: 8)
        .padding(.vertical(greaterThan: verticalPadding))

      prepareExpandableView()
    }

    func getValueViews() -> [NSView] {
      return []
    }

    func initBinding() {}

    override func viewDidMoveToWindow() {
      populateViews()
      initBinding()
    }

    @discardableResult
    func withExpandingDetailView(_ view: NSView) -> Self {
      isExpandable = true
      detailView = view
      return self
    }

    @discardableResult
    func withDetailView(_ view: NSView) -> Self {
      detailView = view
      return self
    }

    private func prepareExpandableView() {
      guard let detailView = detailView else { return }
      detailView.translatesAutoresizingMaskIntoConstraints = false
      if let l10n = l10n {
        SettingsLocalization.injectContext(detailView, l10n)
      }

      backgroundView.removeFromSuperview()
      backgroundView.clickable = isExpandable

      expandingStackView = NSStackView()
      expandingStackView!.orientation = .vertical
      expandingStackView!.spacing = 0
      expandingStackView?.translatesAutoresizingMaskIntoConstraints = false
      self.addSubview(expandingStackView!)
      expandingStackView!.padding(.all)
      expandingStackView!.addArrangedSubview(backgroundView)
      expandingStackView!.addArrangedSubview(detailView)
      detailView.padding(.leading(8), .trailing)
      if isExpandable {
        disclosureButton.isHidden = false
        expandingStackView!.setVisibilityPriority(.notVisible, for: detailView)
        detailView.alphaValue = 0
      } else {
        expandingStackView!.setVisibilityPriority(.mustHold, for: detailView)
      }
    }

    override func mouseUp(with event: NSEvent) {
      guard isExpandable else { return }

      isExpanded = !isExpanded
      if isExpanded {
        disclosureButton.state = .on
        expandingStackView!.setVisibilityPriority(.mustHold, for: detailView!)
        backgroundView.enableRoundCorner = false
        detailView?.alphaValue = 1
      } else {
        disclosureButton.state = .off
        expandingStackView!.setVisibilityPriority(.notVisible, for: detailView!)
        backgroundView.enableRoundCorner = true
        detailView?.alphaValue = 0
      }

      NSAnimationContext.runAnimationGroup({ context in
        context.duration = AccessibilityPreferences.adjustedDuration(0.25)
        context.allowsImplicitAnimation = true
        self.window?.layoutIfNeeded()
      }, completionHandler: nil)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }

  class PopupButton: General {
    private var popupButton: NSPopUpButton!
    private var valueTypes: [(Int, String)] = []
    private var customBinding = false
    private var customBindingBlock: ((NSPopUpButton) -> Void)?

    override func getValueViews() -> [NSView] {
      popupButton = NSPopUpButton()
      popupButton.translatesAutoresizingMaskIntoConstraints = false
      popupButton.bezelStyle = .flexiblePush
      popupButton.showsBorderOnlyWhileMouseInside = true
      return [popupButton]
    }

    func bindTo<T>(_ key: Preference.Key, ofType t: T.Type) -> Self
    where T: RawRepresentable & CaseIterable & InitializingFromKey, T.RawValue == Int
    {
      self.key = key
      for c in t.allCases {
        valueTypes.append((c.rawValue, String(describing: c)))
      }
      return self
    }

    func bindToCustom<T>(type t: T.Type, block: @escaping (NSPopUpButton) -> Void) -> Self
    where T: RawRepresentable & CaseIterable & InitializingFromKey, T.RawValue == Int
    {
      self.customBinding = true
      self.customBindingBlock = block
      for c in t.allCases {
        valueTypes.append((c.rawValue, String(describing: c)))
      }
      return self
    }

    override func initBinding() {
      guard let l10nKey = key?.rawValue ?? labelLocalizationKey?.rawValue else { return }
      for (tag, _) in valueTypes {
        let title = l10n.localized(.init("\(l10nKey).items.\(tag)"))
        popupButton.addItem(withTitle: title)
        popupButton.lastItem?.tag = tag
      }
      popupButton.controlSize = controlSize
      if let key = key {
        popupButton.bind(.selectedTag, to: UserDefaults.standard, withKeyPath: key.rawValue)
      } else if customBinding, let customBindingBlock = customBindingBlock {
        customBindingBlock(popupButton)
      }
    }
  }

  class Switch: General {
    var nsSwitch: NSSwitch!
    private var customBinding = false
    private var customBindingBlock: ((NSSwitch) -> Void)?

    override func getValueViews() -> [NSView] {
      nsSwitch = NSSwitch()
      nsSwitch.controlSize = .mini
      nsSwitch.action = #selector(switchChanged)
      nsSwitch.target = self
      return [nsSwitch]
    }

    func bindTo(_ key: Preference.Key) -> Self {
      self.key = key
      return self
    }

    func bindToCustom(block: @escaping (NSSwitch) -> Void) -> Self {
      self.customBinding = true
      self.customBindingBlock = block
      return self
    }

    override func initBinding() {
      if let key = key {
        nsSwitch.bind(.value, to: UserDefaults.standard, withKeyPath: key.rawValue)
      } else if customBinding, let customBindingBlock = customBindingBlock {
        customBindingBlock(nsSwitch)
      }
      DispatchQueue.main.async {
        self.switchChanged(self.nsSwitch)
      }
    }

    @objc func switchChanged(_ sender: NSSwitch) {
      guard let detailView = detailView else { return }
      let enableSubControls = sender.state == .on
      setSubControls(detailView, enabled: enableSubControls)
    }

    private func setSubControls(_ view: NSView, enabled: Bool) {
      if let control = view as? NSControl {
        control.isEnabled = enabled
      }
      for v in view.subviews {
        setSubControls(v, enabled: enabled)
      }
    }
  }

  class SwitchWithPopupButton: General {
    var keySwitch: Preference.Key?
    var keyPopup: Preference.Key?

    private var nsSwitch: NSSwitch!
    private var popupButton: NSPopUpButton!
    private var valueTypes: [(Int, String)] = []

    private var customBindingPopup = false
    private var customBindingBlockPopup: ((NSPopUpButton) -> Void)?
    private var customBindingSwitch = false
    private var customBindingBlockSwitch: ((NSSwitch) -> Void)?

    override func getValueViews() -> [NSView] {
      nsSwitch = NSSwitch()
      nsSwitch.controlSize = .mini
      nsSwitch.action = #selector(switchChanged)
      nsSwitch.target = self
      popupButton = NSPopUpButton()
      popupButton.translatesAutoresizingMaskIntoConstraints = false
      popupButton.bezelStyle = .flexiblePush
      popupButton.showsBorderOnlyWhileMouseInside = true
      return [popupButton, nsSwitch]
    }

    func labelKey(_ key: Preference.Key) -> Self {
      self.key = key
      return self
    }

    func bindSwitchTo(_ key: Preference.Key) -> Self {
      self.keySwitch = key
      return self
    }

    func bindPopupTo<T>(_ key: Preference.Key, ofType t: T.Type) -> Self
    where T: RawRepresentable & CaseIterable & InitializingFromKey, T.RawValue == Int
    {
      self.keyPopup = key
      for c in t.allCases {
        valueTypes.append((c.rawValue, String(describing: c)))
      }
      return self
    }

    func bindPopupToCustom<T>(type t: T.Type, block: @escaping (NSPopUpButton) -> Void) -> Self
    where T: RawRepresentable & CaseIterable & InitializingFromKey, T.RawValue == Int
    {
      self.customBindingPopup = true
      self.customBindingBlockPopup = block
      for c in t.allCases {
        valueTypes.append((c.rawValue, String(describing: c)))
      }
      return self
    }

    func bindSwitchToCustom(block: @escaping (NSSwitch) -> Void) -> Self {
      self.customBindingSwitch = true
      self.customBindingBlockSwitch = block
      return self
    }

    override func initBinding() {
      // switch
      if let key = keySwitch {
        nsSwitch.bind(.value, to: UserDefaults.standard, withKeyPath: key.rawValue)
      } else if customBindingSwitch, let customBindingBlock = customBindingBlockSwitch {
        customBindingBlock(nsSwitch)
      }
      // popup
      guard let l10nKey = keyPopup?.rawValue ?? labelLocalizationKey?.rawValue else { return }
      for (tag, _) in valueTypes {
        let title = l10n.localized(.init("\(l10nKey).items.\(tag)"))
        popupButton.addItem(withTitle: title)
        popupButton.lastItem?.tag = tag
      }
      popupButton.controlSize = controlSize
      if let key = keyPopup {
        popupButton.bind(.selectedTag, to: UserDefaults.standard, withKeyPath: key.rawValue)
      } else if customBindingPopup, let customBindingBlock = customBindingBlockPopup {
        customBindingBlock(popupButton)
      }
      DispatchQueue.main.async {
        self.switchChanged(self.nsSwitch)
      }
    }

    @objc func switchChanged(_ sender: NSSwitch) {
      let enableSubControls = sender.state == .on
      setSubControls(popupButton, enabled: enableSubControls)
      if let detailView = detailView {
        setSubControls(detailView, enabled: enableSubControls)
      }
    }

    private func setSubControls(_ view: NSView, enabled: Bool) {
      if let control = view as? NSControl {
        control.isEnabled = enabled
      }
      for v in view.subviews {
        setSubControls(v, enabled: enabled)
      }
    }
  }
}


fileprivate class ClickableView: NSView {
  var showBottomRoundCorner = false {
    didSet { setRoundCorners() }
  }

  var showTopRoundCorner = false {
    didSet { setRoundCorners() }
  }

  var enableRoundCorner = true {
    didSet { setRoundCorners() }
  }

  var clickable = false

  init() {
    super.init(frame: NSRect())
    wantsLayer = true
    layer?.cornerRadius = 7
  }

  private func setRoundCorners() {
    layer?.maskedCorners = []
    guard enableRoundCorner else { return }
    if showTopRoundCorner {
      layer?.maskedCorners.insert([.layerMinXMaxYCorner, .layerMaxXMaxYCorner])
    }
    if showBottomRoundCorner {
      layer?.maskedCorners.insert([.layerMinXMinYCorner, .layerMaxXMinYCorner])
    }
  }

  override func viewDidMoveToWindow() {
    guard clickable else { return }
    DispatchQueue.main.async { [self] in
      addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
  }

  override func mouseEntered(with event: NSEvent) {
    layer?.backgroundColor = NSColor.highlightColor.withAlphaComponent(0.2).cgColor
  }

  override func mouseExited(with event: NSEvent) {
    layer?.backgroundColor = .clear
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}


fileprivate class NonClickableButton: NSButton {
  override func mouseDown(with event: NSEvent) {}
  override func mouseUp(with event: NSEvent) {}
}
