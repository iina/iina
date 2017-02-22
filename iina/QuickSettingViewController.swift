//
//  QuickSettingViewController.swift
//  iina
//
//  Created by lhc on 12/8/16.
//  Copyright © 2016年 lhc. All rights reserved.
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

  weak var playerCore: PlayerCore! = PlayerCore.shared
  weak var mainWindow: MainWindowController!

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
    customSpeedTextField.formatter = DecimalFormatter()
    if pendingSwitchRequest != nil {
      switchToTab(pendingSwitchRequest!)
      pendingSwitchRequest = nil
    }

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
    aspectSegment.selectSegment(withLabel: playerCore.info.unsureAspect)
    cropSegment.selectSegment(withLabel: playerCore.info.unsureCrop)
    rotateSegment.selectSegment(withTag: AppData.rotations.index(of: playerCore.info.rotation) ?? -1)
    customSpeedTextField.doubleValue = playerCore.mpvController.getDouble(MPVOption.PlaybackControl.speed)
    deinterlaceCheckBtn.state = playerCore.info.deinterlace ? NSOnState : NSOffState

    // Audio
    customAudioDelayTextField.doubleValue = playerCore.mpvController.getDouble(MPVOption.Audio.audioDelay)

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
    customSubDelayTextField.doubleValue = playerCore.mpvController.getDouble(MPVOption.Subtitles.subDelay)

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
      return track?.readableTitle ?? Constants.String.none
    } else {
      return nil
    }
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    withAllTableViews { (view, type) in
      if view.numberOfSelectedRows > 0 {
        // note that track ids start from 1
        self.playerCore.setTrack(view.selectedRow, forType: type)
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

  // Tab buttons

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

  // Video tab

  @IBAction func aspectChangedAction(_ sender: NSSegmentedControl) {
    if let value = sender.label(forSegment: sender.selectedSegment) {
      playerCore.setVideoAspect(value)
      mainWindow.displayOSD(.aspect(value))
    }
  }

  @IBAction func cropChangedAction(_ sender: NSSegmentedControl) {
    if let cropStr = sender.label(forSegment: sender.selectedSegment) {
      playerCore.setCrop(fromString: cropStr)
      mainWindow.displayOSD(.crop(cropStr))
    }
  }

  @IBAction func rotationChangedAction(_ sender: NSSegmentedControl) {
    let value = [0, 90, 180, 270][sender.selectedSegment]
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

  @IBAction func speedChangedAction(_ sender: NSSlider) {
    // Each step is 64^(1/24)
    //   0       1   ..    7      8      9   ..   24
    // 0.250x 0.297x .. 0.841x 1.000x 1.189x .. 16.00x
    let sliderValue = sender.doubleValue
    let value = AppData.minSpeed * pow((AppData.maxSpeed / AppData.minSpeed), sliderValue / sliderSteps)
    let speed = (customSpeedTextField.formatter as? NumberFormatter)?.string(from: NSNumber(value: value)) ?? ""
    speedSliderIndicator.stringValue = "\(speed)x"
    customSpeedTextField.stringValue = speed
    let knobPos = sender.knobPointPosition()
    speedSliderConstraint.constant = knobPos - speedSliderIndicator.frame.width
    playerCore.setSpeed(value)
    view.layout()
  }

  @IBAction func customSpeedEditFinishedAction(_ sender: NSTextField) {
    var value = customSpeedTextField.doubleValue
    value = max(min(value, AppData.maxSpeed), AppData.minSpeed)
    customSpeedTextField.stringValue = (customSpeedTextField.formatter as? NumberFormatter)?.string(from: NSNumber(value: value)) ?? ""
    let sliderValue = log(value / AppData.minSpeed) / log(AppData.maxSpeed / AppData.minSpeed) * sliderSteps
    speedSlider.doubleValue = sliderValue
    if playerCore.info.playSpeed != value {
      playerCore.setSpeed(value)
    }
    if let window = sender.window {
      window.makeFirstResponder(window.contentView)
    }
    speedSliderConstraint.constant = speedSlider.knobPointPosition() - speedSliderIndicator.frame.width
    view.layout()
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

  // Audio tab

  @IBAction func loadExternalAudioAction(_ sender: NSButton) {
    let result = Utility.quickOpenPanel(title: "Load external audio file", isDir: false) { url in
      self.playerCore.loadExternalAudioFile(url)
    }
    if result {
      audioTableView.reloadData()
    }
  }

  @IBAction func audioDelayChangedAction(_ sender: NSSlider) {
    let sliderValue = sender.doubleValue
    let delay = (customSpeedTextField.formatter as? NumberFormatter)?.string(from: NSNumber(value: sliderValue)) ?? ""
    audioDelaySliderIndicator.stringValue = "\(delay)s"
    let knobPos = sender.knobPointPosition()
    audioDelaySliderConstraint.constant = knobPos - audioDelaySliderIndicator.frame.width
    if let event = NSApp.currentEvent {
      if event.type == .leftMouseUp {
        playerCore.setAudioDelay(sliderValue)
      }
    }
    view.layout()
  }

  @IBAction func customAudioDelayEditFinishedAction(_ sender: AnyObject?) {
    let value = customAudioDelayTextField.doubleValue
    playerCore.setAudioDelay(value)
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


  // Sub tab

  @IBAction func loadExternalSubAction(_ sender: NSButton) {
    let result = Utility.quickOpenPanel(title: "Load external subtitle", isDir: false) { url in
      self.playerCore.loadExternalSubFile(url)
    }
    if result {
      subTableView.reloadData()
      secSubTableView.reloadData()
    }
  }

  @IBAction func subDelayChangedAction(_ sender: NSSlider) {
    let sliderValue = sender.doubleValue
    let delay = (customSpeedTextField.formatter as? NumberFormatter)?.string(from: NSNumber(value: sliderValue)) ?? ""
    subDelaySliderIndicator.stringValue = "\(delay)s"
    let knobPos = sender.knobPointPosition()
    subDelaySliderConstraint.constant = knobPos - subDelaySliderIndicator.frame.width
    if let event = NSApp.currentEvent {
      if event.type == .leftMouseUp {
        playerCore.setSubDelay(sliderValue)
        customSubDelayTextField.doubleValue = sliderValue
      }
    }
    view.layout()
  }

  @IBAction func customSubDelayEditFinishedAction(_ sender: AnyObject?) {
    let value = customSubDelayTextField.doubleValue
    playerCore.setSubDelay(value)
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
