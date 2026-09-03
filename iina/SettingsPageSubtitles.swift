//
//  SettingsPageSubtitles.swift
//  iina
//
//  Created by Hechen Li on 6/16/25.
//  Copyright © 2025 lhc. All rights reserved.
//

fileprivate let ui = SettingsUIHelper.sharedUI


class SettingsPageSubtitles: SettingsPage {
  override var identifier: String {
    "subtitles"
  }
  
  override var title: String {
    return NSLocalizedString("sidebar.sub", comment: "Subtitles")
  }

  override var image: NSImage {
    return .sf("captions.bubble", withConfiguration: symbolConfiguration)!
  }

  override var localizationTable: String {
    "SettingsSubtitesLocalizable"
  }

  private lazy var subtitlesASSView: SubtitlesASSView = SubtitlesASSView()
  private lazy var subtitlesFontView: SubtitlesFontView = SubtitlesFontView()
  private lazy var subtitlesColorView: SubtitlesColorView = SubtitlesColorView()
  private lazy var subtitlesBorderView: SubtitlesBorderView = SubtitlesBorderView()
  private lazy var subtitlesShadowView: SubtitlesShadowView = SubtitlesShadowView()
  private lazy var subtitlesMarginView: SubtitlesMarginView = SubtitlesMarginView()
  private lazy var subtitlesAlignView: SubtitlesAlignView = SubtitlesAlignView()
  private lazy var subtitlesEncodingView: SubtitlesEncodingView = SubtitlesEncodingView()
  private lazy var subtitleSourceView: SubtitleSourceView = SubtitleSourceView()

  override func content() -> [SettingsSection] {
    return sections {
      sectionAutoLoad()
      sectionASS()
      sectionText()
      sectionPosition()
      sectionOnlineSubtitles()
      sectionOther()
    }
  }

  private func sectionAutoLoad() -> SettingsSection {
    return section {
      SettingsList(title: .text_AutoLoad) {
        SettingsItem.PopupButton()
          .image(name: ["bolt.badge.automatic", "bolt.badge.a"])
          .bindTo(.subAutoLoadIINA, ofType: Preference.IINAAutoLoadAction.self)
        SettingsItem.General(title: .text_Advanced)
          .withExpandingDetailView {
            SettingsItem.LongInput()
              .bindTo(.subAutoLoadPriorityString)
              .controlSize(.small)
              .hasDescription()
            SettingsItem.LongInput()
              .bindTo(.subAutoLoadSearchPath)
              .controlSize(.small)
              .hasDescription()
          }
      }
    }
  }

  private func sectionASS() -> SettingsSection {
    return section {
      SettingsList(title: .text_ASSSubtitles) {
        SettingsItem.General(title: .text_OverrideLevel)
          .image(name: "pencil.slash")
          .withHelpLink("https://mpv.io/manual/stable/#options-sub-ass-override")
          .withValueView(subtitlesASSView.segmentControl)
          .withDetailView(subtitlesASSView)
      }
    }
  }

  private func sectionText() -> SettingsSection {
    return section {
      SettingsList(title: .text_TextSubtitles) {
        SettingsItem.General(title: .text_Font)
          .image(name: "textformat")
          .withValueView(subtitlesFontView.view)
        SettingsItem.General(title: .text_Color)
          .image(name: "paintpalette")
          .withValueView(subtitlesColorView.view)
        SettingsItem.PopupButton()
          .image(name: ["character.textbox.badge.sparkles", "square.dashed.inset.filled", "square.dashed"])
          .bindTo(.subBorderStyle, ofType: Preference.SubBorderStyle.self)
          .withHelpLink(AppData.mpvManualLink.appending("/#options-sub-border-style"))
        SettingsItem.General(title: .text_Border)
          .image(name: ["inset.filled.circle.dashed", "circle.dashed.inset.filled", "circle.dashed.inset.fill"])
          .withValueView(subtitlesBorderView.view)
        SettingsItem.General(title: .text_Shadow)
          .image(name: ["shadow"])
          .withValueView(subtitlesShadowView.view)
        SettingsItem.General(title: .text_OtherStyles)
          .image(name: ["textformat.characters.arrow.left.and.right", "star.leadinghalf.filled", "star.leadinghalf.fill"])
          .withExpandingDetailView {
            SettingsItem.Input()
              .bindTo(.subBlur)
              .range(0...20, allowsFloats: true)
            SettingsItem.Input()
              .bindTo(.subSpacing)
              .range(-10...10, allowsFloats: true)
          }
      }
    }
  }

  private func sectionPosition() -> SettingsSection {
    return section {
      SettingsList(title: .text_Position) {
        SettingsItem.General(title: .text_Align)
          .image(name: "arrow.up.and.down.and.arrow.left.and.right")
          .withValueView(subtitlesAlignView.view)
        SettingsItem.General(title: .text_Margin)
          .image(name: "arrow.down.to.line")
          .withValueView(subtitlesMarginView.view)
        SettingsItem.Input()
          .image(name: "arrow.up.and.down")
          .bindTo(.subPos)
          .range(0...150)
          .trailingLabel(.text_Percent)
      }

      SettingsList {
        SettingsItem.Switch()
          .image(name: ["arrow.up.left.and.arrow.down.right.rectangle", "arrow.up.backward.and.arrow.down.forward"])
          .bindTo(.subScaleWithWindow)
      }

      SettingsList {
        SettingsItem.Switch()
          .image(name: ["inset.filled.bottomthird.rectangle", "rectangle.bottomthird.inset.filled", "rectangle.bottomthird.inset.fill"])
          .bindTo(.displayInLetterBox)
      }
    }
  }

  private func sectionOnlineSubtitles() -> SettingsSection {
    return section {
      SettingsList(title: .text_OnlineSubtitles) {
        SettingsItem.General(title: .text_SubtitleSource)
          .image(name: "server.rack")
          .withDetailView(subtitleSourceView)
        SettingsItem.Switch()
          .image(name: ["text.magnifyingglass", "magnifyingglass"])
          .bindTo(.autoSearchOnlineSub)
          .hasDescription()
      }
    }
  }

  private func sectionOther() -> SettingsSection {
    return section {
      SettingsList(title: .text_Other) {
        SettingsItem.General(title: .text_PreferredLanguage)
          .image(name: "character.book.closed")
          .withDetailView(
            SettingsAccessory.LanguageSelector()
              .bind(to: .subLang)
              .hasDescription()
          )
        SettingsItem.General(title: .text_DefaultEncoding)
          .withDetailView(subtitlesEncodingView)
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


fileprivate class SubtitlesASSView: SettingsAccessory.Base {
  let segmentControl: NSSegmentedControl

  private let stackView: NSStackView
  private let primarySelection: SettingsAccessory.Selection
  private let secondarySelection: SettingsAccessory.Selection

  override init() {
    self.segmentControl = NSSegmentedControl(
      labels: ["Primary", "Secondary"],
      trackingMode: .selectOne, target: nil, action: nil)

    self.primarySelection = SettingsAccessory.Selection(topPadding: 0)
      .bindTo(.subOverrideLevel, ofType: Preference.SubOverrideLevel.self)
      .order([4, 0, 3, 1, 2])
    self.secondarySelection = SettingsAccessory.Selection(l10nKey: .subOverrideLevel, topPadding: 0)
      .bindTo(.secondarySubOverrideLevel, ofType: Preference.SubOverrideLevel.self)
      .order([4, 0, 3, 1, 2])
    self.stackView = NSStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false

    super.init()

    segmentControl.translatesAutoresizingMaskIntoConstraints = false
    segmentControl.target = self
    segmentControl.action = #selector(subOverrideLevelSegmentedControlAction(_:))
    segmentControl.selectedSegment = 0

    view.addSubview(stackView)
    stackView.padding(.top(4), .bottom, .horizontal)
  }

  override func registerSearchEntry(context: SettingsSearch.Context) {
    primarySelection.registerSearchEntry(context: context)
  }

  override func makeView() -> NSView {
    stackView.addArrangedSubview(primarySelection.makeView())
    stackView.addArrangedSubview(secondarySelection.makeView())
    stackView.orientation = .vertical
    stackView.alignment = .width
    stackView.setVisibilityPriority(.notVisible, for: secondarySelection.builtView!)

    return super.makeView()
  }

  @objc func subOverrideLevelSegmentedControlAction(_ sender: NSSegmentedControl) {
    if sender.selectedSegment == 0 {
      stackView.setVisibilityPriority(.mustHold, for: primarySelection.builtView!)
      stackView.setVisibilityPriority(.notVisible, for: secondarySelection.builtView!)
    } else {
      stackView.setVisibilityPriority(.notVisible, for: primarySelection.builtView!)
      stackView.setVisibilityPriority(.mustHold, for: secondarySelection.builtView!)
    }
  }
}


fileprivate class SubtitlesFontView: SettingsAccessory.Base {
  override init() {
    super.init()

    let fontButton = SButton(image: nil)
    fontButton.translatesAutoresizingMaskIntoConstraints = false
    fontButton.target = self
    fontButton.action = #selector(chooseSubFontAction)
    fontButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let widthConstraint = fontButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120)
    widthConstraint.priority = .defaultLow
    widthConstraint.isActive = true
    fontButton.bind(.title, to: UserDefaults.standard, withKeyPath: Preference.Key.subTextFont.rawValue)
    fontButton.size(height: 25)

    let sizeInput = ui.input(bindTo: .subTextSize, range: 1...9000, allowsFloats: true)

    let boldButton = SButton(image: .sf("bold"))
    boldButton.translatesAutoresizingMaskIntoConstraints = false
    boldButton.setButtonType(.toggle)
    boldButton.cell!.bind(.state, to: UserDefaults.standard, withKeyPath: Preference.Key.subBold.rawValue)
    boldButton.size(width: 32, height: 25)

    let italicButton = SButton(image: .sf("italic"))
    italicButton.translatesAutoresizingMaskIntoConstraints = false
    italicButton.setButtonType(.toggle)
    italicButton.cell!.bind(.state, to: UserDefaults.standard, withKeyPath: Preference.Key.subItalic.rawValue)
    italicButton.size(width: 32, height: 25)

    let stackView = ui.hStack(fontButton, sizeInput, boldButton, italicButton)

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


fileprivate class SubtitlesColorView: SettingsAccessory.Base {
  override init() {
    super.init()
    let colorWell = ui.colorWell(bindTo: .subTextColorString)
    view.addSubview(colorWell)
    colorWell.padding(.top(8), .bottom(8), .leading, .trailing)
  }
}


fileprivate class SubtitlesBorderView: SettingsAccessory.Base {
  override init() {
    super.init()

    let widthLabel = ui.smallLabel(bindTo: .text_Size)
    let widthInput = ui.input(bindTo: .subBorderSize, range: 0...Double.infinity, allowsFloats: true)

    let colorLabel = ui.smallLabel(bindTo: .text_Color)
    let colorWell = ui.colorWell(bindTo: .subBorderColorString)

    let stackView = ui.hStack(widthLabel, widthInput, colorLabel, colorWell)

    view.addSubview(stackView)
    stackView.padding(.vertical(8), .leading, .trailing)
  }
}


fileprivate class SubtitlesShadowView: SettingsAccessory.Base {
  override init() {
    super.init()

    let sizeLabel = ui.smallLabel(bindTo: .text_Offset)
    let sizeInput = ui.input(bindTo: .subShadowSize)

    let colorLabel = ui.smallLabel(bindTo: .text_Color)
    let colorWell = ui.colorWell(bindTo: .subShadowColorString)

    let stackView = ui.hStack(sizeLabel, sizeInput, colorLabel, colorWell)

    view.addSubview(stackView)
    stackView.padding(.vertical(8), .leading, .trailing)
  }
}


fileprivate class SubtitlesMarginView: SettingsAccessory.Base {
  override init() {
    super.init()

    let xLabel = ui.smallLabel(bindTo: .text_X)
    let xInput = ui.input(bindTo: .subMarginX, range: 0...Double(Int.max))

    let yLabel = ui.smallLabel(bindTo: .text_Y)
    let yInput = ui.input(bindTo: .subMarginY, range: 0...Double(Int.max))

    let stackView = ui.hStack(xLabel, xInput, yLabel, yInput)

    view.addSubview(stackView)
    stackView.padding(.vertical(8), .leading, .trailing)
  }
}


fileprivate class SubtitlesAlignView: SettingsAccessory.Base {
  override init() {
    super.init()

    let xLabel = ui.smallLabel(bindTo: .text_X)
    let xPopUp = makePopUp(.subAlignX)

    let yLabel = ui.smallLabel(bindTo: .text_Y)
    let yPopUp = makePopUp(.subAlignY)

    let stackView = ui.hStack(xLabel, xPopUp, yLabel, yPopUp)

    view.addSubview(stackView)
    stackView.padding(.vertical(8), .leading, .trailing)
  }

  private func makePopUp(_ key: Preference.Key) -> NSPopUpButton {
    let allValues = key == .subAlignX ? Preference.SubAlignX.self.allCases.map { $0.rawValue } :
      Preference.SubAlignY.self.allCases.map { $0.rawValue }
    let popupButton = NSPopUpButton()
    popupButton.bezelStyle = .toolbar

    for tag in allValues {
      let title = ui.localized(.init("\(key.rawValue).items.\(tag)"))
      popupButton.addItem(withTitle: title)
      popupButton.lastItem?.tag = tag
    }
    popupButton.bind(.selectedTag, to: UserDefaults.standard, withKeyPath: key.rawValue)
    return popupButton
  }
}


fileprivate class SubtitlesEncodingView: SettingsAccessory.Base {
  let popupButton: NSPopUpButton

  override init() {
    self.popupButton = NSPopUpButton()
    super.init()

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
    popupButton.padding(.leading(SettingsSubList.indent), .top, .bottom(8), .trailing(8))
  }

  @objc func changeDefaultEncoding(_ sender: NSPopUpButton) {
    Preference.set(sender.selectedItem!.representedObject!, for: .defaultEncoding)
    PlayerCore.active.setSubEncoding((sender.selectedItem?.representedObject as? String) ?? "auto")
    PlayerCore.active.reloadAllSubs()
  }
}


fileprivate class SubtitleSourceView: SettingsAccessory.Base {
  var subSourceStackView: NSStackView!
  let subSourcePopUpButton: NSPopUpButton
  let loginIndicator: NSProgressIndicator

  override init() {
    self.subSourcePopUpButton = NSPopUpButton()
    subSourcePopUpButton.translatesAutoresizingMaskIntoConstraints = false
    subSourcePopUpButton.bind(.selectedObject, to: UserDefaults.standard, withKeyPath: Preference.Key.onlineSubProvider.rawValue)
    self.subSourceStackView = nil
    self.loginIndicator = NSProgressIndicator()
    loginIndicator.translatesAutoresizingMaskIntoConstraints = false
    loginIndicator.style = .spinning
    loginIndicator.isHidden = true
    super.init()

    let descLabel = ui.smallLabel(bindTo: .text_SubtitleSource_desc).makeMultiLine()

    // don't add legacy opensub support (is the API still alive?)
    let legacyOpenSubLabel = ui.smallLabel(bindTo: .text_LegacyOpenSubAlert).makeMultiLine()
//    let openSubAccountName = ui.smallLabel(bindTo: .text_NotLoggedIn)
//    let openSubLoginBtn = ui.button(.text_Login)
//    let legacyOpenSubSettingsView = makeStackView([openSubLoginBtn, openSubAccountName, loginIndicator])
    let legacyOpenSubView = ui.vStack(legacyOpenSubLabel)

    let assrtHelpBtn = NSButton(title: "", target: self, action: #selector(assrtHelpBtnAction))
    assrtHelpBtn.bezelStyle = .helpButton
    let assrtLabel = ui.label(bindTo: .text_AssrtAPIToken, isSecondary: true)
    let assrtTokenField = ui.input(bindTo: .assrtToken, isFixedSize: false)
    let assrtView = ui.hStack(assrtLabel, assrtTokenField, assrtHelpBtn)

    let pluginDescLabel = ui.smallLabel(bindTo: .text_SubtitleSourcePluginDesc).makeMultiLine()

    subSourceStackView = ui.vStack(
      subSourcePopUpButton, descLabel, legacyOpenSubView, assrtView, pluginDescLabel
    )
    subSourcePopUpButton.padding(.horizontal)

    view.addSubview(subSourceStackView)
    subSourceStackView.padding(.top, .bottom(8), .leading(SettingsSubList.indent), .trailing(8))

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
