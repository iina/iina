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
    var expandedView: NSView?
    var isFirstItem = false
    var isLastItem = false

    var label: NSTextField!
    var mainView: NSView!
    var valueView: NSView!
    var valueStackView: NSStackView!
    var expandingStackView: NSStackView?
    var disclosureButton: NSButton!

    var controlSize: NSControl.ControlSize = .regular
    var labelLocalizationKey: SettingsLocalization.Key?

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
    var isExpandable: Bool { expandedView != nil }
    var isExpanded = false
    private var missingL10n = false

    var key: Preference.Key?

    private var backgroundView: ClickableView!

    init(title l10nKey: SettingsLocalization.Key? = nil) {
      self.labelLocalizationKey = l10nKey
      super.init(frame: NSRect())
      self.translatesAutoresizingMaskIntoConstraints = false
    }

    func populateViews() {
      backgroundView = ClickableView()
      backgroundView.showTopRoundCorner = isFirstItem
      backgroundView.showBottomRoundCorner = isLastItem
      backgroundView.translatesAutoresizingMaskIntoConstraints = false
      self.addSubview(backgroundView)
      backgroundView.fillSuperView()

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
      backgroundView.addSubview(label)

      disclosureButton = NSButton(frame: NSRect(x: 0, y: 0, width: 12, height: 12))
      disclosureButton.translatesAutoresizingMaskIntoConstraints = false
      disclosureButton.setButtonType(.pushOnPushOff)
      disclosureButton.bezelStyle = .disclosure
      disclosureButton.state = .off
      disclosureButton.title = ""
      disclosureButton.isHidden = true
      backgroundView.addSubview(disclosureButton)

      valueView = self.getValueView()
      valueView.translatesAutoresizingMaskIntoConstraints = false
      if let l10n = l10n {
        SettingsLocalization.injectContext(valueView, l10n)
      }

      valueStackView = NSStackView()
      valueStackView.translatesAutoresizingMaskIntoConstraints = false
      valueStackView.orientation = .horizontal
      valueStackView.addArrangedSubview(valueView)
      backgroundView.addSubview(valueStackView)

      valueStackView.paddingToSuperView(top: verticalPadding, bottom: verticalPadding, trailing: 8)
        .centerInSuperView(y: true)
      disclosureButton.paddingToSuperView(leading: 4)
        .centerInSuperView(y: true).spacingTo(view: label, trailing: 4)
      label.centerInSuperView(y: true).flexibleSpacingTo(view: valueStackView, trailing: 8)
        .flexiblePaddingToSuperView(top: verticalPadding, bottom: verticalPadding)

      prepareExpandableView()
    }

    func getValueView() -> NSView {
      return NSView()
    }

    func initBinding() {}

    override func viewDidMoveToWindow() {
      populateViews()
      if let key = key {
        initBinding()
      }
    }

    @discardableResult
    func withExpandingDetailView(_ view: NSView) -> Self {
      expandedView = view
      return self
    }

    private func prepareExpandableView() {
      guard let expandedView = expandedView else { return }
      expandedView.translatesAutoresizingMaskIntoConstraints = false
      if let l10n = l10n {
        SettingsLocalization.injectContext(expandedView, l10n)
      }

      disclosureButton.isHidden = false
      backgroundView.removeFromSuperview()
      backgroundView.clickable = true

      expandingStackView = NSStackView()
      expandingStackView!.orientation = .vertical
      expandingStackView!.spacing = 0
      expandingStackView?.translatesAutoresizingMaskIntoConstraints = false
      self.addSubview(expandingStackView!)
      expandingStackView!.fillSuperView()
      expandingStackView!.addArrangedSubview(backgroundView)
      expandingStackView!.addArrangedSubview(expandedView)
      expandedView.paddingToSuperView(leading: 8, trailing: 0)
      expandingStackView!.setVisibilityPriority(.notVisible, for: expandedView)
    }

    override func mouseUp(with event: NSEvent) {
      guard isExpandable else { return }

      isExpanded = !isExpanded
      if isExpanded {
        disclosureButton.state = .on
        expandingStackView!.setVisibilityPriority(.mustHold, for: expandedView!)
        backgroundView.enableRoundCorner = false
      } else {
        disclosureButton.state = .off
        expandingStackView!.setVisibilityPriority(.notVisible, for: expandedView!)
        backgroundView.enableRoundCorner = true
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

    override func getValueView() -> NSView {
      popupButton = NSPopUpButton()
      popupButton.translatesAutoresizingMaskIntoConstraints = false
      popupButton.isBordered = false
      return popupButton
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

    override func initBinding() {
      for (tag, _) in valueTypes {
        let title = l10n.localized(.init("\(key!.rawValue).items.\(tag)"))
        popupButton.addItem(withTitle: title)
        popupButton.lastItem?.tag = tag
      }
      popupButton.controlSize = controlSize
      popupButton.bind(.selectedTag, to: UserDefaults.standard, withKeyPath: key!.rawValue)
    }
  }

  class Switch: General {
    var nsSwitch: NSSwitch!

    override func getValueView() -> NSView {
      nsSwitch = NSSwitch()
      nsSwitch.controlSize = .mini
      return nsSwitch
    }

    func bindTo(_ key: Preference.Key) -> Self {
      self.key = key
      return self
    }

    override func initBinding() {
      nsSwitch.bind(.value, to: UserDefaults.standard, withKeyPath: key!.rawValue)
    }
  }
}


class ClickableView: NSView {
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
    layer?.backgroundColor = NSColor.highlightColor.withAlphaComponent(0.4).cgColor
  }

  override func mouseExited(with event: NSEvent) {
    layer?.backgroundColor = .clear
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
