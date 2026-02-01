//
//  SettingsItem.swift
//  iina
//
//  Created by Hechen Li on 6/22/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Cocoa

struct SettingsItem {
  class Base: NSView, WithSettingsLocalizationContext  {
    var l10n: SettingsLocalization.Context!

    var isFirstItem = false
    var isLastItem = false
    
    var controlSize: NSControl.ControlSize = .regular

    func setControlSize(_ label: NSTextField) {
      label.controlSize = controlSize
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
    }
  }

  class Custom: Base {
    var customView: NSView!

    init() {
      super.init(frame: NSRect())
      self.translatesAutoresizingMaskIntoConstraints = false
    }
    
    @MainActor required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
    
    func view(_ view: NSView) -> Self {
      self.customView = view
      return self
    }

    override func viewDidMoveToWindow() {
      guard window != nil else { return }
      customView.translatesAutoresizingMaskIntoConstraints = false
      self.addSubview(customView)
      customView.padding(.all)
    }
  }
  
  class LongInput: Base {
    let label: NSTextField
    let textField: NSTextField
    
    var iconView: NSImageView!
    var imageName: [String]?

    var key: Preference.Key?
    var hasDesc: Bool = false
    var descKey: SettingsLocalization.Key?

    init() {
      self.label = NSTextField(labelWithString: "")
      label.translatesAutoresizingMaskIntoConstraints = false
      self.textField = NSTextField()
      textField.translatesAutoresizingMaskIntoConstraints = false
      iconView = NSImageView()
      iconView.translatesAutoresizingMaskIntoConstraints = false

      super.init(frame: NSRect())
      self.translatesAutoresizingMaskIntoConstraints = false
    }
    
    @MainActor required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
    
    func bindTo(_ key: Preference.Key) -> Self {
      self.key = key
      return self
    }
    
    public func image(name: [String]) -> Self {
      self.imageName = name
      return self
    }

    func controlSize(_ size: NSControl.ControlSize) -> Self {
      self.controlSize = size
      return self
    }
    
    func hasDescription(content: SettingsLocalization.Key? = nil) -> Self {
      self.hasDesc = true
      self.descKey = content
      return self
    }

    override func viewDidMoveToWindow() {
      setControlSize(label)
      setControlSize(textField)
      
      if let key = key {
        label.stringValue = l10n.localized(.init("\(key.rawValue).label"))
        textField.bind(.value, to: UserDefaults.standard, withKeyPath: key.rawValue)
      }
      
      let labelStackView = NSStackView(views: [iconView, label])
      
      if let imageName, let symbol = NSImage.findSFSymbol(imageName) {
        iconView.image = symbol
        iconView.size(width: 24, height: 20)
      } else {
        iconView.isHidden = true
        label.padding(.leading(30))
      }
      
      labelStackView.translatesAutoresizingMaskIntoConstraints = false
      labelStackView.orientation = .horizontal
      labelStackView.spacing = 6

      let stackView = NSStackView(views: [labelStackView, textField])
      stackView.translatesAutoresizingMaskIntoConstraints = false
      stackView.orientation = .vertical
      stackView.alignment = .leading
      
      if hasDesc {
        let descKey =  descKey ?? .init("\(key!.rawValue).desc")
        let descLabel = NSTextField(labelWithString: l10n.localized(descKey))
        descLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        descLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(descLabel)
        descLabel.padding(.leading(30))
      }
      
      self.addSubview(stackView)
      
      textField.padding(.leading(30), .trailing)
      
      stackView.padding(.leading(6), .trailing(8), .vertical(8))
    }
  }


  class General: Base {
    var detailView: NSView?
    var valueView: NSView?
    var extraViews: [NSView] = []

    var label: NSTextField!
    var desc: NSTextField!
    var labelStackView: NSStackView!
    var image: NSImageView!
    var mainView: NSView!
    var valueStackView: NSStackView!
    var expandingStackView: NSStackView?
    var disclosureButton: NSButton!

    var labelLocalizationKey: SettingsLocalization.Key?
    var imageName: [String]?
    var hasDesc: Bool = false
    var descKey: SettingsLocalization.Key?
    var helpLink: String?

    var verticalPadding: CGFloat {
      switch controlSize {
      case .mini: return 6
      case .small: return 8
      case .regular: return 12
      case .large: return 14
      case .extraLarge: return 18
      @unknown default: return 8
      }
    }

    var isExpandable = false
    var isExpandableAndClickable: Bool = true
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

    public func hasDescription(content: SettingsLocalization.Key) -> Self {
      self.hasDesc = true
      self.descKey = content
      return self
    }

    public func image(name: String) -> Self {
      self.imageName = [name]
      return self
    }

    public func image(name: [String]) -> Self {
      self.imageName = name
      return self
    }

    func withHelpLink(_ link: String) -> Self {
      self.helpLink = link
      return self
    }

    func extraViews(_ extraViews: NSView...) -> Self {
      self.extraViews = extraViews
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
      setControlSize(label)

      let labelWithHelpButtonStackView = NSStackView()
      labelWithHelpButtonStackView.translatesAutoresizingMaskIntoConstraints = false
      labelWithHelpButtonStackView.orientation = .horizontal
      labelWithHelpButtonStackView.alignment = .centerY
      labelWithHelpButtonStackView.addArrangedSubview(label)
      if helpLink != nil {
        let helpButton = NSButton()
        helpButton.title = ""
        helpButton.translatesAutoresizingMaskIntoConstraints = false
        helpButton.bezelStyle = .helpButton
        helpButton.controlSize = .small
        helpButton.target = self
        helpButton.action = #selector(openHelpLink)
        labelWithHelpButtonStackView.addArrangedSubview(helpButton)
      }

      labelStackView = NSStackView()
      labelStackView.translatesAutoresizingMaskIntoConstraints = false
      labelStackView.orientation = .vertical
      labelStackView.spacing = 6
      labelStackView.alignment = .leading
      labelStackView.addArrangedSubview(labelWithHelpButtonStackView)

      backgroundView.addSubview(labelStackView)

      if hasDesc {
        let descText = l10n.localized(descKey ?? .init("\(key!.rawValue).desc"))
        desc = NSTextField(labelWithString: descText)
        desc.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        desc.textColor = .secondaryLabelColor
        desc.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        desc.lineBreakMode = .byWordWrapping
        labelStackView.addArrangedSubview(desc)
      }

      image = NSImageView()
      image.translatesAutoresizingMaskIntoConstraints = false
      if let imageName, let symbol = NSImage.findSFSymbol(imageName) {
        image.image = symbol
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
      extraViews.forEach {
        valueStackView.addArrangedSubview($0)
      }
      valueViews.forEach {
        valueStackView.addArrangedSubview($0)
      }
      backgroundView.addSubview(valueStackView)

      valueStackView.centerYAnchor
        .constraint(equalTo: backgroundView.topAnchor, constant: verticalPadding + 8).isActive = true
      valueStackView.padding(.trailing(8))
//       valueStackView.padding(.top(verticalPaddingFixed), .trailing(8))
//      valueStackView.padding(.vertical(verticalPadding), .trailing(8)).center(y: true)
      image.size(width: 24, height: 20).spacing(to: labelStackView, .trailing(6))
        .padding(.top(11))
      disclosureButton.padding(.trailing(12)).center(y: true)
      labelStackView.center(y: true).flexibleSpacingTo(view: valueStackView, trailing: 8)
        .padding(.leading(36), .vertical(greaterThan: verticalPadding))

      prepareExpandableView()
    }

    func getValueViews() -> [NSView] {
      if let valueView = valueView {
        return [valueView]
      }
      return []
    }

    func initBinding() {}

    override func viewDidMoveToWindow() {
      guard window != nil else { return }
      populateViews()
      initBinding()
    }

    @discardableResult
    func withExpandingDetailView(@SettingsSubListBuilder _ view: () -> NSView) -> Self {
      isExpandable = true
      detailView = view()
      return self
    }

    @discardableResult
    func withExpandingDetailView(_ view: NSView) -> Self {
      isExpandable = true
      detailView = view
      return self
    }

    @discardableResult
    func withDetailView(@SettingsSubListBuilder _ view: () -> NSView) -> Self {
      detailView = view()
      return self
    }

    @discardableResult
    func withDetailView(_ view: NSView) -> Self {
      detailView = view
      return self
    }

    @discardableResult
    final func withValueView(_ view: NSView) -> Self {
      valueView = view
      return self
    }

    private func prepareExpandableView() {
      guard let detailView = detailView else { return }
      detailView.translatesAutoresizingMaskIntoConstraints = false
      if let l10n = l10n {
        SettingsLocalization.injectContext(detailView, l10n)
      }

      backgroundView.removeFromSuperview()
      backgroundView.clickable = isExpandable && isExpandableAndClickable

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
        if isExpandableAndClickable {
          disclosureButton.isHidden = false
        }
        expandingStackView!.setVisibilityPriority(.notVisible, for: detailView)
        detailView.alphaValue = 0
      } else {
        expandingStackView!.setVisibilityPriority(.mustHold, for: detailView)
      }
    }

    override func mouseUp(with event: NSEvent) {
      guard isExpandable && isExpandableAndClickable else { return }

      toggleExpandable()
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    @objc private func openHelpLink(_ sender: NSButton!) {
      if let link = helpLink, let url = URL(string: link) {
        NSWorkspace.shared.open(url)
      }
    }

    func toggleExpandable(_ setValue: Bool? = nil) {
      if let setValue = setValue {
        isExpanded = setValue
      } else {
        isExpanded.toggle()
      }

      if isExpanded {
        disclosureButton.state = .on
        expandingStackView!.setVisibilityPriority(.mustHold, for: detailView!)
        backgroundView.enableRoundCorner = false
      } else {
        disclosureButton.state = .off
        expandingStackView!.setVisibilityPriority(.notVisible, for: detailView!)
        backgroundView.enableRoundCorner = true
      }

      let duration = AccessibilityPreferences.adjustedDuration(0.25)
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = duration
        context.allowsImplicitAnimation = true
        self.window?.layoutIfNeeded()
      }, completionHandler: nil)

      DispatchQueue.main.asyncAfter(deadline: .now() + duration / 3) {
        NSAnimationContext.runAnimationGroup({ context in
          context.duration = duration
          self.detailView?.alphaValue = self.isExpanded ? 1 : 0
        }, completionHandler: nil)
      }
    }
  }

  class PopupButton: General {
    private var popupButton: NSPopUpButton!
    private var valueTypes: [(Int, String)] = []
    private var customBinding = false
    private var customBindingBlock: ((NSPopUpButton) -> Void)?
    private var tagForDisabled: Int?

    override func getValueViews() -> [NSView] {
      popupButton = NSPopUpButton()
      popupButton.translatesAutoresizingMaskIntoConstraints = false
      popupButton.bezelStyle = .flexiblePush
      if #available(macOS 26, *) {
        popupButton.showsBorderOnlyWhileMouseInside = false
      } else {
        popupButton.showsBorderOnlyWhileMouseInside = true
      }
      popupButton.target = self
      popupButton.action = #selector(popupChanged)
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

    func disableSubListOnTag(_ tag: Int) -> Self {
      self.tagForDisabled = tag
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
      DispatchQueue.main.async {
        self.popupChanged(self.popupButton)
      }
    }

    @objc func popupChanged(_ sender: NSPopUpButton) {
      guard let detailView = detailView, let tag = tagForDisabled else { return }

      let enabled = sender.selectedTag() != tag
      setSubControls(detailView, enabled: enabled)
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

    func bindExpandableView() -> Self {
      isExpandableAndClickable = false
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

      let enabled = sender.state == .on
      if !isExpandableAndClickable {
        toggleExpandable(enabled)
      }
      setSubControls(detailView, enabled: enabled)
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
      if #available(macOS 26, *) {
        popupButton.showsBorderOnlyWhileMouseInside = false
      } else {
        popupButton.showsBorderOnlyWhileMouseInside = true
      }
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

  class Input: General {
    private var textField: NSTextField!
    private var trailingLabel: SettingsLocalization.Key?
    private var customBinding = false
    private var customBindingBlock: ((NSTextField) -> Void)?
    private var isLongText = false

    private var cachedStepperValue: Double?
    private var stepper: NSStepper?

    init(title l10nKey: SettingsLocalization.Key? = nil, step: Double = 1) {
      if (step != 0) {
        let stepper = NSStepper()
        stepper.increment = step
        stepper.minValue = -1e10
        stepper.maxValue = 1e10
        stepper.valueWraps = false
        cachedStepperValue = stepper.doubleValue
        self.stepper = stepper
      }
      super.init(title: l10nKey)
      if let stepper {
        stepper.target = self
        stepper.action = #selector(stepperValueChanged)
        stepper.controlSize = controlSize
      }
    }

    @MainActor required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    func trailingLabel(_ key: SettingsLocalization.Key) -> Self {
      self.trailingLabel = key
      return self
    }

    @objc func stepperValueChanged(sender: NSStepper) {
      guard let cachedStepperValue else { return }
      if cachedStepperValue < sender.doubleValue {
        textField.doubleValue += sender.increment
      } else {
        textField.doubleValue -= sender.increment
      }
      self.cachedStepperValue = sender.doubleValue
    }

    override func getValueViews() -> [NSView] {
      textField = NSTextField()
      textField.translatesAutoresizingMaskIntoConstraints = false
      textField.controlSize = controlSize
      textField.bezelStyle = .roundedBezel
      textField.size(width: 64)
      setControlSize(textField)
      let stack = NSStackView(views: [textField])
      if let stepper {
        stack.addView(stepper, in: .trailing)
        stack.spacing = 2
      }
      if let trailingLabel = trailingLabel {
        let label = NSTextField(labelWithString: l10n.localized(trailingLabel))
        setControlSize(label)
        return [stack, label]
      } else {
        return [stack]
      }
    }

    func bindTo(_ key: Preference.Key) -> Self {
      self.key = key
      return self
    }

    func bindToCustom(block: @escaping (NSTextField) -> Void) -> Self {
      self.customBinding = true
      self.customBindingBlock = block
      return self
    }

    override func initBinding() {
      if let key = key {
        textField.bind(.value, to: UserDefaults.standard, withKeyPath: key.rawValue)
      } else if customBinding, let customBindingBlock = customBindingBlock {
        customBindingBlock(textField)
      }
    }
  }

  class SwitchWithInput: General {
    var keySwitch: Preference.Key?
    var keyInput: Preference.Key?

    private var nsSwitch: NSSwitch!
    private var valueTypes: [(Int, String)] = []
    private var textField: NSTextField!
    private var trailingLabel: SettingsLocalization.Key?

    private var customBindingInput = false
    private var customBindingBlockInput: ((NSTextField) -> Void)?
    private var customBindingSwitch = false
    private var customBindingBlockSwitch: ((NSSwitch) -> Void)?

    override func getValueViews() -> [NSView] {
      nsSwitch = NSSwitch()
      nsSwitch.controlSize = .mini
      nsSwitch.action = #selector(switchChanged)
      nsSwitch.target = self
      textField = NSTextField()
      textField.translatesAutoresizingMaskIntoConstraints = false
      textField.controlSize = controlSize
      textField.bezelStyle = .roundedBezel
      textField.size(width: 64)
      setControlSize(textField)
      if let trailingLabel = trailingLabel {
        let label = NSTextField(labelWithString: l10n.localized(trailingLabel))
        setControlSize(label)
        return [textField, label, nsSwitch]
      } else {
        return [textField, nsSwitch]
      }
    }

    func labelKey(_ key: Preference.Key) -> Self {
      self.key = key
      return self
    }

    func trailingLabel(_ key: SettingsLocalization.Key) -> Self {
      self.trailingLabel = key
      return self
    }

    func bindSwitchTo(_ key: Preference.Key) -> Self {
      self.keySwitch = key
      return self
    }

    func bindInputTo(_ key: Preference.Key) -> Self {
      self.keyInput = key
      return self
    }

    func bindInputToCustom(block: @escaping (NSTextField) -> Void) -> Self {
      self.customBindingInput = true
      self.customBindingBlockInput = block
      return self
    }

    override func initBinding() {
      // switch
      if let key = keySwitch {
        nsSwitch.bind(.value, to: UserDefaults.standard, withKeyPath: key.rawValue)
      } else if customBindingSwitch, let customBindingBlock = customBindingBlockSwitch {
        customBindingBlock(nsSwitch)
      }
      // input
      if let key = keyInput {
        textField.bind(.value, to: UserDefaults.standard, withKeyPath: key.rawValue)
      } else if customBindingInput, let customBindingBlock = customBindingBlockInput {
        customBindingBlock(textField)
      }
      DispatchQueue.main.async {
        self.switchChanged(self.nsSwitch)
      }
    }

    @objc func switchChanged(_ sender: NSSwitch) {
      let enableSubControls = sender.state == .on
      setSubControls(textField, enabled: enableSubControls)
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
  private var backgroundColor: CGColor?

  init() {
    super.init(frame: NSRect())
    wantsLayer = true
    layer?.cornerRadius = SettingsPage.corderRadius
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
    if backgroundColor == nil {
      viewDidChangeEffectiveAppearance()
    }
    layer?.backgroundColor = backgroundColor
  }

  override func mouseExited(with event: NSEvent) {
    layer?.backgroundColor = .clear
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func viewDidChangeEffectiveAppearance() {
    backgroundColor = if #available(macOS 26, *) {
      if effectiveAppearance.isDark {
        NSColor.highlightColor.withAlphaComponent(0.1).cgColor
      } else {
        NSColor.black.withAlphaComponent(0.08).cgColor
      }
    } else {
      NSColor.highlightColor.withAlphaComponent(0.2).cgColor
    }
  }
}


fileprivate class NonClickableButton: NSButton {
  override func mouseDown(with event: NSEvent) {}
  override func mouseUp(with event: NSEvent) {}
}


class SettingsAccessory {
  /// A Base class for customized controls.
  class Base: WithSettingsLocalizationContext {
    var l10n: SettingsLocalization.Context!
    let view: NSView
    lazy var ui: SettingsUIHelper = SettingsUIHelper(l10n)

    init(l10n: SettingsLocalization.Context) {
      self.l10n = l10n
      self.view = NSView()
      self.view.translatesAutoresizingMaskIntoConstraints = false
    }

    func makeLabel(_ key: SettingsLocalization.Key, isSmall: Bool = true) -> NSTextField {
      let label = NSTextField(labelWithString: l10n.localized(key))
      label.translatesAutoresizingMaskIntoConstraints = false
      if isSmall {
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
      }
      return label
    }
    
    func makeButton(_ key: SettingsLocalization.Key) -> NSButton {
      let btn = NSButton(title: l10n.localized(key), target: nil, action: nil)
      btn.translatesAutoresizingMaskIntoConstraints = false
      return btn
    }

    func makeColorWell() -> NSColorWell {
      let colorWell = NSColorWell()
      colorWell.translatesAutoresizingMaskIntoConstraints = false
      if #available(macOS 13.0, *) {
        colorWell.colorWellStyle = .expanded
      }
      colorWell.size(height: 24)
      return colorWell
    }

    func makeInput(_ key: Preference.Key, fixedAlignmentRect: Bool = true, isFixedSize: Bool = true) -> NSTextField {
      let input = fixedAlignmentRect ? TextFieldWithFixedAlignmentRect() : NSTextField()
      input.translatesAutoresizingMaskIntoConstraints = false
      input.bezelStyle = .roundedBezel
      input.bind(.value, to: UserDefaults.standard, withKeyPath: key.rawValue)
      if isFixedSize {
        input.size(width: 48, height: 25)
      }
      return input
    }

    func makeStackView(_ views: [NSView], orientation: NSUserInterfaceLayoutOrientation = .horizontal) -> NSStackView {
      let stackView = NSStackView(views: views)
      stackView.translatesAutoresizingMaskIntoConstraints = false
      stackView.orientation = orientation
      stackView.alignment = orientation == .horizontal ? .centerY : .centerX
      stackView.spacing = 8
      return stackView
    }
  }
  
  fileprivate class TextFieldWithFixedAlignmentRect: NSTextField {
    override func frame(forAlignmentRect alignmentRect: NSRect) -> NSRect {
      return alignmentRect
    }
  }
  
  class Selection: NSView, WithSettingsLocalizationContext {
    var l10n: SettingsLocalization.Context!

    private class ClickableBox: NSBox {
      var listener: (() -> Void)?

      override func mouseDown(with event: NSEvent) {
        listener?()
      }
    }

    let view: NSBox
    let stackView: NSStackView
    var key: Preference.Key? = nil
    var items: [Int: NSBox] = [:]
    var customtransformer: (((Int) -> Any), (Any?) -> Int)?
    var localizationKey: Preference.Key?

    private var valueTypes: [(Int, String)] = []
    @objc private var selectedValue: Int = 0 {
      didSet {
        print(selectedValue)
        updateSelection()
      }
    }

    init(l10nKey: Preference.Key? = nil, topPadding: CGFloat = -4) {
      self.view = NSBox()
      self.stackView = NSStackView()
      self.localizationKey = l10nKey
      super.init(frame: NSRect())
      self.translatesAutoresizingMaskIntoConstraints = false

      view.translatesAutoresizingMaskIntoConstraints = false
      view.boxType = .custom
      view.borderWidth = 0
      view.titlePosition = .noTitle
      view.contentView = stackView

      stackView.translatesAutoresizingMaskIntoConstraints = false
      stackView.orientation = .vertical
      stackView.spacing = 4
      stackView.setHuggingPriority(.defaultLow, for: .horizontal)
      stackView.padding(.top(-4), .bottom(0), .horizontal)
    }

    @MainActor required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    func order(_ order: [Int]) -> Self {
      if valueTypes.isEmpty {
        fatalError("must call bindTo() before calling order()")
      }
      valueTypes = valueTypes.sorted { order.firstIndex(of: $0.0)! < order.firstIndex(of: $1.0)! }
      return self
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

    func customTransformer(_ transformer: ( ((Int) -> Any), (Any?) -> Int)) -> Self {
      self.customtransformer = transformer
      return self
    }

    private func initBinding() {
      guard let key = key else { return }
      if let transformer = customtransformer {
        selectedValue = transformer.1(Preference.value(for: key))
      } else {
        selectedValue = Preference.integer(for: key)
      }
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: [.new], context: nil)
    }

    private func updateSelection() {
      let selectedItem = items[selectedValue]!
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.1
        items.values.forEach {
          $0.borderColor = .separatorColor
          $0.borderWidth = 1
          $0.fillColor = .gray.withAlphaComponent(0.1)
        }
        selectedItem.animator().borderColor = .controlAccentColor
        selectedItem.animator().borderWidth = 2
        selectedItem.animator().fillColor = .controlAccentColor.withAlphaComponent(0.1)
      }
    }

    deinit {
      guard let key = key else { return }
      ObjcUtils.silenced {
        UserDefaults.standard.removeObserver(self, forKeyPath: key.rawValue)
      }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
      guard let change = change else { return }

      if let transformer = customtransformer {
        selectedValue = transformer.1(change[.newKey])
      } else {
        if let newValue = change[.newKey] as? Int {
          selectedValue = newValue
        }
      }
    }

    override func viewDidMoveToWindow() {
      guard window != nil, stackView.arrangedSubviews.isEmpty else { return }

      guard let l10nKey = localizationKey?.rawValue ?? key?.rawValue else { return }
      for (tag, _) in valueTypes {
        let title = l10n.localized(.init("\(l10nKey).items.\(tag)"))
        let desc = l10n.localized(.init("\(l10nKey).items.\(tag).desc"))
        let box = ClickableBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.boxType = .custom
        box.titlePosition = .noTitle
        let itemTitle = NSTextField(labelWithString: title)
        let itemDesc = NSTextField(labelWithString: desc)
        itemDesc.textColor = .secondaryLabelColor
        itemDesc.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        itemDesc.lineBreakMode = .byWordWrapping
        itemDesc.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let itemStackView = NSStackView(views: [itemTitle, itemDesc])
        itemStackView.translatesAutoresizingMaskIntoConstraints = false
        itemStackView.spacing = 2
        itemStackView.orientation = .vertical
        itemStackView.alignment = .leading
        itemStackView.setHuggingPriority(.init(100), for: .horizontal)
        box.contentView = itemStackView
        box.cornerRadius = 6
        box.listener = { [unowned self] in
          if let transformer = self.customtransformer {
            Preference.set(transformer.0(tag), for: self.key!)
          } else {
            Preference.set(tag, for: self.key!)
          }
        }
        items[tag] = box
        itemStackView.padding(.vertical(6), .horizontal(12))
        stackView.addArrangedSubview(box)
      }

      self.addSubview(view)
      view.padding(.top, .leading(SettingsSubListView.padding), .trailing(8), .bottom(8))

      initBinding()
    }
  }

  class LanguageSelector: NSView, WithSettingsLocalizationContext {
    var l10n: SettingsLocalization.Context!

    private var key: Preference.Key? = nil
    private var hasDesc = false
    private let stackView: NSStackView
    private let audioLangTokenField: LanguageTokenField
    
    init() {
      self.audioLangTokenField = .init()
      self.stackView = NSStackView()
      super.init(frame: NSRect())

      audioLangTokenField.translatesAutoresizingMaskIntoConstraints = false
      audioLangTokenField.bezelStyle = .roundedBezel
      audioLangTokenField.target = self
      audioLangTokenField.action = #selector(preferredLanguageAction(_:))
      
      stackView.translatesAutoresizingMaskIntoConstraints = false
      stackView.orientation = .vertical
      stackView.addArrangedSubview(audioLangTokenField)
      self.addSubview(stackView)

      stackView.padding(.top(-4), .leading(SettingsSubListView.padding), .trailing(8), .bottom(8))
    }

    @MainActor required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    func bind(to key: Preference.Key?) -> Self {
      self.key = key
      return self
    }
    
    func hasDescription() -> Self {
      self.hasDesc = true
      return self
    }

    override func viewDidMoveToWindow() {
      guard window != nil else { return }

      audioLangTokenField.awakeFromNib()
      if let key = key {
        audioLangTokenField.commaSeparatedValues = Preference.string(for: key) ?? ""
        if hasDesc {
          let descLabel = NSTextField(labelWithString: l10n.localized(.init("\(key.rawValue).desc")))
          descLabel.makeMultiLine()
          descLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
          descLabel.textColor = .secondaryLabelColor
          stackView.addArrangedSubview(descLabel)
        }
      }
      
    }

    @objc func preferredLanguageAction(_ sender: LanguageTokenField) {
      guard let key = key else { return }
      let csv = sender.commaSeparatedValues
      if Preference.string(for: key) != csv {
        Logger.log("Saving \(key.rawValue): \"\(csv)\"", level: .verbose)
        Preference.set(csv, for: key)
      }
    }
  }
}
