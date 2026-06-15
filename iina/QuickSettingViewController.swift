//
//  QuickSettingViewController.swift
//  iina
//
//  Created by lhc on 12/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate let tabConfig = [
  ("Layout", NSImage.sf("paintpalette.fill"), 0),
  ("Video", NSImage.tabVideo, 1),
  ("Audio", NSImage.tabAudio, 2),
  ("Subtitles", NSImage.tabSub, 3),
]

class QuickSettingViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, SidebarViewController {
  override var nibName: NSNib.Name {
    return NSNib.Name("QuickSettingViewController")
  }

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow
    self.player = mainWindow.player
    super.init(nibName: nil, bundle: nil)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  enum TabViewType: Equatable {
    case layout
    case video
    case audio
    case sub

    init(buttonTag: Int) {
      self = [.layout, .video, .audio, .sub][at: buttonTag] ?? .video
    }

    init?(name: String) {
      switch name {
      case "layout":
        self = .layout
      case "video":
        self = .video
      case "audio":
        self = .audio
      case "sub":
        self = .sub
      default:
        self = .video
      }
    }

    var buttonTag: Int {
      switch self {
      case .layout: return 0
      case .video: return 1
      case .audio: return 2
      case .sub: return 3
      }
    }

    var name: String {
      switch self {
      case .layout: return "layout"
      case .video: return "video"
      case .audio: return "audio"
      case .sub: return "sub"
      }
    }
  }

  /**
   Similar to the one in `PlaylistViewController`.
   Since IBOutlet is `nil` when the view is not loaded at first time,
   use this variable to cache which tab it need to switch to when the
   view is ready. The value will be handled after loaded.
   */
  private var pendingSwitchRequest: TabViewType?

  unowned let player: PlayerCore
  unowned let mainWindow: MainWindowController
  private let ui = UIHelper()
  private let prefObserver = Preference.Observer()

  var currentTab: TabViewType = .video

  private var tabButtonsStackView: NSStackView!
  private var tabButtonsSegmentControl: NSSegmentedControl!
  private var tabButtonsLeadingConstraint: NSLayoutConstraint!
  private var tabButtonsTrailingConstraint: NSLayoutConstraint!
  private var tabButtonsHeightConstraint: NSLayoutConstraint!
  private var topConstraint: NSLayoutConstraint!

  private var tabViewController: NSTabViewController!
  private var layoutTabBtn: NSButton!
  private var videoTabBtn: NSButton!
  private var audioTabBtn: NSButton!
  private var subTabBtn: NSButton!
  private var dismissBtn: NSButton!
  private var closeSidebarBtn: NSButton!
  private var closeSidebarBtnSizeConstraint: NSLayoutConstraint!

  private var layoutTabScrollView: SidebarScrollView!
  private var videoTabScrollView: SidebarScrollView!
  private var audioTabScrollView: SidebarScrollView!
  @IBOutlet weak var subtitlesTabScrollView: SidebarScrollView!

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
  @IBOutlet weak var speedSliderContainerView: NSView!

  @IBOutlet weak var speedSlider0_25xLabel: NSTextField!
  @IBOutlet weak var speedSlider1xLabel: NSTextField!
  @IBOutlet weak var speedSlider4xLabel: NSTextField!
  @IBOutlet weak var speedSlider16xLabel: NSTextField!
  @IBOutlet var speedSlider1xLabelCenterXConstraint: NSLayoutConstraint!
  @IBOutlet var speedSlider4xLabelCenterXConstraint: NSLayoutConstraint!
  @IBOutlet var speedSlider1xLabelPrevLabelConstraint: NSLayoutConstraint!
  @IBOutlet var speedSlider4xLabelPrevLabelConstraint: NSLayoutConstraint!
  @IBOutlet var speedSlider16xLabelPrevLabelConstraint: NSLayoutConstraint!

  @IBOutlet weak var customSpeedTextField: NSTextField!
  @IBOutlet weak var speedResetBtn: NSButton!
  @IBOutlet weak var switchHorizontalLine: NSBox!
  @IBOutlet weak var switchHorizontalLine2: NSBox!
  @IBOutlet weak var hardwareDecodingSwitch: NSSwitch!
  @IBOutlet weak var deinterlaceSwitch: NSSwitch!
  @IBOutlet weak var hdrSwitch: NSSwitch!
  @IBOutlet weak var hardwareDecodingLabel: NSTextField!
  @IBOutlet weak var deinterlaceLabel: NSTextField!
  @IBOutlet weak var hdrLabel: NSTextField!

  @IBOutlet weak var brightnessSlider: NSSlider!
  @IBOutlet weak var contrastSlider: NSSlider!
  @IBOutlet weak var saturationSlider: NSSlider!
  @IBOutlet weak var gammaSlider: NSSlider!
  @IBOutlet weak var hueSlider: NSSlider!

  @IBOutlet weak var audioDelaySlider: NSSlider!
  @IBOutlet weak var audioDelaySliderIndicator: NSTextField!
  @IBOutlet weak var audioDelaySliderConstraint: NSLayoutConstraint!
  @IBOutlet weak var customAudioDelayTextField: NSTextField!

  @IBOutlet weak var hideSwitch: NSSwitch!
  @IBOutlet weak var secHideSwitch: NSSwitch!
  @IBOutlet weak var subLoadSegmentedControl: NSSegmentedControl!
  @IBOutlet weak var subDelaySlider: NSSlider!
  @IBOutlet weak var subDelaySliderIndicator: NSTextField!
  @IBOutlet weak var subDelaySliderConstraint: NSLayoutConstraint!
  @IBOutlet weak var customSubDelayTextField: NSTextField!
  @IBOutlet weak var subSegmentedControl: NSSegmentedControl!

  @IBOutlet weak var eqPopUpButton: NSPopUpButton!
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

  var subTextColorWell: NSColorWell!
  var subTextBorderColorWell: NSColorWell!
  var subTextBgColorWell: NSColorWell!

  @IBOutlet weak var subTextColorWellContainer: NSView!
  @IBOutlet weak var subTextSizePopUp: NSPopUpButton!
  @IBOutlet weak var subTextBorderColorWellContainer: NSView!
  @IBOutlet weak var subTextBorderWidthPopUp: NSPopUpButton!
  @IBOutlet weak var subTextBgColorWellContainer: NSView!
  @IBOutlet weak var subTextFontBtn: NSButton!

  @IBOutlet weak var subtitleSwitch: NSSwitch!
  @IBOutlet weak var secondarySubtitleSwitch: NSSwitch!
  
  private lazy var audioEQSliders: [NSSlider] = [
    audioEqSlider1, audioEqSlider2, audioEqSlider3, audioEqSlider4, audioEqSlider5,
    audioEqSlider6, audioEqSlider7, audioEqSlider8, audioEqSlider9, audioEqSlider10
  ]

  private lazy var videoEQSliders: [NSSlider] = [
    brightnessSlider, contrastSlider, saturationSlider, gammaSlider, hueSlider
  ]

  private var inputString: String = ""

  var downShift: CGFloat = 0 {
    didSet {
      topConstraint.constant = downShift
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    self.tabButtonsStackView = NSStackView()
    tabButtonsStackView.translatesAutoresizingMaskIntoConstraints = false
    tabButtonsStackView.orientation = .horizontal
    view.addSubview(tabButtonsStackView)
    topConstraint = tabButtonsStackView.topAnchor.constraint(equalTo: view.topAnchor)
    topConstraint.isActive = true
    tabButtonsLeadingConstraint = tabButtonsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
    tabButtonsLeadingConstraint.isActive = true
    tabButtonsTrailingConstraint = view.trailingAnchor.constraint(equalTo: tabButtonsStackView.trailingAnchor)
    tabButtonsTrailingConstraint.isActive = true
    tabButtonsHeightConstraint = tabButtonsStackView.heightAnchor.constraint(equalToConstant: 64)
    tabButtonsHeightConstraint.isActive = true

    self.tabViewController = AnimatedTabViewController()
    view.addSubview(tabViewController.view)

    tabViewController.view.padding(.bottom, .horizontal)
      .spacing(.top(1), to: tabButtonsStackView)

    tabViewController.tabView.padding(.all)
    tabViewController.tabView.wantsLayer = true

    layoutTabScrollView = SidebarLayoutPane(player: player)
    videoTabScrollView = SidebarVideoPane(player: player)
    audioTabScrollView = SidebarAudioPane(player: player)

    // set up the tab buttons

    self.tabButtonsSegmentControl = NSSegmentedControl()
    tabButtonsSegmentControl.segmentCount = 4

    for config in tabConfig {
      tabButtonsSegmentControl.setImage(config.1, forSegment: config.2)
      tabButtonsSegmentControl.setTag(config.2, forSegment: config.2)
    }
    tabButtonsSegmentControl.target = self
    tabButtonsSegmentControl.action = #selector(tabBtnSegmentControlAction(_:))

    self.closeSidebarBtn = NSButton(
      image: .sf("sidebar.squares.leading")!,
      target: self, action: #selector(dismissSidebar)
    )
    closeSidebarBtn.widthAnchor.constraint(equalTo: closeSidebarBtn.heightAnchor).isActive = true
    closeSidebarBtnSizeConstraint = closeSidebarBtn.widthAnchor.constraint(equalToConstant: 28)
    closeSidebarBtnSizeConstraint.isActive = true
    if #available(macOS 26.0, *) {
      if #available(macOS 27.0, *) {
        closeSidebarBtn.bezelStyle = .glass
        closeSidebarBtn.borderShape = .circle
      } else {
        closeSidebarBtn.bezelStyle = .circular
      }
    } else {
      closeSidebarBtn.bezelStyle = .circular
    }

    func makeTabButton(_ title: String, image: NSImage?, tag: Int) -> NSButton {
      let item = TabButton(title: title,
                           target: self, action: #selector(tabBtnAction))
      item.bezelStyle = .smallSquare
      item.isBordered = false
      if let image {
        image.size = .init(width: 26, height: 18)
        item.image = image
        item.imageScaling = .scaleProportionallyUpOrDown
        item.imagePosition = .imageAbove
      }
      item.font = .systemFont(ofSize: 11, weight: .regular)
      item.tag = tag
      return item
    }

    self.dismissBtn = NSButton(
      image: .sf("chevron.forward")!,
      target: self, action: #selector(dismissSidebar(_:))
    )
    self.layoutTabBtn = makeTabButton("Layout", image: .sf("paintpalette.fill"), tag: 0)
    self.videoTabBtn = makeTabButton("Video", image: .tabVideo, tag: 1)
    self.audioTabBtn = makeTabButton("Audio", image: .tabAudio, tag: 2)
    self.subTabBtn = makeTabButton("Subtitles", image: .tabSub, tag: 3)

    prefObserver.addAll(.compactUI, .sidebarSettingsDisplayAtLeading, runNow: true) {
      [unowned self] key in
      let compactUI = Preference.bool(for: .compactUI)
      let isLeading = Preference.bool(for: .sidebarSettingsDisplayAtLeading)

      let height: CGFloat = (compactUI && !isLeading) ? 48 : 52
      tabButtonsHeightConstraint.constant = height

      if #available(macOS 26.0, *), !compactUI {
        tabButtonsSegmentControl.controlSize = .extraLarge
      } else {
        tabButtonsSegmentControl.controlSize = .large
      }

      closeSidebarBtnSizeConstraint.constant =  compactUI ? 28 : 36

      if key == .sidebarSettingsDisplayAtLeading {
        updateTabButtons()
        updateTabActiveStatus()
      }
    }

    // add pages

    func createViewController(_ view: NSView) -> NSViewController {
      let vc = NSViewController()
      vc.view = view
      return vc
    }

    let tabScrollViews = [layoutTabScrollView, videoTabScrollView, audioTabScrollView, subtitlesTabScrollView]

    for view in tabScrollViews {
      view?.horizontalScroll = self.switchTabByScroll(_:)
      let viewItem = NSTabViewItem(viewController: createViewController(view!))
      tabViewController.addTabViewItem(viewItem)
    }
    tabViewController.selectedTabViewItemIndex = TabViewType.video.buttonTag

    withAllTableViews { (view, _) in
      view.delegate = self
      view.dataSource = self
      view.superview?.superview?.layer?.cornerRadius = 4
    }

    // Color Wells
    if #available(macOS 13.0, *) {
      subTextColorWell = NSColorWell(style: .minimal)
      subTextBgColorWell = NSColorWell(style: .minimal)
      subTextBorderColorWell = NSColorWell(style: .minimal)
    } else {
      subTextColorWell = RoundedColorWell()
      subTextBgColorWell = RoundedColorWell()
      subTextBorderColorWell = RoundedColorWell()
    }
    [(subTextColorWellContainer, subTextColorWell),
     (subTextBgColorWellContainer, subTextBgColorWell),
     (subTextBorderColorWellContainer, subTextBorderColorWell)].forEach { (view, well) in
      well.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(well)
      Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": well])
    }
    
    // Wire color wells to IBAction handlers
    subTextColorWell.target = self
    subTextColorWell.action = #selector(subTextColorAction(_:))

    subTextBgColorWell.target = self
    subTextBgColorWell.action = #selector(subTextBgColorAction(_:))

    subTextBorderColorWell.target = self
    subTextBorderColorWell.action = #selector(subTextBorderColorAction(_:))
    
    
    if #available(macOS 26, *) {
      subtitleSwitch.controlSize = .small
      secondarySubtitleSwitch.controlSize = .small

      speedSlider.neutralValue = 8
      (audioEQSliders + videoEQSliders + [audioDelaySlider, subDelaySlider, subScaleSlider]).forEach {
        $0.neutralValue = 0
      }

      subPosSlider.tintProminence = .none
    }

    // colors
    withAllTableViews { tableView, _ in tableView.backgroundColor = NSColor.sidebarTableBackground }

    if pendingSwitchRequest == nil {
      updateTabActiveStatus()
    } else {
      switchToTab(pendingSwitchRequest!)
      pendingSwitchRequest = nil
    }

    speedResetBtn.toolTip = NSLocalizedString("quicksetting.reset_speed", comment: "Reset speed to 1x")

    subLoadSegmentedControl.image(forSegment: 1)?.isTemplate = true
    switchHorizontalLine.wantsLayer = true
    switchHorizontalLine.layer?.opacity = 0.5
    switchHorizontalLine2.wantsLayer = true
    switchHorizontalLine2.layer?.opacity = 0.5

    // Localize decimal format of numbers
    speedSlider0_25xLabel.stringValue = "\(0.25.groupedStringUpTo6Decimals)x"
    speedSlider1xLabel.stringValue = "1x"
    speedSlider4xLabel.stringValue = "4x"
    speedSlider16xLabel.stringValue = "16x"

  }

  @objc func dismissSidebar(_ sender: AnyObject) {
    mainWindow.sidebars.hide(.settings)
  }

  private func updateTabButtons() {
    tabButtonsStackView.arrangedSubviews.forEach {
      tabButtonsStackView.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    if Preference.bool(for: .sidebarSettingsDisplayAtLeading) {
      closeSidebarBtn.image = .sf("sidebar.squares.leading")
      tabButtonsLeadingConstraint.constant = 96
      tabButtonsTrailingConstraint.constant = 10
      tabButtonsStackView.distribution = .equalSpacing
      tabButtonsStackView.addArrangedSubview(tabButtonsSegmentControl)
      tabButtonsStackView.addArrangedSubview(closeSidebarBtn)
    } else {
      closeSidebarBtn.image = .sf("sidebar.squares.trailing")
      tabButtonsLeadingConstraint.constant = 10
      tabButtonsTrailingConstraint.constant = 10
      tabButtonsStackView.distribution = .equalSpacing
      tabButtonsStackView.addArrangedSubview(closeSidebarBtn)
      tabButtonsStackView.addArrangedSubview(tabButtonsSegmentControl)
    }
  }

  private func redraw(indicator: NSTextField, constraint: NSLayoutConstraint, slider: NSSlider, value: String) {
    indicator.stringValue = value
    let offset: CGFloat = 6
    let sliderInnerWidth = slider.frame.width - offset * 2
    constraint.constant = offset + sliderInnerWidth * CGFloat((slider.doubleValue - slider.minValue) / (slider.maxValue - slider.minValue))
    view.layout()
  }

  // MARK: - Validate UI

  /** Do synchronization*/
  override func viewDidAppear() {
    // image sub
    super.viewDidAppear()
    updateControlsState()
  }

  private func updateControlsState() {
//    updateAudioTabControl()
    updateSubTabControl()
    updateAudioEqState()
  }

  private func updateAudioTabControl() {
    guard player.info.state.active else { return }
    let audioDelay = player.mpv.getDouble(MPVOption.Audio.audioDelay)
    audioDelaySlider.doubleValue = audioDelay
    customAudioDelayTextField.doubleValue = audioDelay
    redraw(indicator: audioDelaySliderIndicator, constraint: audioDelaySliderConstraint, slider: audioDelaySlider, value: "\(customAudioDelayTextField.stringValue)s")
  }

  private func updateSubTabControl() {
    guard player.info.state.active else { return }
    hideSwitch.state = player.info.isSubVisible ? .on : .off
    secHideSwitch.state = player.info.isSecondSubVisible ? .on : .off

    if let currSub = player.info.currentTrack(.sub) {
      let enableTextSettings = !(currSub.isAssSub || currSub.isImageSub)
      [subTextColorWell, subTextSizePopUp, subTextBgColorWell, subTextBorderColorWell, subTextBorderWidthPopUp, subTextFontBtn].forEach { $0.isEnabled = enableTextSettings }
    }

    let isPrimary = (subSegmentedControl.selectedSegment == 0)
    let delayOption = isPrimary ? MPVOption.Subtitles.subDelay : MPVOption.Subtitles.secondarySubDelay
    let subDelay = player.mpv.getDouble(delayOption)
    subDelaySlider.doubleValue = subDelay
    customSubDelayTextField.doubleValue = subDelay
    redraw(indicator: subDelaySliderIndicator, constraint: subDelaySliderConstraint, slider: subDelaySlider, value: "\(customSubDelayTextField.stringValue)s")

    let posOption = isPrimary ? MPVOption.Subtitles.subPos : MPVOption.Subtitles.secondarySubPos
    let currSubPos = player.mpv.getInt(posOption)
    subPosSlider.intValue = Int32(currSubPos)

    let currSubScale = player.mpv.getDouble(MPVOption.Subtitles.subScale).clamped(to: 0.1...10)
    let displaySubScale = Utility.toDisplaySubScale(fromRealSubScale: currSubScale)
    subScaleSlider.doubleValue = displaySubScale + (displaySubScale > 0 ? -1 : 1)

    let fontSize = player.mpv.getInt(MPVOption.Subtitles.subFontSize)
    subTextSizePopUp.selectItem(withTitle: fontSize.description)

    let borderWidth = player.mpv.getDouble(MPVOption.Subtitles.subBorderSize)
    subTextBorderWidthPopUp.selectItem(at: -1)
    subTextBorderWidthPopUp.itemArray.forEach { item in
      if borderWidth == Double(item.title) {
        subTextBorderWidthPopUp.select(item)
      }
    }
  }

  private func updateAudioEqState() {
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

  private func switchToTab(_ tab: TabViewType) {
    guard isViewLoaded else { return }
    currentTab = tab
    tabViewController.selectedTabViewItemIndex = tab.buttonTag
    updateTabActiveStatus()
    reload()
  }

  private func updateTabActiveStatus() {
    let currentTag = currentTab.buttonTag
    [layoutTabBtn, videoTabBtn, audioTabBtn, subTabBtn].forEach { btn in
      let isActive = currentTag == btn!.tag
      btn!.state = isActive ? .on : .off
    }

    let isLeading = Preference.bool(for: .sidebarSettingsDisplayAtLeading)
    for config in tabConfig {
      // don't show label if isLeading
      let isSelected = config.2 == currentTag && !isLeading
      tabButtonsSegmentControl.setLabel(isSelected ? config.0 : "", forSegment: config.2)
    }
    tabButtonsSegmentControl.selectedSegment = currentTag
  }

  func reload() {
    guard isViewLoaded else { return }
    switch currentTab {
    case .layout:
      return
    case .audio:
      break
//      audioTableView.reloadData()
//      updateAudioTabControl()
//      updateAudioEqState()
    case .video:
      videoTableView.reloadData()
    case .sub:
      subTableView.reloadData()
      secSubTableView.reloadData()
      updateSubTabControl()
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

  func switchTabByScroll(_ isForward: Bool) {
    if isForward {
      if currentTab.buttonTag < TabViewType.sub.buttonTag {
        switchToTab(.init(buttonTag: currentTab.buttonTag + 1))
      }
    } else {
      if currentTab.buttonTag > TabViewType.layout.buttonTag {
        switchToTab(.init(buttonTag: currentTab.buttonTag - 1))
      }
    }
  }

  // MARK: - NSTableView delegate

  func numberOfRows(in tableView: NSTableView) -> Int {
    if tableView == videoTableView {
      return player.info.videoTracks.count + 1
    } else if tableView == audioTableView {
      return player.info.audioTracks.count + 1
    } else if tableView == subTableView || tableView == secSubTableView {
      return player.info.$subTracks.withLock { $0.count + 1 }
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
      track = row == 0 ? nil : player.info.videoTracks[at: row-1]
      activeId = player.info.vid!
    } else if tableView == audioTableView {
      track = row == 0 ? nil : player.info.audioTracks[at: row-1]
      activeId = player.info.aid!
    } else if tableView == subTableView {
      track = row == 0 ? nil : player.info.subTracks[at: row-1]
      activeId = player.info.sid!
    } else if tableView == secSubTableView {
      track = row == 0 ? nil : player.info.subTracks[at: row-1]
      activeId = player.info.secondSid!
    } else {
      return nil
    }
    // return track data
    if columnName == .isChosen {
      let isChosen = track == nil ? (activeId == 0) : (track!.id == activeId)
      return isChosen ? Constants.String.dot : ""
    } else if columnName == .trackName {
      return track?.infoString ?? Constants.String.trackNone
    } else if columnName == .trackId {
      return track?.idString
    }
    return nil
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    withAllTableViews { (view, type) in
      if view.numberOfSelectedRows > 0 {
        // note that track ids start from 1
        let subId = view.selectedRow > 0 ? player.info.trackList(type)[view.selectedRow-1].id : 0
        self.player.setTrack(subId, forType: type)
        view.deselectAll(self)
      }
    }
    // Revalidate layout and controls
    updateControlsState()
  }

  private func withAllTableViews(_ block: (NSTableView, MPVTrack.TrackType) -> Void) {
    block(audioTableView, .audio)
    block(subTableView, .sub)
    block(secSubTableView, .secondSub)
  }

  // MARK: - Actions

  // MARK: Tab buttons

  @objc private func tabBtnAction(_ sender: NSButton) {
    switchToTab(.init(buttonTag: sender.tag))
  }

  @objc private func tabBtnSegmentControlAction(_ sender: NSSegmentedControl) {
    switchToTab(.init(buttonTag: sender.selectedTag()))
  }

  // MARK: Video tab

  @IBAction func aspectChangedAction(_ sender: NSSegmentedControl) {
    let aspect = AppData.aspectsInPanel[sender.selectedSegment]
    player.setVideoAspect(aspect)
    player.sendOSD(.aspect(aspect))
  }

  @IBAction func cropChangedAction(_ sender: NSSegmentedControl) {
    if sender.selectedSegment == sender.segmentCount - 1 {
      // User clicked on "Custom...": show custom crop UI
      mainWindow.sidebars.hideAllSideBars {
        self.mainWindow.enterInteractiveMode(.crop, selectWholeVideoByDefault: true)
      }
    } else {
      let cropStr = AppData.cropsInPanel[sender.selectedSegment]
      player.setCrop(fromString: cropStr)
      player.sendOSD(.crop(cropStr))
    }
  }

  @IBAction func rotationChangedAction(_ sender: NSSegmentedControl) {
    let value = AppData.rotations[sender.selectedSegment]
    player.setVideoRotate(value)
    player.sendOSD(.rotate(value))
  }

  @IBAction func customAspectEditFinishedAction(_ sender: AnyObject?) {
    let value = customAspectTextField.stringValue
    if value != "" {
      aspectSegment.setSelected(false, forSegment: aspectSegment.selectedSegment)
      player.setVideoAspect(value)
      player.sendOSD(.aspect(value))
    }
  }

  @IBAction func hardwareDecodingAction(_ sender: NSSwitch) {
    player.toggleHardwareDecoding(sender.state == .on)
  }
  
  @IBAction func deinterlaceAction(_ sender: NSSwitch) {
    player.toggleDeinterlace(sender.state == .on)
  }
  
  @IBAction func hdrAction(_ sender: NSSwitch) {
    self.player.info.hdrEnabled = sender.state == .on
    self.player.refreshEdrMode()
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
    player.setVideoEqualizer(forOption: type, value: Int(sender.intValue))
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
    player.setVideoEqualizer(forOption: type, value: 0)
    slider?.intValue = 0
  }

  // MARK: Audio tab

  @IBAction func loadExternalAudioAction(_ sender: NSButton) {
    let currentDir = player.info.currentURL?.deletingLastPathComponent()
    Utility.quickOpenPanel(
      title: "Load external audio file",
      chooseDir: false,
      dir: currentDir,
      sheetWindow: player.currentWindow,
      allowedFileTypes: Utility.playableFileExt
    ) { url in
      self.player.loadExternalAudioFile(url)
      self.audioTableView.reloadData()
    }
  }

  @IBAction func audioDelayChangedAction(_ sender: NSSlider) {
    let eventType = NSApp.currentEvent!.type
    let sliderValue: Double
    switch eventType {
    case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
      // When dragging slider with the mouse, snap to the nearest 50ms (1/20 sec)
      // Although it is possible to show tick marks at every step of 0.05 in the slider, it is visually unpleasant.
      // So we draw less tick marks, and keep "Only stop on tick marks" disabled, and add our own logic to stop on
      // "virtual tick marks" for these values.
      sliderValue = (sender.doubleValue * 20.0).rounded() / 20.0
      sender.doubleValue = sliderValue
    default:
      sliderValue = sender.doubleValue
    }
    customAudioDelayTextField.doubleValue = sliderValue
    redraw(indicator: audioDelaySliderIndicator, constraint: audioDelaySliderConstraint, slider: audioDelaySlider, value: "\(sliderValue)s")
    if let event = NSApp.currentEvent {
      if event.type == .leftMouseUp {
        player.setAudioDelay(sliderValue)
      }
    }
  }

  @IBAction func customAudioDelayEditFinishedAction(_ sender: NSTextField) {
    if sender.stringValue.isEmpty {
      sender.stringValue = "0"
    }
    let value = sender.doubleValue
    player.setAudioDelay(value)
    audioDelaySlider.doubleValue = value
    redraw(indicator: audioDelaySliderIndicator, constraint: audioDelaySliderConstraint, slider: audioDelaySlider, value: "\(sender.stringValue)s")
  }


  // MARK: Sub tab

  @IBAction func hideSubAction(_ sender: NSSwitch) {
    player.toggleSubVisibility()
  }

  @IBAction func hideSecSubAction(_ sender: NSSwitch) {
    player.toggleSecondSubVisibility()
  }

  @IBAction func loadExternalSubAction(_ sender: NSSegmentedControl) {
    if sender.selectedSegment == 0 {
      let currentDir = player.info.currentURL?.deletingLastPathComponent()
      // In addition to subtitle files allow the user to choose video files as mpv will look for
      // and load embedded subtitle streams in the video file.
      Utility.quickOpenPanel(title: "Load external subtitle", chooseDir: false, dir: currentDir,
                             sheetWindow: player.currentWindow,
                             allowedFileTypes: Utility.containsSubExt) { url in
        // set a delay
        self.player.loadExternalSubFile(url, delay: true)
        self.subTableView.reloadData()
        self.secSubTableView.reloadData()
      }
    } else if sender.selectedSegment == 1 {
      showSubChooseMenu(forView: sender)
    }
  }

  func showSubChooseMenu(forView view: NSView, showLoadedSubs: Bool = false) {
    let activeSubs = player.info.trackList(.sub) + player.info.trackList(.secondSub)
    let menu = NSMenu()
    menu.autoenablesItems = false
    // loaded subtitles
    if showLoadedSubs {
      if player.info.subTracks.isEmpty {
        menu.addItem(withTitle: NSLocalizedString("subtrack.no_loaded", comment: "No subtitles loaded"), enabled: false)
      } else {
        menu.addItem(withTitle: NSLocalizedString("track.none", comment: "<None>"),
                     action: #selector(self.chosenSubFromMenu(_:)), target: self,
                     stateOn: player.info.sid == 0 ? true : false)

        for sub in player.info.subTracks {
          menu.addItem(withTitle: sub.readableTitle,
                       action: #selector(self.chosenSubFromMenu(_:)),
                       target: self,
                       obj: sub,
                       stateOn: sub.id == player.info.sid ? true : false)
        }
      }
      menu.addItem(NSMenuItem.separator())
    }
    // external subtitles
    let addMenuItem = { (sub: FileInfo) -> Void in
      let isActive = !showLoadedSubs && activeSubs.contains { $0.externalFilename == sub.path }
      menu.addItem(withTitle: "\(sub.filename).\(sub.ext)",
                   action: #selector(self.chosenSubFromMenu(_:)),
                   target: self,
                   obj: sub,
                   stateOn: isActive ? true : false)

    }
    if player.info.currentSubsInfo.isEmpty {
      menu.addItem(withTitle: NSLocalizedString("subtrack.no_external", comment: "No external subtitles found"),
                   enabled: false)
    } else {
      if let videoInfo = player.info.currentVideosInfo.first(where: { $0.url == player.info.currentURL }),
        !videoInfo.relatedSubs.isEmpty {
        videoInfo.relatedSubs.forEach(addMenuItem)
        menu.addItem(NSMenuItem.separator())
      }
      player.info.currentSubsInfo.sorted { (f1, f2) in
        return f1.filename.localizedStandardCompare(f2.filename) == .orderedAscending
      }.forEach(addMenuItem)
    }
    NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent!, for: view)
  }

  @objc func chosenSubFromMenu(_ sender: NSMenuItem) {
    if let fileInfo = sender.representedObject as? FileInfo {
      player.loadExternalSubFile(fileInfo.url)
    } else if let sub = sender.representedObject as? MPVTrack {
      player.setTrack(sub.id, forType: .sub)
    } else {
      player.setTrack(0, forType: .sub)
    }
  }

  @IBAction func searchOnlineAction(_ sender: AnyObject) {
    mainWindow.menuActionHandler.menuFindOnlineSub(.dummy)
  }

  @IBAction func subSegmentedControlAction(_ sender: NSSegmentedControl) {
    updateSubTabControl()
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
        player.setSubDelay(sliderValue, forPrimary: subSegmentedControl.selectedSegment == 0)
      }
    }
  }

  @IBAction func customSubDelayEditFinishedAction(_ sender: NSTextField) {
    if sender.stringValue.isEmpty {
      sender.stringValue = "0"
    }
    let value = sender.doubleValue
    player.setSubDelay(value, forPrimary: subSegmentedControl.selectedSegment == 0)
    subDelaySlider.doubleValue = value
    redraw(indicator: subDelaySliderIndicator, constraint: subDelaySliderConstraint, slider: subDelaySlider, value: "\(sender.stringValue)s")
  }

  @IBAction func subScaleReset(_ sender: AnyObject) {
    player.setSubScale(1)
    subScaleSlider.doubleValue = 0
  }

  @IBAction func subPosSliderAction(_ sender: NSSlider) {
    player.setSubPos(Int(sender.intValue), forPrimary: subSegmentedControl.selectedSegment == 0)
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
    player.setSubScale(realValue)
  }

  @IBAction func subTextColorAction(_ sender: AnyObject) {
    player.setSubTextColor(subTextColorWell.color.mpvColorString)
  }

  @IBAction func subTextSizeAction(_ sender: AnyObject) {
    if let selectedItem = subTextSizePopUp.selectedItem, let value = Double(selectedItem.title) {
      player.setSubTextSize(value)
    }
  }

  @IBAction func subTextBorderColorAction(_ sender: AnyObject) {
    player.setSubTextBorderColor(subTextBorderColorWell.color.mpvColorString)
  }

  @IBAction func subTextBorderWidthAction(_ sender: AnyObject) {
    if let selectedItem = subTextBorderWidthPopUp.selectedItem, let value = Double(selectedItem.title) {
      player.setSubTextBorderSize(value)
    }
  }

  @IBAction func subTextBgColorAction(_ sender: AnyObject) {
    player.setSubTextBgColor(subTextBgColorWell.color.mpvColorString)
  }

  @IBAction func subFontAction(_ sender: AnyObject) {
    player.chooseSubFont()
  }

}

class QuickSettingView: NSView {
  override func mouseDown(with event: NSEvent) {}
  override func mouseUp(with event: NSEvent) {}
}


fileprivate class TabButton: NSButton {
  class Cell: NSButtonCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
      if state == .on {
        let frame = NSInsetRect(cellFrame, 0, -4)
        let rect = NSBezierPath(roundedRect: frame, xRadius: 16, yRadius: 16)

        if let gradient = NSGradient(starting: .gray.withAlphaComponent(0.1), ending: .gray.withAlphaComponent(0.2)) {
          gradient.draw(in: rect, angle: 90)
        }

        NSColor.sidebarTabBtnBorder.setStroke()
        rect.lineWidth = 1
        rect.stroke()
      }

      super.draw(withFrame: cellFrame, in: controlView)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
      (controlView as? NSButton)?.contentTintColor = state == .on ?
        .sidebarTabTintActive : .sidebarTabTint
      super.drawInterior(withFrame: cellFrame, in: controlView)
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    self.cell = Cell()
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
