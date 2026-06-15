//
//  SidebarAudioPane.swift
//  iina
//
//  Created by Hechen Li on 2026-06-15.
//  Copyright © 2026 lhc. All rights reserved.
//

fileprivate let ui = UIHelper.shared


class SidebarAudioPane: SidebarScrollView {
  let prefObserver = Preference.Observer()
  weak var player: PlayerCore!

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    drawsBackground = false

    let stack = ui.vStack(spacing: .sidebarStackViewSpacing)

    stack.addArrangedSubview(Container(TrackSelector(
      .audio,
      player: player,
      observedKeys: [.iinaAIDChanged]
    )) {
      $0.padding(.horizontal, .vertical(.sidebarContainerPadding))
    })

    let loadExternalAudioBtn = ui.button(
      "sidebar.load_external_audio",
      target: self, action: #selector(loadExternalAudioAction)
    )
    loadExternalAudioBtn.setContentHuggingPriority(.init(100), for: .horizontal)
    stack.addArrangedSubview(Container(
      loadExternalAudioBtn
    ) {
      $0.padding(.all(.sidebarContainerPadding))
    })

    stack.addArrangedSubview(Container(AudioDelayView(player: player)) {
      $0.padding(.all(.sidebarContainerPadding))
    })

    stack.addArrangedSubview(Container(EqualizerView(player: player)) {
      $0.padding(.all(.sidebarContainerPadding))
    })

    documentView!.addSubview(stack)
    stack.padding(.horizontal(.sidebarMargin), .vertical(4))
  }

  @objc private func loadExternalAudioAction(_ sender: NSButton) {
    let currentDir = player.info.currentURL?.deletingLastPathComponent()
    Utility.quickOpenPanel(
      title: "Load external audio file",
      chooseDir: false,
      dir: currentDir,
      sheetWindow: player.currentWindow,
      allowedFileTypes: Utility.playableFileExt
    ) { url in
      self.player.loadExternalAudioFile(url)
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}


fileprivate class AudioDelayView: SidebarSliderView {
  override var titleImage: NSImage? {
    .sf("clock.arrow.trianglehead.counterclockwise.rotate.90", "clock.arrow.circlepath")
  }
  override var titleKey: String { "sidebar.delay" }
  override var tickMarkLabels: [String] {
    ["-5s", "0s", "+5s"]
  }
  override var notificationKey: Notification.Name {
    .iinaAudioDelayChanged
  }

  override func setup() {
    slider.minValue = -5
    slider.maxValue = 5
    slider.numberOfTickMarks = 21
    if #available(macOS 26, *) {
      slider.neutralValue = 0
    }

    let fmt = NumberFormatter()
    fmt.numberStyle = .decimal
    fmt.maximumSignificantDigits = 3
    input.formatter = fmt
  }

  override func indicatorLabel() -> String {
    "\(input.stringValue)s"
  }

  override func update() {
    let audioDelay = player.mpv.getDouble(MPVOption.Audio.audioDelay)
    slider.doubleValue = audioDelay
    input.doubleValue = audioDelay
    resetButton.isHidden = slider.doubleValue == 0
    updateIndicator()
  }

  override func sliderAction() {
    let eventType = NSApp.currentEvent!.type
    let sliderValue: Double
    switch eventType {
    case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
      // When dragging slider with the mouse, snap to the nearest 50ms (1/20 sec)
      // Although it is possible to show tick marks at every step of 0.05 in the slider, it is visually unpleasant.
      // So we draw less tick marks, and keep "Only stop on tick marks" disabled, and add our own logic to stop on
      // "virtual tick marks" for these values.
      sliderValue = (slider.doubleValue * 20.0).rounded() / 20.0
      slider.doubleValue = sliderValue
    default:
      sliderValue = slider.doubleValue
    }
    input.doubleValue = sliderValue
    updateIndicator()
    if let event = NSApp.currentEvent {
      if event.type == .leftMouseUp {
        player.setAudioDelay(sliderValue)
      }
    }
  }

  override func customEditFinishedAction() {
    if input.stringValue.isEmpty {
      input.stringValue = "0"
    }
    let value = input.doubleValue
    player.setAudioDelay(value)
    if let window = input.window {
      window.makeFirstResponder(window.contentView)
    }
  }

  override func resetButtonAction() {
    player.setAudioDelay(0)
  }
}


fileprivate let eqUserDefinedProfileMenuItemTag = 0
fileprivate let eqPresetProfileMenuItemTag = 1
fileprivate let eqDeleteMenuItemTag = -1
fileprivate let eqRenameMenuItemTag = -2
fileprivate let eqSaveMenuItemTag = -3
fileprivate let eqCustomMenuItemTag = 1000


fileprivate class EqualizerView: NSView, NSMenuDelegate {
  private unowned let player: PlayerCore

  private var eqPopUpButton: NSPopUpButton!
  private var lastUsedProfileName: String = ""

  private lazy var audioEQSliders: [NSSlider] = {
    (0...9).map {
      let slider = NSSlider()
      slider.controlSize = .mini
      slider.isVertical = true
      slider.minValue = -12
      slider.maxValue = 12
      slider.numberOfTickMarks = 5
      if #available(macOS 26.0, *) {
        slider.neutralValue = 0
      }
      slider.tag = $0
      slider.target = self
      slider.action = #selector(audioEqSliderAction)
      return slider
    }
  }()

  private let eqFrequencyLabels = [
    "32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k",
  ]

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false

    let labelStack = ui.hStack(
      spacing: 8,
      ui.image("slider.vertical.3", size: 16),
      ui.label("sidebar.eq", font: .boldSystemFont(ofSize: 12)),
      ui.flexibleSpace(),
    )

    self.eqPopUpButton = NSPopUpButton(frame: .zero)
    eqPopUpButton.translatesAutoresizingMaskIntoConstraints = false
    [
      ("save_eq", eqSaveMenuItemTag),
      ("rename_eq", eqRenameMenuItemTag),
      ("remove_eq", eqDeleteMenuItemTag),
      ("", 0),
      ("manual_eq", eqCustomMenuItemTag),
      ("", 0)
    ].forEach { title, tag in
      if title.isEmpty {
        let item = NSMenuItem.separator()
        item.tag = -1000
        eqPopUpButton.menu!.addItem(item)
      } else {
        let item = NSMenuItem(title: NSLocalizedString("sidebar.\(title)", comment: ""), action: nil, keyEquivalent: "")
        item.tag = tag
        eqPopUpButton.menu!.addItem(item)
      }
    }
    EQProfile.presets.forEach { preset in
      eqPopUpButton.menu!.addItem(withTitle: preset.name, tag: eqPresetProfileMenuItemTag, obj: preset.localizationKey)
    }
    eqPopUpButton.selectItem(withTag: eqCustomMenuItemTag)
    lastUsedProfileName = eqPopUpButton.selectedItem!.title

    eqPopUpButton.menu!.delegate = self
    eqPopUpButton.target = self
    eqPopUpButton.action = #selector(eqPopUpButtonAction)

    let freqLabelContainer = NSView()
    freqLabelContainer.translatesAutoresizingMaskIntoConstraints = false

    let dbLabelContainer = ui.vStack(
      align: .trailing,
      ui.label("+12 dB", isSmall: true),
      ui.label("0 dB", isSmall: true),
      ui.label("-12 dB", isSmall: true),
    )
    dbLabelContainer.distribution = .equalSpacing
    dbLabelContainer.size(height: 120)

    let eqStack = ui.hStack(audioEQSliders + [dbLabelContainer])
    eqStack.setHuggingPriority(.init(100), for: .horizontal)
    eqStack.distribution = .equalSpacing
    eqStack.size(height: 120)

    let container = ui.vStack(
      spacing: .sidebarItemSpacing,
      wantsToGrow: true,
      labelStack, eqPopUpButton, ui.space(), eqStack, freqLabelContainer
    )

    zip(eqFrequencyLabels, audioEQSliders).forEach { label, slider in
      let label = ui.label(label, font: .systemFont(ofSize: 10), isSecondary: true)
      freqLabelContainer.addSubview(label)
      label.padding(.vertical)
      label.centerXAnchor.constraint(equalTo: slider.centerXAnchor).isActive = true
    }

    addSubview(container)
    container.padding(.all)

    player.observe(.iinaAFChanged) { [unowned self] _ in
      update()
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  func applyEQ(_ profile: EQProfile) {
    zip(audioEQSliders, profile.gains).forEach { (slider, gain) in
      slider.doubleValue = gain
    }
    player.setAudioEq(fromGains: profile.gains)
  }

  private func update() {
    if let filter = player.info.audioEqFilter {
      guard let eqString = Regex("\\[(.+?)\\]").captures(in: filter.stringFormat)[at: 1] else { return }
      let filters = eqString.split(separator: ",")
      zip(filters, audioEQSliders).forEach { (filter, slider) in
        if let gain = filter.split(separator: "=").last {
          slider.doubleValue = Double(gain) ?? 0
        } else {
          slider.doubleValue = 0
        }
      }
    } else {
      audioEQSliders.forEach { $0.doubleValue = 0 }
    }
  }

  private func promptAudioEQProfileName(isNewProfile: Bool) -> String? {
    let key = isNewProfile ? "eq.new_profile" : "eq.rename"
    let nameList = eqPopUpButton.itemArray
      .filter{ $0.tag == eqPresetProfileMenuItemTag || $0.tag == eqUserDefinedProfileMenuItemTag }
      .map{ $0.title }
    let validator: Utility.InputValidator<String> = { input in
      if input.isEmpty {
        return .valueIsEmpty
      }
      if nameList.contains( where: { $0 == input } ) {
        return .valueAlreadyExists
      } else {
        return .ok
      }
    }
    var inputString: String?
    Utility.quickPromptPanel(key, validator: validator, callback: { inputString = $0 })
    return inputString
  }

  func findItem(_ name: String, _ tag: Int = eqUserDefinedProfileMenuItemTag) -> NSMenuItem? {
    return eqPopUpButton.itemArray.filter{ $0.tag == tag }.first { $0.title == name }
  }

  @objc func audioEqSliderAction(_ sender: NSSlider) {
    player.setAudioEq(fromGains: audioEQSliders.map { $0.doubleValue })
    eqPopUpButton.selectItem(withTag: eqCustomMenuItemTag)
  }

  @objc func eqPopUpButtonAction(_ sender: NSPopUpButton) {
    let tag = sender.selectedTag()
    let name = sender.titleOfSelectedItem
    let representedObject = sender.selectedItem?.representedObject as? String
    switch tag {
    case eqSaveMenuItemTag:
      if let inputString = promptAudioEQProfileName(isNewProfile: true) {
        let newProfile = EQProfile(fromCurrentSliders: audioEQSliders)
        EQProfile.userEQs[inputString] = newProfile
        menuNeedsUpdate(eqPopUpButton.menu!)
        eqPopUpButton.select(findItem(inputString))
        lastUsedProfileName = inputString
      } else {
        eqPopUpButton.selectItem(withTag: eqCustomMenuItemTag)
      }
    case eqRenameMenuItemTag:
      if let inputString = promptAudioEQProfileName(isNewProfile: false) {
        let profile = EQProfile.userEQs.removeValue(forKey: lastUsedProfileName)
        EQProfile.userEQs[inputString] = profile
        menuNeedsUpdate(eqPopUpButton.menu!)
        eqPopUpButton.select(findItem(inputString))
        lastUsedProfileName = inputString
      } else {
        eqPopUpButton.select(findItem(lastUsedProfileName))
      }
    case eqDeleteMenuItemTag:
      EQProfile.userEQs.removeValue(forKey: lastUsedProfileName)
      menuNeedsUpdate(eqPopUpButton.menu!)
      eqPopUpButton.selectItem(withTag: eqCustomMenuItemTag)
    case eqCustomMenuItemTag:
      lastUsedProfileName = sender.selectedItem!.title
    case eqPresetProfileMenuItemTag:
      guard let preset = EQProfile.presets.first(where: { $0.localizationKey == representedObject }) else { break }
      lastUsedProfileName = preset.name
      applyEQ(preset)
    default: // user defined EQ Profiles
      guard let pair = EQProfile.userEQs.first(where: { $0.0 == name }) else { break }
      lastUsedProfileName = pair.0
      applyEQ(pair.1)
    }
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    let tag = eqPopUpButton.selectedTag()
    let saveItem = menu.item(withTag: eqSaveMenuItemTag)!
    let editingItems = [menu.item(withTag: eqRenameMenuItemTag)!, menu.item(withTag: eqDeleteMenuItemTag)!]

    editingItems.forEach { $0.isHidden = (tag != eqUserDefinedProfileMenuItemTag) }
    saveItem.isEnabled = (tag == eqCustomMenuItemTag)

    let selectedName = eqPopUpButton.titleOfSelectedItem!
    let selectedTag = eqPopUpButton.selectedTag()
    var items = menu.items
    items.removeAll { $0.tag == eqUserDefinedProfileMenuItemTag }
    if !EQProfile.userEQs.isEmpty {
      items.append(NSMenuItem.separator())
    }
    menu.items = items
    EQProfile.userEQs.forEach { (name, eq) in
      menu.addItem(withTitle: name, tag: eqUserDefinedProfileMenuItemTag)
    }
    eqPopUpButton.select(findItem(selectedName, selectedTag))
    eqPopUpButton.itemArray.forEach { $0.state = .off }
    eqPopUpButton.selectedItem?.state = .on
  }
}
