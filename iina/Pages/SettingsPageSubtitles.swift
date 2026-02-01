//
//  SettingsPageSubtitles.swift
//  iina
//
//  Created by Hechen Li on 6/16/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Foundation

class SettingsPageSubtitles: SettingsPage {
  override var title: String {
    return NSLocalizedString("preference.subtitle", comment: "Subtitles")
  }

  override var image: NSImage {
    return makeSymbol("captions.bubble", fallbackImage: "pref_sub")
  }

  override var localizationTable: String {
    "SettingsSubtitesLocalizable"
  }

  private lazy var autoLoadPriorityInput: AdvancedInput = AdvancedInput(l10n: localizationContext)
  private lazy var autoLoadSearchDirInput: AdvancedInput = AdvancedInput(l10n: localizationContext)
  private lazy var subtitlesASSView: SubtitlesASSView = SubtitlesASSView(l10n: localizationContext)
  private lazy var subtitlesFontView: SubtitlesFontView = SubtitlesFontView(l10n: localizationContext)
  private lazy var subtitlesColorView: SubtitlesColorView = SubtitlesColorView(l10n: localizationContext)
  private lazy var subtitlesBorderView: SubtitlesBorderView = SubtitlesBorderView(l10n: localizationContext)
  private lazy var subtitlesShadowView: SubtitlesShadowView = SubtitlesShadowView(l10n: localizationContext)
  private lazy var subtitlesMarginView: SubtitlesMarginView = SubtitlesMarginView(l10n: localizationContext)
  private lazy var subtitlesAlignView: SubtitlesAlignView = SubtitlesAlignView(l10n: localizationContext)
  private lazy var subtitlesEncodingView: SubtitlesEncodingView = SubtitlesEncodingView(l10n: localizationContext)
  private lazy var subtitleSourceView: SubtitleSourceView = SubtitleSourceView(l10n: localizationContext)

  override func content() -> NSView {
    return sections {
      sectionAutoLoad()
      sectionASS()
      sectionText()
      sectionPosition()
      sectionOnlineSubtitles()
      sectionOther()
    }
  }

  private func sectionAutoLoad() -> [NSView] {
    return section {
      SettingsListView(title: .text_AutoLoad) {
        SettingsItem.PopupButton()
          .image(name: ["bolt.badge.automatic", "bolt.badge.a"])
          .bindTo(.subAutoLoadIINA, ofType: Preference.IINAAutoLoadAction.self)
        SettingsItem.General(title: .text_Advanced)
          .withExpandingDetailView {
            SettingsItem.General(title: .text_SubtitlesHavePriorityWhenFilename)
              .withDetailView(autoLoadPriorityInput.view)
            SettingsItem.General(title: .text_AlsoSearchSubtitlesInFollowing)
              .withDetailView(autoLoadSearchDirInput.view)
          }
      }
    }
  }

  private func sectionASS() -> [NSView] {
    return section {
      SettingsListView(title: .text_ASSSubtitles) {
        SettingsItem.General(title: .text_OverrideLevel)
          .image(name: "pencil.slash")
          .withHelpLink("https://mpv.io/manual/stable/#options-sub-ass-override")
          .withValueView(subtitlesASSView.segmentControl)
          .withDetailView(subtitlesASSView.view)
      }
    }
  }

  private func sectionText() -> [NSView] {
    return section {
      SettingsListView(title: .text_TextSubtitles) {
        SettingsItem.General(title: .text_Font)
          .image(name: "textformat")
          .withValueView(subtitlesFontView.view)
        SettingsItem.General(title: .text_Color)
          .image(name: "paintpalette")
          .withValueView(subtitlesColorView.view)
        SettingsItem.General(title: .text_Border)
          .image(name: "rectangle.dashed")
          .withValueView(subtitlesBorderView.view)
      }

      SettingsListView {
        SettingsItem.General(title: .text_Shadow)
          .image(name: ["lightspectrum.horizontal", "lightbulb"])
          .withValueView(subtitlesShadowView.view)
        SettingsItem.General(title: .text_OtherStyles)
          .image(name: ["star.leadinghalf.filled", "star.leadinghalf.fill"])
          .withExpandingDetailView {
            SettingsItem.Input()
              .bindTo(.subBlur)
            SettingsItem.Input()
              .bindTo(.subSpacing)
          }
      }
    }
  }

  private func sectionPosition() -> [NSView] {
    return section {
      SettingsListView(title: .text_Position) {
        SettingsItem.General(title: .text_Align)
          .image(name: "arrow.up.and.down.and.arrow.left.and.right")
          .withValueView(subtitlesAlignView.view)
        SettingsItem.General(title: .text_Margin)
          .image(name: "arrow.down.to.line")
          .withValueView(subtitlesMarginView.view)
        SettingsItem.Input()
          .image(name: "arrow.up.and.down")
          .bindTo(.subPos)
          .trailingLabel(.text_Percent)
      }

      SettingsListView {
        SettingsItem.Switch()
          .image(name: ["arrow.up.left.and.arrow.down.right.rectangle", "arrow.up.backward.and.arrow.down.forward"])
          .bindTo(.subScaleWithWindow)
      }

      SettingsListView {
        SettingsItem.Switch()
          .image(name: ["inset.filled.bottomthird.rectangle", "rectangle.bottomthird.inset.filled", "rectangle.bottomthird.inset.fill"])
          .bindTo(.displayInLetterBox)
      }
    }
  }

  private func sectionOnlineSubtitles() -> [NSView] {
    return section {
      SettingsListView(title: .text_OnlineSubtitles) {
        SettingsItem.General(title: .text_SubtitleSource)
          .image(name: "server.rack")
          .withDetailView(subtitleSourceView.view)
        SettingsItem.Switch()
          .image(name: ["text.magnifyingglass", "magnifyingglass"])
          .bindTo(.autoSearchOnlineSub)
          .hasDescription()
      }
    }
  }

  private func sectionOther() -> [NSView] {
    return section {
      SettingsListView(title: .text_Other) {
        SettingsItem.General(title: .text_PreferredLanguage)
          .image(name: "character.book.closed")
          .withDetailView(
            SettingsAccessory.LanguageSelector()
              .bind(to: .subLang)
              .hasDescription()
          )
        SettingsItem.General(title: .text_DefaultEncoding)
          .withDetailView(subtitlesEncodingView.view)
      }
    }
  }
}


fileprivate extension NSBindingName {
  static let state = NSBindingName("state")
}

fileprivate class SButton: NSButton {
  let onImage: NSImage?

  init(image: NSImage?) {
    self.onImage = image
    super.init(frame: .zero)
    setup()
  }

  required init?(coder: NSCoder) {
    fatalError()
  }

  private func setup() {
    self.wantsLayer = true
    self.layer?.borderWidth = 1
    self.layer?.cornerRadius = 6
    self.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
    self.bezelStyle = .smallSquare
    self.isBordered = false
    updateAppearance()
  }

  override func frame(forAlignmentRect alignmentRect: NSRect) -> NSRect {
    return alignmentRect
  }

  override var intrinsicContentSize: NSSize {
    var size = super.intrinsicContentSize
    size.width += 16
    return size
  }

  private func updateAppearance() {
    self.image = self.state == .on ? onImage?.tinted(.controlAccentColor) : onImage
  }

  override var state: NSControl.StateValue {
    didSet {
      updateAppearance()
    }
  }
}

fileprivate class SInput: NSTextField {
  override func frame(forAlignmentRect alignmentRect: NSRect) -> NSRect {
    return alignmentRect
  }
}


fileprivate class SBaseView: WithSettingsLocalizationContext {
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

  func makeInput(_ key: Preference.Key, isFixedSize: Bool = true) -> SInput {
    let input = SInput()
    input.translatesAutoresizingMaskIntoConstraints = false
    input.bezelStyle = .roundedBezel
    input.bind(.value, to: UserDefaults.standard, withKeyPath: key.rawValue)
    if isFixedSize {
      input.size(width: 48, height: 25)
    }
    return input
  }

  func makeStackView(_ views: [NSView]) -> NSStackView {
    let stackView = NSStackView(views: views)
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .horizontal
    stackView.alignment = .centerY
    stackView.spacing = 8
    return stackView
  }
}


fileprivate class SubtitlesASSView: SBaseView {
  let segmentControl: NSSegmentedControl

  private let stackView: NSStackView
  private let primarySelection: NSView
  private let secondarySelection: NSView

  override init(l10n: SettingsLocalization.Context) {
    self.segmentControl = NSSegmentedControl(
      labels: ["Primary", "Secondary"],
      trackingMode: .selectOne, target: nil, action: nil)

    self.primarySelection = SettingsAccessory.Selection(topPadding: 0)
      .bindTo(.subOverrideLevel, ofType: Preference.SubOverrideLevel.self)
      .order([4, 0, 3, 1, 2])
    self.secondarySelection = SettingsAccessory.Selection(l10nKey: .subOverrideLevel, topPadding: 0)
      .bindTo(.secondarySubOverrideLevel, ofType: Preference.SubOverrideLevel.self)
      .order([4, 0, 3, 1, 2])
    self.stackView = NSStackView(views: [primarySelection, secondarySelection])

    super.init(l10n: l10n)

    segmentControl.translatesAutoresizingMaskIntoConstraints = false
    segmentControl.target = self
    segmentControl.action = #selector(subOverrideLevelSegmentedControlAction(_:))
    segmentControl.selectedSegment = 0

    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .vertical
    stackView.alignment = .width
    stackView.setVisibilityPriority(.notVisible, for: secondarySelection)

    view.addSubview(stackView)
    stackView.padding(.top(4), .bottom, .horizontal)
  }

  @objc func subOverrideLevelSegmentedControlAction(_ sender: NSSegmentedControl) {
    if sender.selectedSegment == 0 {
      stackView.setVisibilityPriority(.mustHold, for: primarySelection)
      stackView.setVisibilityPriority(.notVisible, for: secondarySelection)
    } else {
      stackView.setVisibilityPriority(.notVisible, for: primarySelection)
      stackView.setVisibilityPriority(.mustHold, for: secondarySelection)
    }
  }
}


fileprivate class SubtitlesFontView: SBaseView {
  override init(l10n: SettingsLocalization.Context) {
    super.init(l10n: l10n)

    let fontButton = SButton(image: nil)
    fontButton.translatesAutoresizingMaskIntoConstraints = false
    fontButton.target = self
    fontButton.action = #selector(chooseSubFontAction)
    let widthConstraint = fontButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 160)
    widthConstraint.priority = .defaultHigh
    widthConstraint.isActive = true
    fontButton.bind(.title, to: UserDefaults.standard, withKeyPath: Preference.Key.subTextFont.rawValue)
    fontButton.size(height: 25)

    let sizeInput = makeInput(.subTextSize)

    let boldButton = SButton(image: NSImage(systemSymbolName: "bold", accessibilityDescription: nil)!)
    boldButton.translatesAutoresizingMaskIntoConstraints = false
    boldButton.setButtonType(.toggle)
    boldButton.cell!.bind(.state, to: UserDefaults.standard, withKeyPath: Preference.Key.subBold.rawValue)
    boldButton.size(width: 32, height: 25)

    let italicButton = SButton(image: NSImage(systemSymbolName: "italic", accessibilityDescription: nil)!)
    italicButton.translatesAutoresizingMaskIntoConstraints = false
    italicButton.setButtonType(.toggle)
    italicButton.cell!.bind(.state, to: UserDefaults.standard, withKeyPath: Preference.Key.subItalic.rawValue)
    italicButton.size(width: 32, height: 25)

    let stackView = makeStackView([fontButton, sizeInput, boldButton, italicButton])

    view.addSubview(stackView)
    stackView.padding(.top(8), .bottom(8), .leading, .trailing)
  }

  @objc func chooseSubFontAction(_ sender: AnyObject) {
    let subFont = Preference.string(for: .subTextFont)
    Utility.quickFontPickerWindow(selecting: subFont, sheetWindow: view.window!) { font in
      Preference.set(font ?? "sans-serif", for: .subTextFont)
      UserDefaults.standard.synchronize()
    }
  }
}


fileprivate class SubtitlesColorView: SBaseView {
  override init(l10n: SettingsLocalization.Context) {
    super.init(l10n: l10n)

    let colorLabel = makeLabel(.text_Color)
    let colorWell = makeColorWell()

    let backgroundLabel = makeLabel(.text_Background)
    let backgroundWell = makeColorWell()

    let stackView = makeStackView([colorLabel, colorWell, backgroundLabel, backgroundWell])

    view.addSubview(stackView)
    stackView.padding(.top(8), .bottom(8), .leading, .trailing)
  }
}


fileprivate class SubtitlesBorderView: SBaseView {
  override init(l10n: SettingsLocalization.Context) {
    super.init(l10n: l10n)
    
    let widthLabel = makeLabel(.text_Size)
    let widthInput = makeInput(.subBorderSize)

    let colorLabel = makeLabel(.text_Color)
    let colorWell = makeColorWell()

    let stackView = makeStackView([widthLabel, widthInput, colorLabel, colorWell])

    view.addSubview(stackView)
    stackView.padding(.vertical(8), .leading, .trailing)
  }
}


fileprivate class SubtitlesShadowView: SBaseView {
  override init(l10n: SettingsLocalization.Context) {
    super.init(l10n: l10n)

    let sizeLabel = makeLabel(.text_Offset)
    let sizeInput = makeInput(.subShadowSize)

    let colorLabel = makeLabel(.text_Color)
    let colorWell = makeColorWell()

    let stackView = makeStackView([sizeLabel, sizeInput, colorLabel, colorWell])

    view.addSubview(stackView)
    stackView.padding(.vertical(8), .leading, .trailing)
  }
}


fileprivate class SubtitlesMarginView: SBaseView {
  override init(l10n: SettingsLocalization.Context) {
    super.init(l10n: l10n)

    let xLabel = makeLabel(.text_X)
    let xInput = makeInput(.subMarginX)

    let yLabel = makeLabel(.text_Y)
    let yInput = makeInput(.subMarginY)

    let stackView = makeStackView([xLabel, xInput, yLabel, yInput])

    view.addSubview(stackView)
    stackView.padding(.vertical(8), .leading, .trailing)
  }
}


fileprivate class SubtitlesAlignView: SBaseView {
  override init(l10n: SettingsLocalization.Context) {
    super.init(l10n: l10n)

    let xLabel = makeLabel(.text_X)
    let xPopUp = makePopUp(.subAlignX)

    let yLabel = makeLabel(.text_Y)
    let yPopUp = makePopUp(.subAlignY)

    let stackView = makeStackView([xLabel, xPopUp, yLabel, yPopUp])

    view.addSubview(stackView)
    stackView.padding(.vertical(8), .leading, .trailing)
  }

  private func makePopUp(_ key: Preference.Key) -> NSPopUpButton {
    let allValues = Preference.SubAlign.self.allCases.map { $0.rawValue }
    let popupButton = NSPopUpButton()
    popupButton.bezelStyle = .toolbar

    for tag in allValues {
      let title = l10n.localized(.init("\(key.rawValue).items.\(tag)"))
      popupButton.addItem(withTitle: title)
      popupButton.lastItem?.tag = tag
    }
    popupButton.bind(.selectedTag, to: UserDefaults.standard, withKeyPath: key.rawValue)
    return popupButton
  }
}


fileprivate class SubtitlesEncodingView: SBaseView {
  let popupButton: NSPopUpButton

  override init(l10n: SettingsLocalization.Context) {
    self.popupButton = NSPopUpButton()
    super.init(l10n: l10n)

    popupButton.translatesAutoresizingMaskIntoConstraints = false
    popupButton.bezelStyle = .toolbar
    popupButton.target = self
    popupButton.action = #selector(changeDefaultEncoding)

    let defaultEncoding = Preference.string(for: .defaultEncoding)
    for encoding in AppData.encodings {
      popupButton.addItem(withTitle: encoding.title)
      let lastItem = popupButton.lastItem!
      lastItem.representedObject = encoding.code
      if encoding.code == defaultEncoding ?? "auto" {
        popupButton.select(lastItem)
      }
    }

    popupButton.menu?.insertItem(NSMenuItem.separator(), at: 1)
    view.addSubview(popupButton)
    popupButton.padding(.leading(SettingsSubListView.padding), .top, .bottom(8), .trailing(8))
  }

  @objc func changeDefaultEncoding(_ sender: NSPopUpButton) {
    Preference.set(sender.selectedItem!.representedObject!, for: .defaultEncoding)
    PlayerCore.active.setSubEncoding((sender.selectedItem?.representedObject as? String) ?? "auto")
    PlayerCore.active.reloadAllSubs()
  }
}


fileprivate class AdvancedInput: SBaseView {
  let inputField: NSTextField
  
  override init(l10n: SettingsLocalization.Context) {
    self.inputField = NSTextField()
    super.init(l10n: l10n)
    
    inputField.controlSize = .small
    inputField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    
    let stackView = NSStackView(views: [inputField])
    stackView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stackView)
    stackView.padding(.top, .leading(SettingsSubListView.padding), .trailing(8), .bottom(8))
  }
}


fileprivate class SubtitleSourceView: SBaseView {
  var subSourceStackView: NSStackView!
  let subSourcePopUpButton: NSPopUpButton
  let loginIndicator: NSProgressIndicator
  
  override init(l10n: SettingsLocalization.Context) {
    self.subSourcePopUpButton = NSPopUpButton()
    subSourcePopUpButton.translatesAutoresizingMaskIntoConstraints = false
    subSourcePopUpButton.bind(.selectedObject, to: UserDefaults.standard, withKeyPath: Preference.Key.onlineSubProvider.rawValue)
    self.subSourceStackView = nil
    self.loginIndicator = NSProgressIndicator()
    loginIndicator.translatesAutoresizingMaskIntoConstraints = false
    loginIndicator.style = .spinning
    loginIndicator.isHidden = true
    super.init(l10n: l10n)
    
    let descLabel = makeLabel(.text_SubtitleSource_desc).makeMultiLine()
    
    // don't add legacy opensub support (is the API still alive?)
    let legacyOpenSubLabel = makeLabel(.text_LegacyOpenSubAlert).makeMultiLine()
//    let openSubAccountName = makeLabel(.text_NotLoggedIn)
//    let openSubLoginBtn = makeButton(.text_Login)
//    let legacyOpenSubSettingsView = makeStackView([openSubLoginBtn, openSubAccountName, loginIndicator])
    let legacyOpenSubView = makeStackView([legacyOpenSubLabel])
    legacyOpenSubView.orientation = .vertical

    let assrtHelpBtn = NSButton(title: "", target: self, action: #selector(assrtHelpBtnAction))
    assrtHelpBtn.bezelStyle = .helpButton
    let assrtLabel = makeLabel(.text_AssrtAPIToken, isSmall: false)
    let assrtTokenField = makeInput(.assrtToken, isFixedSize: false)
    let assrtView = makeStackView([assrtLabel, assrtTokenField, assrtHelpBtn])
    
    let pluginDescLabel = makeLabel(.text_SubtitleSourcePluginDesc).makeMultiLine()
    
    subSourceStackView = makeStackView([subSourcePopUpButton, descLabel, legacyOpenSubView, assrtView, pluginDescLabel])
    subSourceStackView.orientation = .vertical
    subSourcePopUpButton.padding(.horizontal)

    view.addSubview(subSourceStackView)
    subSourceStackView.padding(.top, .bottom(8), .leading(SettingsSubListView.padding), .trailing(8))
    
    subSourcePopUpButton.target = self
    subSourcePopUpButton.action = #selector(refreshSubSourceAccessoryView)
    
    refreshSubSources()
    refreshSubSourceAccessoryView()
  }
  
  @objc private func assrtHelpBtnAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.wikiLink.appending("/Download-Online-Subtitles#assrt"))!)
  }

  private func refreshSubSources() {
    OnlineSubtitle.populateMenu(subSourcePopUpButton.menu!)
    let provider = Preference.string(for: .onlineSubProvider)
    let index = subSourcePopUpButton.menu!.items.firstIndex { $0.representedObject as? String == provider }
    subSourcePopUpButton.selectItem(at: index ?? 0)
  }

  @objc private func refreshSubSourceAccessoryView() {
    let map = [OnlineSubtitle.Providers.openSub.id: 2, OnlineSubtitle.Providers.assrt.id: 3]
    let id = subSourcePopUpButton.selectedItem?.representedObject as? String ?? ""
    let isSourceFromPlugin = !id.hasPrefix(":")
    for (index, view) in subSourceStackView.views.enumerated() {
      if index == 0 || index == 1 { continue }
      if index == 4 {
        subSourceStackView.setVisibilityPriority(isSourceFromPlugin ? .mustHold : .notVisible, for: view)
      } else {
        subSourceStackView.setVisibilityPriority(index == map[id] ? .mustHold : .notVisible, for: view)
      }
    }
  }
}
