//
//  QuickSettingViewController.swift
//  iina
//
//  Created by lhc on 12/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class QuickSettingViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, SidebarViewController {

  override var nibName: String {
    return "QuickSettingViewController"
  }
  
  let sliderSteps = 24.0
  
  /**
   Similiar to the one in `PlaylistViewController`.
   Since IBOutlet is `nil` when the view is not loaded at first time,
   use this variable to cache which tab it need to switch to when the
   view is ready. The value will be handled after loaded.
   */
  private var pendingSwitchRequest: TabViewType?

  /** Tab type. Use TrackType for now. Propobably not a good choice. */
  typealias TabViewType = MPVTrack.TrackType

  weak var playerCore: PlayerCore!

  weak var mainWindow: MainWindowController! {
    didSet {
      self.playerCore = mainWindow.playerCore
    }
  }

  var currentTab: TabViewType = .video

  var observers: [NSObjectProtocol] = []


  @IBOutlet weak var videoTabBtn: NSButton!
  @IBOutlet weak var audioTabBtn: NSButton!
  @IBOutlet weak var subTabBtn: NSButton!
  @IBOutlet weak var tabView: NSTabView!

  @IBOutlet weak var buttonTopConstraint: NSLayoutConstraint!
	
  @IBOutlet weak var videoTableView: NSTableView!
  @IBOutlet weak var audioTableView: NSTableView!
  @IBOutlet weak var subTableView: NSTableView!
  @IBOutlet weak var secSubTableView: NSTableView!

  @IBOutlet weak var rotateSegment: NSSegmentedControl!

  @IBOutlet weak var aspectSegment: NSSegmentedControl!
  @IBOutlet weak var customAspectTextField: NSTextField!

  @IBOutlet weak var cropSegment: NSSegmentedControl!

  @IBOutlet weak var speedSlider: NSSlider!
  @IBOutlet weak var speedSliderIndicator: NSTextField!
  @IBOutlet weak var speedSliderConstraint: NSLayoutConstraint!
  @IBOutlet weak var customSpeedTextField: NSTextField!
  @IBOutlet weak var deinterlaceCheckBtn: NSButton!

  @IBOutlet weak var brightnessSlider: NSSlider!
  @IBOutlet weak var contrastSlider: NSSlider!
  @IBOutlet weak var saturationSlider: NSSlider!
  @IBOutlet weak var gammaSlider: NSSlider!
  @IBOutlet weak var hueSlider: NSSlider!

  @IBOutlet weak var audioDelaySlider: NSSlider!
  @IBOutlet weak var audioDelaySliderIndicator: NSTextField!
  @IBOutlet weak var audioDelaySliderConstraint: NSLayoutConstraint!
  @IBOutlet weak var customAudioDelayTextField: NSTextField!
	
	
  @IBOutlet weak var subLoadSementedControl: NSSegmentedControl!
  @IBOutlet weak var subDelaySlider: NSSlider!
  @IBOutlet weak var subDelaySliderIndicator: NSTextField!
  @IBOutlet weak var subDelaySliderConstraint: NSLayoutConstraint!
  @IBOutlet weak var customSubDelayTextField: NSTextField!
	
  @IBOutlet weak var audioEqSlider1: NSSlider!
  @IBOutlet weak var audioEqSlider2: NSSlider!
  @IBOutlet weak var audioEqSlider3: NSSlider!
  @IBOutlet weak var audioEqSlider4: NSSlider!
  @IBOutlet weak var audioEqSlider5: NSSlider!
  @IBOutlet weak var audioEqSlider6: NSSlider!
  @IBOutlet weak var audioEqSlider7: NSSlider!
  @IBOutlet weak var audioEqSlider8: NSSlider!
  @IBOutlet weak var audioEqSlider9: NSSlider!
  @IBOutlet weak var audioEqSlider10: NSSlider!

  @IBOutlet weak var subScaleSlider: NSSlider!
  @IBOutlet weak var subScaleResetBtn: NSButton!
  @IBOutlet weak var subPosSlider: NSSlider!

  @IBOutlet weak var subTextColorWell: NSColorWell!
  @IBOutlet weak var subTextSizePopUp: NSPopUpButton!
  @IBOutlet weak var subTextBorderColorWell: NSColorWell!
  @IBOutlet weak var subTextBorderWidthPopUp: NSPopUpButton!
  @IBOutlet weak var subTextBgColorWell: NSColorWell!
  @IBOutlet weak var subTextFontBtn: NSButton!

  var downShift: CGFloat = 0 {
    didSet {
      buttonTopConstraint.constant = downShift
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    withAllTableViews { (view, _) in
      view.delegate = self
      view.dataSource = self
      view.superview?.superview?.layer?.cornerRadius = 4
    }
    if pendingSwitchRequest != nil {
      switchToTab(pendingSwitchRequest!)
      pendingSwitchRequest = nil
    }

    subLoadSementedControl.image(forSegment: 1)?.isTemplate = true

    // notifications
    let tracklistChangeObserver = NotificationCenter.default.addObserver(forName: Constants.Noti.tracklistChanged, object: nil, queue: OperationQueue.main) { _ in
      self.playerCore.getTrackInfo()
      self.withAllTableViews { $0.0.reloadData() }
    }
    observers.append(tracklistChangeObserver)
    let afChangeObserver = NotificationCenter.default.addObserver(forName: Constants.Noti.afChanged, object: nil, queue: OperationQueue.main) { _ in
      self.updateAudioEqState()
    }
    observers.append(afChangeObserver)
  }

  // MARK: - Validate UI

  /** Do syncronization*/
  override func viewDidAppear() {
    // image sub
    super.viewDidAppear()
    updateControlsState()
  }

  deinit {
    observers.forEach {
      NotificationCenter.default.removeObserver($0)
    }
  }

  private func updateControlsState() {
    // Video
    if let index = AppData.aspectsInPanel.index(of: playerCore.info.unsureAspect) {
      aspectSegment.selectedSegment = index
    }
    if let index = AppData.cropsInPanel.index(of: playerCore.info.unsureCrop) {
      cropSegment.selectedSegment = index
    }
    rotateSegment.selectSegment(withTag: AppData.rotations.index(of: playerCore.info.rotation) ?? -1)
    deinterlaceCheckBtn.state = playerCore.info.deinterlace ? NSOnState : NSOffState
    let speed = playerCore.mpvController.getDouble(MPVOption.PlaybackControl.speed)
    customSpeedTextField.doubleValue = speed
    let sliderValue = log(speed / AppData.minSpeed) / log(AppData.maxSpeed / AppData.minSpeed) * sliderSteps
    speedSlider.doubleValue = sliderValue
    redraw(indicator: speedSliderIndicator, constraint: speedSliderConstraint, slider: speedSlider, value: "\(customSpeedTextField.stringValue)x")

    // Audio
    let audioDelay = playerCore.mpvController.getDouble(MPVOption.Audio.audioDelay)
    audioDelaySlider.doubleValue = audioDelay
    customAudioDelayTextField.doubleValue = audioDelay
    redraw(indicator: audioDelaySliderIndicator, constraint: audioDelaySliderConstraint, slider: audioDelaySlider, value: "\(customAudioDelayTextField.stringValue)s")

    // Sub
    if let currSub = playerCore.info.currentTrack(.sub) {
      subScaleSlider.isEnabled = !currSub.isImageSub
      // FIXME: CollorWells cannot be disable?
      let enableTextSettings = !(currSub.isAssSub || currSub.isImageSub)
      [subTextColorWell, subTextSizePopUp, subTextBgColorWell, subTextBorderColorWell, subTextBorderWidthPopUp, subTextFontBtn].forEach { $0.isEnabled = enableTextSettings }
    }

    let currSubScale = playerCore.mpvController.getDouble(MPVOption.Subtitles.subScale).constrain(min: 0.1, max: 10)
    let displaySubScale = Utility.toDisplaySubScale(fromRealSubScale: currSubScale)
    subScaleSlider.doubleValue = displaySubScale + (displaySubScale > 0 ? -1 : 1)
    let subDelay = playerCore.mpvController.getDouble(MPVOption.Subtitles.subDelay)
    subDelaySlider.doubleValue = subDelay
    customSubDelayTextField.doubleValue = subDelay
    redraw(indicator: subDelaySliderIndicator, constraint: subDelaySliderConstraint, slider: subDelaySlider, value: "\(customSubDelayTextField.stringValue)s")

    let currSubPos = playerCore.mpvController.getInt(MPVOption.Subtitles.subPos)
    subPosSlider.intValue = Int32(currSubPos)

    let fontSize = playerCore.mpvController.getInt(MPVOption.Subtitles.subFontSize)
    subTextSizePopUp.selectItem(withTitle: fontSize.toStr())

    let borderWidth = playerCore.mpvController.getDouble(MPVOption.Subtitles.subBorderSize)
    subTextBorderWidthPopUp.selectItem(at: -1)
    subTextBorderWidthPopUp.itemArray.forEach { item in
      if borderWidth == Double(item.title) {
        subTextBorderWidthPopUp.select(item)
      }
    }

    // Equalizer
    updateVideoEqState()
    updateAudioEqState()
  }

  private func updateVideoEqState() {
    brightnessSlider.intValue = Int32(playerCore.info.brightness)
    contrastSlider.intValue = Int32(playerCore.info.contrast)
    saturationSlider.intValue = Int32(playerCore.info.saturation)
    gammaSlider.intValue = Int32(playerCore.info.gamma)
    hueSlider.intValue = Int32(playerCore.info.hue)
  }

  private func updateAudioEqState() {
    if let filter = playerCore.info.audioEqFilter {
      withAllAudioEqSliders { slider in
        slider.doubleValue = Double( filter.params!["e\(slider.tag)"] ?? "" ) ?? 0
      }
    } else {
      withAllAudioEqSliders { $0.doubleValue = 0 }
    }
  }

  func reloadSubtitlesData() {
    guard isViewLoaded else {
      return
    }
    subTableView.reloadData()
    secSubTableView.reloadData()
  }

  // MARK: - Switch tab

  /** Switch tab (call from other objects) */
  func pleaseSwitchToTab(_ tab: TabViewType) {
    if isViewLoaded {
      switchToTab(tab)
    } else {
      // cache the request
      pendingSwitchRequest = tab
    }
  }

  /** Switch tab (for internal call) */
  private func switchToTab(_ tab: TabViewType) {
    let button: NSButton
    let tabIndex: Int
    switch tab {
    case .video:
      button = videoTabBtn
      tabIndex = 0
    case .audio:
      button = audioTabBtn
      tabIndex = 1
    case .sub:
      button = subTabBtn
      tabIndex = 2
    default:
      return
    }
    tabView.selectTabViewItem(at: tabIndex)
    // cancel current active button
    for btn in [videoTabBtn, audioTabBtn, subTabBtn] {
      if let btn = btn {
        let title = btn.title
        btn.attributedTitle = NSAttributedString(string: title, attributes: Utility.tabTitleFontAttributes)
      }
    }
    // the active one
    let title = button.title
    button.attributedTitle = NSAttributedString(string: title, attributes: Utility.tabTitleActiveFontAttributes)

    currentTab = tab
  }

  // MARK: - NSTableView delegate

  func numberOfRows(in tableView: NSTableView) -> Int {
    if tableView == videoTableView {
      return playerCore.info.videoTracks.count + 1
    } else if tableView == audioTableView {
      return playerCore.info.audioTracks.count + 1
    } else if tableView == subTableView || tableView == secSubTableView {
      return playerCore.info.subTracks.count + 1
    } else {
      return 0
    }
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    // get track according to tableview
    // row=0: <None> row=1~: tracks[row-1]
    let track: MPVTrack?
    let activeId: Int
    let columnName = tableColumn?.identifier
    if tableView == videoTableView {
      track = row == 0 ? nil : playerCore.info.videoTracks[row-1]
      activeId = playerCore.info.vid!
    } else if tableView == audioTableView {
      track = row == 0 ? nil : playerCore.info.audioTracks[row-1]
      activeId = playerCore.info.aid!
    } else if tableView == subTableView {
      track = row == 0 ? nil : playerCore.info.subTracks[row-1]
      activeId = playerCore.info.sid!
    } else if tableView == secSubTableView {
      track = row == 0 ? nil : playerCore.info.subTracks[row-1]
      activeId = playerCore.info.secondSid!
    } else {
      return nil
    }
    // return track data
    if columnName == Constants.Identifier.isChosen {
      let isChosen = track == nil ? (activeId == 0) : (track!.id == activeId)
      return isChosen ? Constants.String.dot : ""
    } else if columnName == Constants.Identifier.trackName {
      return track?.readableTitle ?? Constants.String.trackNone
    } else {
      return nil
    }
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    withAllTableViews { (view, type) in
      if view.numberOfSelectedRows > 0 {
        // note that track ids start from 1
        let subId = view.selectedRow > 0 ? playerCore.info.trackList(type)[view.selectedRow-1].id : 0
        self.playerCore.setTrack(subId, forType: type)
        view.deselectAll(self)
        view.reloadData()
      }
    }
    // Revalidate layout and controls
    updateControlsState()
  }

  private func withAllTableViews (_ block: (NSTableView, MPVTrack.TrackType) -> Void) {
    block(audioTableView, .audio)
    block(subTableView, .sub)
    block(secSubTableView, .secondSub)
    block(videoTableView, .video)
  }

  private func withAllAudioEqSliders(_ block: (NSSlider) -> Void) {
    [audioEqSlider1, audioEqSlider2, audioEqSlider3, audioEqSlider4, audioEqSlider5,
     audioEqSlider6, audioEqSlider7, audioEqSlider8, audioEqSlider9, audioEqSlider10].forEach {
      block($0)
    }
  }

  // MARK: - Actions

  // MARK: Tab buttons

  @IBAction func tabBtnAction(_ sender: NSButton) {
    tabView.selectTabViewItem(at: sender.tag)
    // cancel current active button
    [videoTabBtn, audioTabBtn, subTabBtn].forEach { btn in
      if let btn = btn {
        let title = btn.title
        btn.attributedTitle = NSAttributedString(string: title, attributes: Utility.tabTitleFontAttributes)
      }
    }
    // the active one
    let title = sender.title
    sender.attributedTitle = NSAttributedString(string: title, attributes: Utility.tabTitleActiveFontAttributes)
    updateControlsState()
  }

  // MARK: Video tab

  @IBAction func aspectChangedAction(_ sender: NSSegmentedControl) {
    let aspect = AppData.aspectsInPanel[sender.selectedSegment]
    playerCore.setVideoAspect(aspect)
    mainWindow.displayOSD(.aspect(aspect))
  }

  @IBAction func cropChangedAction(_ sender: NSSegmentedControl) {
    let cropStr = AppData.cropsInPanel[sender.selectedSegment]
    playerCore.setCrop(fromString: cropStr)
    mainWindow.displayOSD(.crop(cropStr))
  }

  @IBAction func rotationChangedAction(_ sender: NSSegmentedControl) {
    let value = AppData.rotations[sender.selectedSegment]
    playerCore.setVideoRotate(value)
    mainWindow.displayOSD(.rotate(value))
  }

  @IBAction func customAspectEditFinishedAction(_ sender: AnyObject?) {
    let value = customAspectTextField.stringValue
    if value != "" {
      aspectSegment.setSelected(false, forSegment: aspectSegment.selectedSegment)
      playerCore.setVideoAspect(value)
      mainWindow.displayOSD(.aspect(value))
    }
  }

  private func redraw(indicator: NSTextField, constraint: NSLayoutConstraint, slider: NSSlider, value: String) {
    indicator.stringValue = value
    let offset: CGFloat = 6
    let sliderInnerWidth = slider.frame.width - offset * 2
    constraint.constant = offset + sliderInnerWidth * CGFloat((slider.doubleValue - slider.minValue) / (slider.maxValue - slider.minValue))
    view.layout()
  }

  @IBAction func speedChangedAction(_ sender: NSSlider) {
    // Each step is 64^(1/24)
    //   0       1   ..    7      8      9   ..   24
    // 0.250x 0.297x .. 0.841x 1.000x 1.189x .. 16.00x
    let eventType = NSApp.currentEvent!.type
    if eventType == .leftMouseDown {
      sender.allowsTickMarkValuesOnly = true
    }
    if eventType == .leftMouseUp {
      sender.allowsTickMarkValuesOnly = false
    }
    let sliderValue = sender.doubleValue
    let value = AppData.minSpeed * pow(AppData.maxSpeed / AppData.minSpeed, sliderValue / sliderSteps)
    customSpeedTextField.doubleValue = value
    playerCore.setSpeed(value)
    redraw(indicator: speedSliderIndicator, constraint: speedSliderConstraint, slider: speedSlider, value: "\(customSpeedTextField.stringValue)x")
  }

  @IBAction func customSpeedEditFinishedAction(_ sender: NSTextField) {
    if sender.stringValue.isEmpty {
      sender.stringValue = "1"
    }
    let value = customSpeedTextField.doubleValue
    let sliderValue = log(value / AppData.minSpeed) / log(AppData.maxSpeed / AppData.minSpeed) * sliderSteps
    speedSlider.doubleValue = sliderValue
    if playerCore.info.playSpeed != value {
      playerCore.setSpeed(value)
    }
    redraw(indicator: speedSliderIndicator, constraint: speedSliderConstraint, slider: speedSlider, value: "\(sender.stringValue)x")
    if let window = sender.window {
      window.makeFirstResponder(window.contentView)
    }
  }

  @IBAction func deinterlaceBtnAction(_ sender: AnyObject) {
    playerCore.toggleDeinterlace(deinterlaceCheckBtn.state == NSOnState)
  }

  @IBAction func equalizerSliderAction(_ sender: NSSlider) {
    let type: PlayerCore.VideoEqualizerType
    switch sender {
    case brightnessSlider:
      type = .brightness
    case contrastSlider:
      type = .contrast
    case saturationSlider:
      type = .saturation
    case gammaSlider:
      type = .gamma
    case hueSlider:
      type = .hue
    default:
      return
    }
    playerCore.setVideoEqualizer(forOption: type, value: Int(sender.intValue))
  }

  // use tag for buttons
  @IBAction func resetEqualizerBtnAction(_ sender: NSButton) {
    let type: PlayerCore.VideoEqualizerType
    let slider: NSSlider?
    switch sender.tag {
    case 0:
      type = .brightness
      slider = brightnessSlider
    case 1:
      type = .contrast
      slider = contrastSlider
    case 2:
      type = .saturation
      slider = saturationSlider
    case 3:
      type = .gamma
      slider = gammaSlider
    case 4:
      type = .hue
      slider = hueSlider
    default:
      return
    }
    playerCore.setVideoEqualizer(forOption: type, value: 0)
    slider?.intValue = 0
  }

  @IBAction func cropBtnAcction(_ sender: AnyObject) {
    mainWindow.hideSideBar {
      self.mainWindow.enterInteractiveMode()
    }
  }

  // MARK: Audio tab

  @IBAction func loadExternalAudioAction(_ sender: NSButton) {
    let currentDir = playerCore.info.currentURL?.deletingLastPathComponent()
    Utility.quickOpenPanel(title: "Load external audio file", isDir: false, dir: currentDir) { url in
      self.playerCore.loadExternalAudioFile(url)
      self.audioTableView.reloadData()
    }
  }

  @IBAction func audioDelayChangedAction(_ sender: NSSlider) {
    let eventType = NSApp.currentEvent!.type
    if eventType == .leftMouseDown {
      sender.allowsTickMarkValuesOnly = true
    }
    if eventType == .leftMouseUp {
      sender.allowsTickMarkValuesOnly = false
    }
    let sliderValue = sender.doubleValue
    customAudioDelayTextField.doubleValue = sliderValue
    redraw(indicator: audioDelaySliderIndicator, constraint: audioDelaySliderConstraint, slider: audioDelaySlider, value: "\(customAudioDelayTextField.stringValue)s")
    if let event = NSApp.currentEvent {
      if event.type == .leftMouseUp {
        playerCore.setAudioDelay(sliderValue)
      }
    }
  }

  @IBAction func customAudioDelayEditFinishedAction(_ sender: NSTextField) {
    if sender.stringValue.isEmpty {
      sender.stringValue = "0"
    }
    let value = sender.doubleValue
    playerCore.setAudioDelay(value)
    audioDelaySlider.doubleValue = value
    redraw(indicator: audioDelaySliderIndicator, constraint: audioDelaySliderConstraint, slider: audioDelaySlider, value: "\(sender.stringValue)s")
  }

  @IBAction func audioEqSliderAction(_ sender: NSSlider) {
    let params: [String: String] = [
      "e0": audioEqSlider1.stringValue,
      "e1": audioEqSlider2.stringValue,
      "e2": audioEqSlider3.stringValue,
      "e3": audioEqSlider4.stringValue,
      "e4": audioEqSlider5.stringValue,
      "e5": audioEqSlider6.stringValue,
      "e6": audioEqSlider7.stringValue,
      "e7": audioEqSlider8.stringValue,
      "e8": audioEqSlider9.stringValue,
      "e9": audioEqSlider10.stringValue,
    ]
    let filter = MPVFilter(name: "equalizer", label: nil, params: params)
    playerCore.setAudioEq(fromFilter: filter)
  }

  @IBAction func resetAudioEqAction(_ sender: AnyObject) {
    playerCore.removeAudioEqFilter()
  }


  // MARK: Sub tab

  @IBAction func loadExternalSubAction(_ sender: NSSegmentedControl) {
    if sender.selectedSegment == 0 {
      let currentDir = playerCore.info.currentURL?.deletingLastPathComponent()
      Utility.quickOpenPanel(title: "Load external subtitle", isDir: false, dir: currentDir) { url in
        self.playerCore.loadExternalSubFile(url)
        self.subTableView.reloadData()
        self.secSubTableView.reloadData()
      }
    } else if sender.selectedSegment == 1 {
      let activeSubs = playerCore.info.trackList(.sub) + playerCore.info.trackList(.secondSub)
      let menu = NSMenu()
      menu.autoenablesItems = false
      if playerCore.info.currentSubsInfo.isEmpty {
        menu.addItem(withTitle: NSLocalizedString("track.none", comment: "<None>"))
      } else {
        if let videoInfo = playerCore.info.currentVideosInfo.first(where: { $0.url == playerCore.info.currentURL }),
          !videoInfo.relatedSubs.isEmpty {
          videoInfo.relatedSubs.forEach { sub in
            let isActive = activeSubs.contains { $0.externalFilename == sub.path }
            menu.addItem(withTitle: "\(sub.filename).\(sub.ext)", action: #selector(self.chosenSubFromMenu(_:)), tag: nil, obj: sub, stateOn: isActive)
          }
          menu.addItem(NSMenuItem.separator())
        }
        playerCore.info.currentSubsInfo.sorted { (f1, f2) in
          return f1.filename.localizedStandardCompare(f2.filename) == .orderedAscending
        }.forEach { sub in
          let isActive = activeSubs.contains { $0.externalFilename == sub.path }
          menu.addItem(withTitle: "\(sub.filename).\(sub.ext)", action: #selector(self.chosenSubFromMenu(_:)), tag: nil, obj: sub, stateOn: isActive)
        }
      }
      NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent!, for: sender)
    }
  }

  @objc
  private func chosenSubFromMenu(_ sender: NSMenuItem) {
    guard let fileInfo = sender.representedObject as? FileInfo else { return }
    playerCore.loadExternalSubFile(fileInfo.url)
  }

  @IBAction func searchOnlineAction(_ sender: AnyObject) {
    mainWindow.menuFindOnlineSub(.dummy)
  }

  @IBAction func subDelayChangedAction(_ sender: NSSlider) {
    let eventType = NSApp.currentEvent!.type
    if eventType == .leftMouseDown {
      sender.allowsTickMarkValuesOnly = true
    }
    if eventType == .leftMouseUp {
      sender.allowsTickMarkValuesOnly = false
    }
    let sliderValue = sender.doubleValue
    customSubDelayTextField.doubleValue = sliderValue
    redraw(indicator: subDelaySliderIndicator, constraint: subDelaySliderConstraint, slider: subDelaySlider, value: "\(customSubDelayTextField.stringValue)s")
    if let event = NSApp.currentEvent {
      if event.type == .leftMouseUp {
        playerCore.setSubDelay(sliderValue)
      }
    }
  }

  @IBAction func customSubDelayEditFinishedAction(_ sender: NSTextField) {
    if sender.stringValue.isEmpty {
      sender.stringValue = "0"
    }
    let value = sender.doubleValue
    playerCore.setSubDelay(value)
    subDelaySlider.doubleValue = value
    redraw(indicator: subDelaySliderIndicator, constraint: subDelaySliderConstraint, slider: subDelaySlider, value: "\(sender.stringValue)s")
  }

  @IBAction func subScaleReset(_ sender: AnyObject) {
    playerCore.setSubScale(1)
    subScaleSlider.doubleValue = 0
  }

  @IBAction func subPosSliderAction(_ sender: NSSlider) {
    playerCore.setSubPos(Int(sender.intValue))
  }

  @IBAction func subScaleSliderAction(_ sender: NSSlider) {
    let value = sender.doubleValue
    let mappedValue: Double, realValue: Double
    // map [-10, -1], [1, 10] to [-9, 9], bounds may change in future
    if value > 0 {
      mappedValue = round((value + 1) * 20) / 20
      realValue = mappedValue
    } else {
      mappedValue = round((value - 1) * 20) / 20
      realValue = 1 / mappedValue
    }
    playerCore.setSubScale(realValue)
  }

  @IBAction func subTextColorAction(_ sender: AnyObject) {
    playerCore.setSubTextColor(subTextColorWell.color.mpvColorString)
  }

  @IBAction func subTextSizeAction(_ sender: AnyObject) {
    if let selectedItem = subTextSizePopUp.selectedItem {
      if let value = Double(selectedItem.title) {
        playerCore.setSubTextSize(value)
      }
    }
  }

  @IBAction func subTextBorderColorAction(_ sender: AnyObject) {
    playerCore.setSubTextBorderColor(subTextBorderColorWell.color.mpvColorString)
  }

  @IBAction func subTextBorderWidthAction(_ sender: AnyObject) {
    if let value = Double(subTextBorderWidthPopUp.stringValue) {
      playerCore.setSubTextBorderSize(value)
    }
  }

  @IBAction func subTextBgColorAction(_ sender: AnyObject) {
    playerCore.setSubTextBgColor(subTextBgColorWell.color.mpvColorString)
  }

  @IBAction func subFontAction(_ sender: AnyObject) {
    Utility.quickFontPickerWindow() {
      self.playerCore.setSubFont($0 ?? "")
    }
  }


}
