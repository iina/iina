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
  private var subtitlesTabScrollView: SidebarScrollView!

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
    subtitlesTabScrollView = SidebarSubtitlesPane(player: player)

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
    self.layoutTabBtn = makeTabButton("Layout", image: .sf("paintbrush.fill"), tag: 0)
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

  // MARK: - Switch tab

  private func switchToTab(_ tab: TabViewType) {
    guard isViewLoaded else { return }
    currentTab = tab
    tabViewController.selectedTabViewItemIndex = tab.buttonTag
    updateTabActiveStatus()
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

  // MARK: - Actions

  // MARK: Tab buttons

  @objc private func tabBtnAction(_ sender: NSButton) {
    switchToTab(.init(buttonTag: sender.tag))
  }

  @objc private func tabBtnSegmentControlAction(_ sender: NSSegmentedControl) {
    switchToTab(.init(buttonTag: sender.selectedTag()))
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
