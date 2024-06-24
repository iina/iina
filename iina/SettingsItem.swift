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
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
      case .mini:
        label.font = NSFont.systemFont(ofSize: 9)
      case .large:
        label.font = NSFont.systemFont(ofSize: 15)
      default:
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
      }
      backgroundView.addSubview(label)

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

      valueStackView.padding(.vertical(verticalPadding), .trailing(8))
        .center(y: true)
      disclosureButton.padding(.leading(4))
        .center(y: true).spacing(to: label, .trailing(4))
      label.center(y: true).flexibleSpacingTo(view: valueStackView, trailing: 8)
        .padding(.vertical(greaterThan: verticalPadding))

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
      expandingStackView!.padding(.all)
      expandingStackView!.addArrangedSubview(backgroundView)
      expandingStackView!.addArrangedSubview(expandedView)
      expandedView.padding(.leading(8), .trailing)
      expandingStackView!.setVisibilityPriority(.notVisible, for: expandedView)
      expandedView.alphaValue = 0
    }

    override func mouseUp(with event: NSEvent) {
      guard isExpandable else { return }

      isExpanded = !isExpanded
      if isExpanded {
        disclosureButton.state = .on
        expandingStackView!.setVisibilityPriority(.mustHold, for: expandedView!)
        backgroundView.enableRoundCorner = false
        expandedView?.alphaValue = 1
      } else {
        disclosureButton.state = .off
        expandingStackView!.setVisibilityPriority(.notVisible, for: expandedView!)
        backgroundView.enableRoundCorner = true
        expandedView?.alphaValue = 0
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
      popupButton.bezelStyle = .flexiblePush
      popupButton.showsBorderOnlyWhileMouseInside = true
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
    layer?.backgroundColor = NSColor.highlightColor.withAlphaComponent(0.4).cgColor
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
