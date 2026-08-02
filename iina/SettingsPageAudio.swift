//
//  SettingsPageAudio.swift
//  iina
//
//  Created by Hechen Li on 6/15/25.
//  Copyright © 2025 lhc. All rights reserved.
//

fileprivate let ui = SettingsUIHelper.sharedUI


class SettingsPageAudio: SettingsPage {
  private lazy var audioOutputDeviceView: AudioOutputDeviceView = AudioOutputDeviceView()

  override var identifier: String {
    "audio"
  }

  override var title: String {
    return NSLocalizedString("sidebar.audio", comment: "Audio")
  }

  override var image: NSImage {
    return .sf("waveform", withConfiguration: symbolConfiguration)!
  }

  override var localizationTable: String {
    "SettingsAudioLocalizable"
  }

  override func content() -> [SettingsSection] {
    return sections {
      sectionHardware()
      sectionChannelRouting()
      sectionVolume()
      sectionOther()
    }
  }

  private func sectionHardware() -> SettingsSection {
    return section {
      SettingsList(title: .text_Hardware) {
        SettingsItem.Input(title: .videoThreadsLabel)
          .image(name: "number")
          .bindTo(.audioThreads)
          .hasDescription(content: .videoThreadsDesc)
        SettingsItem.General(title: .audioDriverEnableAVFoundationLabel)
          .image(name: "waveform")
          .withHelpLink(AppData.audioDriverHellpLink)
          .withDetailView(
            SettingsAccessory.Selection()
              .bindTo(.audioDriverEnableAVFoundation, ofType: AudioDriver.self)
              .customTransformer(({ $0 == 1 }, { val in
                if let val = val as? Bool, val {
                  return 1
                }
                return 0
              }))
          )
      }

      SettingsList {
        SettingsItem.General(title: .preferredAudioDeviceLabel)
          .image(name: "hifispeaker.and.homepod")
          .withDetailView(audioOutputDeviceView)
        SettingsItem.General(title: .text_SPDIFOutput)
          .image(name: "audio.jack.stereo")
          .withExpandingDetailView {
            SettingsItem.Switch()
              .bindTo(.spdifAC3)
            SettingsItem.Switch()
              .bindTo(.spdifDTS)
            SettingsItem.Switch()
              .bindTo(.spdifDTSHD)
          }
      }
    }
  }

  private func sectionChannelRouting() -> SettingsSection {
    return section {
      SettingsList {
        SettingsItem.Switch()
          .image(name: "arrow.triangle.branch")
          .bindTo(.audioChannelRoutingEnabled)
          .bindExpandableView()
          .hasDescription()
          .withExpandingDetailView(AudioChannelRoutingView())
      }
    }
  }

  private func sectionVolume() -> SettingsSection {
    return section {
      SettingsList(title: .text_Volume) {
        SettingsItem.SwitchWithInput()
          .image(name: "speaker.wave.3")
          .labelKey(.enableInitialVolume)
          .bindInputTo(.initialVolume)
          .bindSwitchTo(.enableInitialVolume)
        SettingsItem.Input()
          .bindTo(.maxVolume)
          .hasDescription()
      }

      SettingsList {
        SettingsItem.PopupButton()
          .image(name: "speaker.plus")
          .bindTo(.replayGain, ofType: Preference.ReplayGainOption.self)
          .disableSubListOnTag(0)
          .hasDescription()
          .withHelpLink(AppData.gainAdjustmentHelpLink)
          .withDetailView {
            SettingsItem.Input()
              .bindTo(.replayGainPreamp)
              .trailingLabel(.text_dB)
              .hasDescription()
            SettingsItem.Switch()
              .bindTo(.replayGainClip)
              .hasDescription()
          }
        SettingsItem.Input()
          .image(name: "square.dotted")
          .bindTo(.replayGainFallback)
          .trailingLabel(.text_dB)
          .hasDescription()
      }
    }
  }

  private func sectionOther() -> SettingsSection {
    return section {
      SettingsList(title: .text_AudioOther) {
        SettingsItem.General(title: .gaplessAudioLabel)
          .image(name: "custom.waveform.2.arrow.trianglehead.2.clockwise.rotate.90")
          .withHelpLink(AppData.gaplessAudioHelpLink)
          .withDetailView(
            SettingsAccessory.Selection()
              .bindTo(.gaplessAudio, ofType: Preference.GaplessAudioOption.self)
          )
      }

      SettingsList {
        SettingsItem.General(title: .text_PreferredLanguage)
          .image(name: "character.book.closed")
          .withDetailView(
            SettingsAccessory.LanguageSelector()
              .bind(to: .audioLanguage)
          )
      }
    }
  }
}


fileprivate class AudioChannelRoutingView: NSObject, SettingsContainer, NSTextFieldDelegate {
  lazy var itemID = SettingsContainerUUID.next()

  let view = NSView()
  private let modePopUp = NSPopUpButton()
  private let leftSourcePopUp = NSPopUpButton()
  private let rightSourcePopUp = NSPopUpButton()
  private let assignmentStack = NSStackView()
  private let matrixStack = NSStackView()
  private var matrixFields: [String: (left: NSTextField, right: NSTextField)] = [:]
  private var builtView: NSView?

  func makeView() -> NSView {
    if let builtView {
      return builtView
    }

    view.translatesAutoresizingMaskIntoConstraints = false

    let modeRow = row(label: ui.localized(.audioChannelRoutingModeLabel), control: modePopUp)
    configureModePopUp()

    configureSourcePopUp(leftSourcePopUp, selected: Preference.string(for: .audioChannelRoutingLeftSource))
    configureSourcePopUp(rightSourcePopUp, selected: Preference.string(for: .audioChannelRoutingRightSource))
    leftSourcePopUp.action = #selector(sourcePopUpChanged(_:))
    rightSourcePopUp.action = #selector(sourcePopUpChanged(_:))

    assignmentStack.translatesAutoresizingMaskIntoConstraints = false
    assignmentStack.orientation = .vertical
    assignmentStack.spacing = 6
    assignmentStack.addArrangedSubview(row(label: ui.localized(.text_OutputChannel1), control: leftSourcePopUp))
    assignmentStack.addArrangedSubview(row(label: ui.localized(.text_OutputChannel2), control: rightSourcePopUp))

    matrixStack.translatesAutoresizingMaskIntoConstraints = false
    matrixStack.orientation = .vertical
    matrixStack.spacing = 6
    buildMatrixRows()

    let contentStack = NSStackView(views: [modeRow, assignmentStack, matrixStack])
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    contentStack.orientation = .vertical
    contentStack.alignment = .leading
    contentStack.spacing = 10
    view.addSubview(contentStack)
    contentStack.padding(.top(topConstraintOffset), .leading(SettingsSubList.indent), .trailing(8), .bottom(8))

    updateModeVisibility()
    builtView = view
    view.tag = itemID
    return view
  }

  func registerSearchEntry(context: SettingsSearch.Context) {
    context.add(itemID, ui.localized(.audioChannelRoutingModeLabel), isMain: true)
    context.add(itemID, ui.localized(.text_OutputChannel1))
    context.add(itemID, ui.localized(.text_OutputChannel2))
    context.add(itemID, ui.localized(.text_SourceChannel))
  }

  private func configureModePopUp() {
    modePopUp.translatesAutoresizingMaskIntoConstraints = false
    modePopUp.controlSize = .small
    modePopUp.target = self
    modePopUp.action = #selector(modePopUpChanged(_:))
    modePopUp.removeAllItems()
    for mode in Preference.AudioChannelRoutingMode.allCases {
      modePopUp.addItem(withTitle: ui.localized(.init("audioChannelRoutingMode.items.\(mode.rawValue)")))
      modePopUp.lastItem?.tag = mode.rawValue
    }
    modePopUp.selectItem(withTag: Preference.integer(for: .audioChannelRoutingMode))
  }

  private func configureSourcePopUp(_ popUp: NSPopUpButton, selected: String?) {
    popUp.translatesAutoresizingMaskIntoConstraints = false
    popUp.controlSize = .small
    popUp.target = self
    popUp.removeAllItems()
    for source in Preference.audioChannelRoutingSources {
      popUp.addItem(withTitle: "\(source.title) (\(source.id))")
      popUp.lastItem?.representedObject = source.id
    }
    if let selected,
       let item = popUp.itemArray.first(where: { $0.representedObject as? String == selected }) {
      popUp.select(item)
    }
  }

  private func buildMatrixRows() {
    let header = NSStackView()
    header.translatesAutoresizingMaskIntoConstraints = false
    header.orientation = .horizontal
    header.alignment = .centerY
    header.spacing = 8
    header.addArrangedSubview(headerLabel(ui.localized(.text_SourceChannel), width: 120))
    header.addArrangedSubview(headerLabel(ui.localized(.text_OutputChannel1), width: 62))
    header.addArrangedSubview(headerLabel(ui.localized(.text_OutputChannel2), width: 62))
    matrixStack.addArrangedSubview(header)

    for entry in Preference.audioChannelRoutingMatrixEntries() {
      let sourceTitle = Preference.audioChannelRoutingSources.first(where: { $0.id == entry.source })?.title ?? entry.source
      let leftField = gainField(entry.leftGain, source: entry.source, output: "left")
      let rightField = gainField(entry.rightGain, source: entry.source, output: "right")
      matrixFields[entry.source] = (leftField, rightField)

      let row = NSStackView(views: [
        headerLabel("\(sourceTitle) (\(entry.source))", width: 120),
        leftField,
        rightField
      ])
      row.translatesAutoresizingMaskIntoConstraints = false
      row.orientation = .horizontal
      row.alignment = .centerY
      row.spacing = 8
      matrixStack.addArrangedSubview(row)
    }

    let resetButton = NSButton(title: ui.localized(.text_Reset), target: self, action: #selector(resetMatrix))
    resetButton.controlSize = .small
    matrixStack.addArrangedSubview(resetButton)
  }

  private func row(label title: String, control: NSView) -> NSStackView {
    let label = headerLabel(title, width: 120)
    let stack = NSStackView(views: [label, control])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 8
    return stack
  }

  private func headerLabel(_ title: String, width: CGFloat) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.controlSize = .small
    label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    label.widthAnchor.constraint(equalToConstant: width).isActive = true
    return label
  }

  private func gainField(_ value: Double, source: String, output: String) -> NSTextField {
    let field = NSTextField()
    field.translatesAutoresizingMaskIntoConstraints = false
    field.controlSize = .small
    field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    field.alignment = .right
    field.stringValue = value.prettyFormat()
    field.identifier = NSUserInterfaceItemIdentifier("\(source).\(output)")
    field.delegate = self
    field.widthAnchor.constraint(equalToConstant: 62).isActive = true
    return field
  }

  @objc private func modePopUpChanged(_ sender: NSPopUpButton) {
    Preference.set(sender.selectedTag(), for: .audioChannelRoutingMode)
    updateModeVisibility()
  }

  @objc private func sourcePopUpChanged(_ sender: NSPopUpButton) {
    guard let source = sender.selectedItem?.representedObject as? String else { return }
    Preference.set(source, for: sender == leftSourcePopUp ? .audioChannelRoutingLeftSource : .audioChannelRoutingRightSource)
  }

  @objc private func resetMatrix() {
    Preference.set(Preference.audioChannelRoutingDefaultMatrix, for: .audioChannelRoutingMatrix)
    refreshMatrixFields()
  }

  func controlTextDidEndEditing(_ obj: Notification) {
    saveMatrixFields()
  }

  private func updateModeVisibility() {
    let mode = Preference.enum(for: .audioChannelRoutingMode) as Preference.AudioChannelRoutingMode
    assignmentStack.isHidden = mode != .assignment
    matrixStack.isHidden = mode != .customDownmix
  }

  private func refreshMatrixFields() {
    for entry in Preference.audioChannelRoutingMatrixEntries() {
      matrixFields[entry.source]?.left.stringValue = entry.leftGain.prettyFormat()
      matrixFields[entry.source]?.right.stringValue = entry.rightGain.prettyFormat()
    }
  }

  private func saveMatrixFields() {
    let entries = Preference.audioChannelRoutingSources.map { source -> (String, Double, Double) in
      let fields = matrixFields[source.id]
      let left = Double(fields?.left.stringValue ?? "") ?? 0
      let right = Double(fields?.right.stringValue ?? "") ?? 0
      return (source.id, left, right)
    }
    Preference.setAudioChannelRoutingMatrixEntries(entries)
    refreshMatrixFields()
  }
}


fileprivate enum AudioDriver: Int, InitializingFromKey, CaseIterable {
  case coreAudio = 0
  case avFoundation

  static var defaultValue = AudioDriver.coreAudio

  init?(key: Preference.Key) {
    self.init(rawValue: Preference.integer(for: key))
  }

  var description: String {
    switch self {
    case .coreAudio: "coreAudio"
    case .avFoundation: "avFoundation"
    }
  }
}


fileprivate class AudioOutputDeviceView: SettingsContainer {
  lazy var itemID = SettingsContainerUUID.next()

  let view: NSView
  let audioDevicePopUp: NSPopUpButton

  init() {
    self.view = NSView()
    self.audioDevicePopUp = NSPopUpButton()
  }

  func makeView() -> NSView {
    audioDevicePopUp.translatesAutoresizingMaskIntoConstraints = false
    audioDevicePopUp.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    audioDevicePopUp.removeAllItems()

    let audioDevices = PlayerCore.active.getAudioDevices()
    let audioDevice = Preference.string(for: .audioDevice)!

    var selected = false
    audioDevices.forEach { device in
      audioDevicePopUp.addItem(withTitle: device.description)
      audioDevicePopUp.lastItem!.representedObject = device
      if device.name == audioDevice {
        audioDevicePopUp.select(audioDevicePopUp.lastItem!)
        selected = true
      }
    }
    if !selected {
      // The configured audio device may not have been found because the configured audio output
      // driver was changed. Try and find the same audio device but with the currently configured
      // audio output driver.
      let description = Preference.string(for: .audioDeviceDesc)!
      let device = MPVAudioDevice(desc: description, name: audioDevice)
      let avfoundationEnabled = Preference.bool(for: PK.audioDriverEnableAVFoundation)
      let invalid = avfoundationEnabled ? "coreaudio" : "avfoundation"
      if device.driver == invalid {
        // The configured audio device is not for the currently configured audio output driver. Try
        // and find the same device with the configured driver.
        let driver = avfoundationEnabled ? "avfoundation" : "coreaudio"
        let replacement = MPVAudioDevice(device, driver)
        let index = audioDevicePopUp.indexOfItem(withTitle: String(describing: replacement))
        if index != -1 {
          // Update the audio device configured in settings with the corresponding device that is
          // for the currently configured audio output driver.
          Logger.log("""
              Audio output driver changed to \(driver), changing audio device setting
                from: \(audioDevice)
                to: \(replacement.name)
              """)
          audioDevicePopUp.selectItem(at: index)
          Preference.set(replacement.name, for: .audioDevice)
          selected = true
        }
      }
    }
    if !selected {
      let device = MPVAudioDevice(desc: Preference.string(for: .audioDeviceDesc)!,
                                  name: audioDevice, isMissing: true)
      audioDevicePopUp.addItem(withTitle: String(describing: device))
      audioDevicePopUp.lastItem!.representedObject = device
      audioDevicePopUp.select(audioDevicePopUp.lastItem!)
    }

    audioDevicePopUp.target = self
    audioDevicePopUp.action = #selector(audioDeviceAction)

    view.addSubview(audioDevicePopUp)
    audioDevicePopUp.padding(.top(topConstraintOffset), .bottom(8), .leading(SettingsSubList.indent), .trailing(8))

    return view
  }

  @objc func audioDeviceAction(_ sender: Any) {
    let device = audioDevicePopUp.selectedItem!.representedObject as! MPVAudioDevice
    Preference.set(device.name, for: .audioDevice)
    Preference.set(device.desc, for: .audioDeviceDesc)
  }
}
