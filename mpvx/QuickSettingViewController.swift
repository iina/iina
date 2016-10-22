//
//  QuickSettingViewController.swift
//  mpvx
//
//  Created by lhc on 12/8/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class QuickSettingViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

  override var nibName: String {
    return "QuickSettingViewController"
  }
  
  let distanceBetweenSliderAndIndicator: CGFloat = 18
  let sliderIndicatorHalfWidth:CGFloat = 16
  
  /**
   Similiar to the one in `PlaylistViewController`.
   Since IBOutlet is `nil` when the view is not loaded at first time,
   use this variable to cache which tab it need to switch to when the
   view is ready. The value will be handled after loaded.
   */
  private var pendingSwitchRequest: TabViewType?
  
  /** Tab type. Use TrackType for now. Propobably not a good choice. */
  typealias TabViewType = MPVTrack.TrackType
  
  var playerCore: PlayerCore = PlayerCore.shared
  weak var mainWindow: MainWindowController!
  
  @IBOutlet weak var videoTabBtn: NSButton!
  @IBOutlet weak var audioTabBtn: NSButton!
  @IBOutlet weak var subTabBtn: NSButton!
  @IBOutlet weak var tabView: NSTabView!
  
  @IBOutlet weak var videoTableView: NSTableView!
  @IBOutlet weak var audioTableView: NSTableView!
  @IBOutlet weak var subTableView: NSTableView!
  @IBOutlet weak var secSubTableView: NSTableView!
  
  @IBOutlet weak var rotateSegment: NSSegmentedControl!
  
  @IBOutlet weak var aspectSegment: NSSegmentedControl!
  @IBOutlet weak var customAspectTextField: NSTextField!
  
  @IBOutlet weak var speedSlider: NSSlider!
  @IBOutlet weak var speedSliderIndicator: NSTextField!
  @IBOutlet weak var customSpeedTextField: NSTextField!
  
  @IBOutlet weak var customAudioDelayTextField: NSTextField!
  @IBOutlet weak var audioDelaySliderIndicator: NSTextField!
  
  @IBOutlet weak var customSubDelayTextField: NSTextField!
  @IBOutlet weak var subDelaySliderIndicator: NSTextField!
  
  @IBOutlet weak var subScaleSlider: NSSlider!
  @IBOutlet weak var subScaleResetBtn: NSButton!
  
  @IBOutlet weak var subTextColorWell: NSColorWell!
  @IBOutlet weak var subTextSizePopUp: NSPopUpButton!
  @IBOutlet weak var subTextSBoldCheckBox: NSButton!
  @IBOutlet weak var subTextBorderColorWell: NSColorWell!
  @IBOutlet weak var subTextBorderWidthPopUp: NSPopUpButton!
  @IBOutlet weak var subTextBgColorWell: NSColorWell!
  
  
  
  
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
  }
  
  // MARK: - Validate UI
  
  /** Do syncronization*/
  override func viewDidAppear() {
    // image sub
    validateSubSettings()
  }
  
  private func validateSubSettings() {
    let currSub = playerCore.info.currentTrack(.sub)
    if currSub != nil && currSub!.isImageSub {
      subScaleSlider.isEnabled = false
    } else {
      subScaleSlider.isEnabled = true
    }
    // update values
    let currSubTextColor = playerCore.mpvController.getString(MPVOption.Subtitles.subColor)
    print(currSubTextColor)
    
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
    validateSubSettings()
  }
  
  private func withAllTableViews (_ block: (NSTableView, MPVTrack.TrackType) -> Void) {
    block(audioTableView, .audio)
    block(subTableView, .sub)
    block(secSubTableView, .secondSub)
    block(videoTableView, .video)
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
  }
  
  // Video tab
  
  @IBAction func aspectChangedAction(_ sender: NSSegmentedControl) {
    if let value = sender.label(forSegment: sender.selectedSegment) {
      playerCore.setVideoAspect(value)
      mainWindow.displayOSD(.aspect(value))
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
    //   0     1 ..     7  8    9 ..  26
    // -5x -4.5x .. -1.5x 1x 1.5x .. 10x
    let sliderValue = sender.doubleValue
    let value = sliderValue >= 8 ? (sliderValue / 2.0 - 3) : (sliderValue / 2.0 - 5)
    speedSliderIndicator.stringValue = "\(value)x"
    let knobPos = sender.knobPointPosition()
    speedSliderIndicator.setFrameOrigin(NSPoint(x: knobPos - sliderIndicatorHalfWidth, y: sender.frame.origin.y + distanceBetweenSliderAndIndicator))
    if let event = NSApp.currentEvent {
      if event.type == .leftMouseUp {
        playerCore.setSpeed(value)
        mainWindow.displayOSD(.speed(value))
      }
    }
  }
  
  @IBAction func customSpeedEditFinishedAction(_ sender: NSTextField) {
    let value = customSpeedTextField.doubleValue
    if (value >= 1 || value <= -1 || value == 0) && playerCore.info.playSpeed != value {
      let finalValue = value == 0 ? 1 : value
      playerCore.setSpeed(finalValue)
      mainWindow.displayOSD(.speed(finalValue))
    }
    if let window = sender.window {
      window.makeFirstResponder(window.contentView)
    }
  }
  
  // Audio tab
  
  @IBAction func loadExternalAudioAction(_ sender: NSButton) {
    Utility.quickOpenPanel(title: "Load external audio file") { url in
      self.playerCore.loadExternalAudioFile(url)
    }
    audioTableView.reloadData()
  }
  
  @IBAction func audioDelayChangedAction(_ sender: NSSlider) {
    let sliderValue = sender.doubleValue
    audioDelaySliderIndicator.stringValue = "\(sliderValue)s"
    let knobPos = sender.knobPointPosition()
    audioDelaySliderIndicator.setFrameOrigin(NSPoint(x: knobPos - sliderIndicatorHalfWidth, y: sender.frame.origin.y + distanceBetweenSliderAndIndicator))
    if let event = NSApp.currentEvent {
      if event.type == .leftMouseUp {
        playerCore.setAudioDelay(sliderValue)
        mainWindow.displayOSD(.audioDelay(sliderValue))
      }
    }
  }
  
  @IBAction func customAudioDelayEditFinishedAction(_ sender: AnyObject?) {
    let value = customAudioDelayTextField.doubleValue
    playerCore.setAudioDelay(value)
    mainWindow.displayOSD(.audioDelay(value))
  }
  
  // Sub tab
  
  @IBAction func loadExternalSubAction(_ sender: NSButton) {
    Utility.quickOpenPanel(title: "Load external subtitle") { url in
      self.playerCore.loadExternalSubFile(url)
    }
    subTableView.reloadData()
    secSubTableView.reloadData()
  }
  
  @IBAction func subDelayChangedAction(_ sender: NSSlider) {
    let sliderValue = sender.doubleValue
    subDelaySliderIndicator.stringValue = "\(sliderValue)s"
    let knobPos = sender.knobPointPosition()
    subDelaySliderIndicator.setFrameOrigin(NSPoint(x: knobPos - sliderIndicatorHalfWidth, y: sender.frame.origin.y + distanceBetweenSliderAndIndicator))
    if let event = NSApp.currentEvent {
      if event.type == .leftMouseUp {
        playerCore.setSubDelay(sliderValue)
        mainWindow.displayOSD(.subDelay(sliderValue))
      }
    }
  }
  
  @IBAction func customSubDelayEditFinishedAction(_ sender: AnyObject?) {
    let value = customSubDelayTextField.doubleValue
    playerCore.setSubDelay(value)
    mainWindow.displayOSD(.subDelay(value))
  }
  
  @IBAction func subScaleReset(_ sender: AnyObject) {
    playerCore.setSubScale(1)
    subScaleSlider.doubleValue = 0
    mainWindow.displayOSD(.subScale(1))
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
    mainWindow.displayOSD(.subScale(mappedValue))
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
  
  @IBAction func subTextBoldAction(_ sender: AnyObject) {
    playerCore.setSubTextBold(subTextSBoldCheckBox.state == NSOnState)
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
  
  
  
}
