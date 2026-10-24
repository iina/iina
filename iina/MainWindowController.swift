//
//  MainWindowController.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import Mustache
import WebKit

fileprivate let isMacOS11: Bool = {
  if #unavailable(macOS 12.0) {
      return true
  }
  return false
}()

fileprivate let UIAnimationDuration = 0.25
fileprivate let OSDAnimationDuration = 0.5

fileprivate extension NSStackView.VisibilityPriority {
  static let detachEarly = NSStackView.VisibilityPriority(rawValue: 850)
  static let detachEarlier = NSStackView.VisibilityPriority(rawValue: 800)
  static let detachEarliest = NSStackView.VisibilityPriority(rawValue: 750)
}

// The minimum distance that the user must drag before their click or tap gesture is interpreted as a drag gesture:
fileprivate let minimumInitialDragDistance: CGFloat = 3.0

fileprivate let layoutSides: [NSLayoutConstraint.Attribute] = [.top, .bottom, .leading, .trailing]

class MainWindowController: PlayerWindowController {

  override var windowNibName: NSNib.Name {
    return NSNib.Name("MainWindowController")
  }

  /** For Force Touch. */
  let minimumPressDuration: TimeInterval = 0.5

  // MARK: - Objects, Views

  override var videoView: VideoView {
    return _videoView
  }

  lazy private var _videoView: VideoView = VideoView(frame: window!.contentView!.bounds, player: player)

  /// Owns the sidebar panels, view controllers, and show/hide/resize logic.
  lazy var sidebars = SidebarController(mainWindow: self)

  private lazy var magnificationGestureRecognizer: NSMagnificationGestureRecognizer = {
    return NSMagnificationGestureRecognizer(target: self, action: #selector(MainWindowController.handleMagnifyGesture(recognizer:)))
  }()

  /// For auto hiding UI after a timeout.
  var hideControlTimer: Timer?
  var hideOSDTimer: Timer?
  private var seekPreviewHover: SeekPreviewHoverController?
  var isSeekingWithSlider = false

  /// For blacking out other screens.
  var screens: [NSScreen] = []
  var blackWindows: [NSWindow] = []
  var cachedScreens: [NSScreen] = []

  /// For hiding camera housing only in legacy full screen.
  var cameraHousingWindow: NSWindow?

  lazy var rotation: Int = {
    return player.mpv.getInt(MPVProperty.videoParamsRotate)
  }()


  var videoViewContainer: NSView!
  var titleBarView: Titlebar!
  var titleBarHeightConstraint: NSLayoutConstraint!
  var oscBottomView: OSCBottomView!
  var oscFloatingView: OSCFloatingView!

  var currentControlBar: NSView?

  var oscPlayControlView: NSStackView!
  var oscPlayControlMiddleView: NSStackView!
  var leftArrowButton: NSButton!
  var rightArrowButton: NSButton!
  var oscSpeedLabelLeftContainer: NSView!
  var oscSpeedLabelRightContainer: NSView!
  var oscSpeedLabelLeft: NSTextField!
  var oscSpeedLabelRight: NSTextField!

  var oscVolumeView: NSView!
  var oscToolbarView: NSStackView!
  var oscSliderView: NSView!

  private(set) var floatingOSCScale: CGFloat = 1
  private var floatingOSCControlConstraints: [(constraint: NSLayoutConstraint, original: CGFloat)] = []
  private var floatingOSCToolbarConstraints: [(constraint: NSLayoutConstraint, original: CGFloat)] = []
  private var floatingOSCOriginalImageScaling: [NSButton: NSImageScaling] = [:]
  private var floatingOSCControlsView: FloatingOSCControlsView?
  private var floatingOSCOriginalDistributions: [NSStackView: NSStackView.Distribution] = [:]

  var osdView: OSDView!
  var additionalInfoView: AdditionalInfoView!
  var bufferIndicatorView: BufferIndicatorView!
  var timePreviewView: TimePreviewView!
  var chapterPreviewView: TimePreviewView!
  var titlebarOnTopButton: NSButton!
  var thumbnailPeekView: ThumbnailPeekView!
  // Output clamps must not replace the reference; manual resizing scales it with the visible window.
  private var isApplyingVideoTransformWindowFrame = false
  private var videoTransformWindowReferenceSize: NSSize?
  private var videoTransformWindowSize: NSSize?
  private var videoTransformWindowDisplaySize: NSSize?
  private var videoTransformWindowGeneration: Int?
  private var windowSizingFileGeneration: Int?
  private var videoAspectTransition: (panscan: Double, mediaGeneration: Int)?
  enum VideoGeometryChange: Hashable { case aspect, rotation }
  private final class GeometryMotion {
    let generation: Int
    let osdToken: UUID
    let oldVisibleRect: NSRect
    let oldRotation: Int
    let overlay: CropTransitionOverlay?
    let wasAnimating: Bool
    var expectedRotation = 0
    var expectedPAR = 1.0
    var targetDisplaySize: NSSize?
    var targetWindowFrame: NSRect?
    var waitingForFrame = false
    var animating = false
    var outputIsReady = false
    var pendingFrame: ((Bool) -> Void)?
    init(generation: Int, osdToken: UUID, oldVisibleRect: NSRect, oldRotation: Int,
         overlay: CropTransitionOverlay?, wasAnimating: Bool) {
      self.generation = generation; self.osdToken = osdToken
      self.oldVisibleRect = oldVisibleRect; self.oldRotation = oldRotation
      self.overlay = overlay; self.wasAnimating = wasAnimating
    }
  }
  private var geometryMotion: GeometryMotion?
  private var pendingGeometryChanges: [VideoGeometryChange: () -> Void] = [:]
  private var cropExitOverlay: CropTransitionOverlay?
  private var pendingPlayerCropChange: (() -> Void)?
  private var fullscreenVideoConstraints: [NSLayoutConstraint] = []
  var isCropTransitionInProgress: Bool { cropExitOverlay != nil || interactiveMode.isEntering || geometryMotion != nil }
  var isPlayerCropTransitionInProgress: Bool { cropExitOverlay?.isPlayerTransition == true }

  var isFullscreenTransitionInProgress: Bool {
    if case .animating = fsState { return true }
    return false
  }

  var videoAspectTransitionOriginalPanscan: Double? {
    guard let transition = videoAspectTransition,
          transition.mediaGeneration == player.info.trackSelectionGeneration,
          player.mpv.getDouble(MPVOption.Video.panscan) == 1 else { return nil }
    return transition.panscan
  }

  // MARK: - Status

  override var isOntop: Bool {
    didSet {
      titleBarView.updateOnTopIcon()
    }
  }

  /** For mpv's `geometry` option. We cache the parsed structure
   so never need to parse it every time. */
  var cachedGeometry: GeometryDef?

  private var windowDragMouseDownEvent: NSEvent?
  private var didDragWindow = false

  lazy var liveText = LiveTextController(mainWindow: self)
  lazy var interactiveMode = InteractiveModeController(mainWindow: self)
  var pipStatus = PIPStatus.notInPIP
  private var pipReturnWindowAlpha: CGFloat?
  private var pipPreparationFeedback: UUID?
  private var operationFeedbackRequests = Set<UUID>()
  private var operationFeedbackView: PreparationFeedbackView?
  private var operationFeedbackToken: DelayedPreparationFeedback.Token?
  var isVideoLoaded: Bool = false

  var shouldApplyInitialWindowSize = true
  var isWindowHidden: Bool = false
  var isWindowMiniaturizedDueToPip = false

  var isMouseInWindow: Bool = false
  /** flag to ignore abrupt momentum scrolls */
  private var isMomentumScrollingAllowed = false

  var isFastforwarding: Bool = false

  var isPausedDueToInactive: Bool = false
  var isPausedDueToMiniaturization: Bool = false

  var lastMagnification: CGFloat = 0.0
  var frameWhenStartedPinching = NSRect()
  private var windowResizeSession: WindowResizeSession?

  /** Views that will show/hide when cursor moving in/out the window. */
  let fadeableViews = FadeableViewController()

  private var uiAnimationGeneration = 0
  private var isUIHiddenByOSCClick = false
  private var isPluginMenuTracking = false

  // Left and right arrow buttons

  /** The maximum pressure recorded when clicking on the arrow buttons. */
  var maxPressure: Int32 = 0

  /** The value of speedValueIndex before Force Touch. */
  var oldIndex: Int = AppData.availableSpeedValues.count / 2

  /** When the arrow buttons were last clicked. */
  var lastClick = Date()

  /** The index of current speed in speed value array. */
  var speedValueIndex: Int = AppData.availableSpeedValues.count / 2 {
    didSet {
      if speedValueIndex < 0 || speedValueIndex >= AppData.availableSpeedValues.count {
        speedValueIndex = AppData.availableSpeedValues.count / 2
      }
    }
  }

  /** For force touch action */
  var isCurrentPressInSecondStage = false

  /** Whether current osd needs user interaction to be dismissed */
  var isShowingPersistentOSD = false
  var osdContext: Any?

  // MARK: - Enums

  // Window state

  enum FullScreenState: Equatable {
    case windowed
    case animating(toFullscreen: Bool, legacy: Bool, priorWindowedFrame: NSRect)
    case fullscreen(legacy: Bool, priorWindowedFrame: NSRect)

    var isFullscreen: Bool {
      switch self {
      case .fullscreen: return true
      case let .animating(toFullscreen: toFullScreen, legacy: _, priorWindowedFrame: _): return toFullScreen
      default: return false
      }
    }

    var priorWindowedFrame: NSRect? {
      get {
        switch self {
        case .windowed: return nil
        case .animating(_, _, let p): return p
        case .fullscreen(_, let p): return p
        }
      }
      set {
        guard let newRect = newValue else { return }
        switch self {
        case .windowed: return
        case let .animating(toFullscreen, legacy, _):
          self = .animating(toFullscreen: toFullscreen, legacy: legacy, priorWindowedFrame: newRect)
        case let .fullscreen(legacy, _):
          self = .fullscreen(legacy: legacy, priorWindowedFrame: newRect)
        }
      }
    }

    mutating func startAnimatingToFullScreen(legacy: Bool, priorWindowedFrame: NSRect) {
      self = .animating(toFullscreen: true, legacy: legacy, priorWindowedFrame: priorWindowedFrame)
    }

    mutating func startAnimatingToWindow() {
      guard case .fullscreen(let legacy, let priorWindowedFrame) = self else { return }
      self = .animating(toFullscreen: false, legacy: legacy, priorWindowedFrame: priorWindowedFrame)
    }

    mutating func finishAnimating() {
      switch self {
      case .windowed, .fullscreen: assertionFailure("something went wrong with the state of the world. One must be .animating to finishAnimating. Not \(self)")
      case .animating(let toFullScreen, let legacy, let frame):
        if toFullScreen {
          self = .fullscreen(legacy: legacy, priorWindowedFrame: frame)
        } else {
          self = .windowed
        }
      }
    }
  }

  var fsState: FullScreenState = .windowed {
    didSet {
      // Must not access mpv while it is asynchronously processing stop and quit commands.
      guard player.info.state.active else { return }
      switch fsState {
      case .fullscreen: player.mpv.setFlag(MPVOption.Window.fullscreen, true)
      case .animating:  break
      case .windowed:   player.mpv.setFlag(MPVOption.Window.fullscreen, false)
      }
    }
  }

  // Animation state

  /// Animation state of he hide/show part
  enum UIAnimationState {
    case shown, hidden, willShow, willHide
  }

  var animationState: UIAnimationState = .shown
  var osdAnimationState: UIAnimationState = .hidden

  private var osdLastMessage: OSDMessage? = nil

  enum PIPStatus {
    case notInPIP
    case inPIP
    case intermediate
  }

  // MARK: - Observed user defaults

  // Cached user default values
  private(set) lazy var oscPosition: Preference.OSCPosition = Preference.enum(for: .oscPosition)
  private lazy var arrowBtnFunction: Preference.ArrowButtonAction = Preference.enum(for: .arrowButtonAction)
  private lazy var pinchAction: Preference.PinchAction = Preference.enum(for: .pinchAction)
  lazy var displayTimeAndBatteryInFullScreen: Bool = Preference.bool(for: .displayTimeAndBatteryInFullScreen)

  private let localObservedPrefKeys: [Preference.Key] = [
    .oscPosition,
    .showChapterPos,
    .arrowButtonAction,
    .pinchAction,
    .blackOutMonitor,
    .useLegacyFullScreen,
    .displayTimeAndBatteryInFullScreen,
    .controlBarToolbarButtons,
    .alwaysShowOnTopIcon,
    .unlockWindowAspectRatio,
    .edgeToEdgeVideo,
    .compactUI,
    .dockedControlBarAndTitlebar,
    .useLiquidGlassOSC,
    .useLiquidGlassOSD,
    .useLiquidGlassSidebar,
    .enableLiveText
  ]

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath, let change else { return }
    super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)

    switch keyPath {
    case PK.oscPosition.rawValue:
      if let newValue = change[.newKey] as? Int {
        setupOnScreenController(withPosition: Preference.OSCPosition(rawValue: newValue) ?? .floating)
        liveText.updateOverlayInsets()
      }
    case PK.showChapterPos.rawValue:
      if let newValue = change[.newKey] as? Bool {
        (playSlider.cell as! PlaySliderCell).drawChapters = newValue
      }
    case PK.verticalScrollAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        verticalScrollAction = Preference.ScrollAction(rawValue: newValue)!
      }
    case PK.horizontalScrollAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        horizontalScrollAction = Preference.ScrollAction(rawValue: newValue)!
      }
    case PK.arrowButtonAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        arrowBtnFunction = Preference.ArrowButtonAction(rawValue: newValue)!
        updateArrowButtons()
      }
    case PK.pinchAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        pinchAction = Preference.PinchAction(rawValue: newValue)!
      }
    case PK.blackOutMonitor.rawValue:
      if let newValue = change[.newKey] as? Bool {
        if fsState.isFullscreen {
          newValue ? blackOutOtherMonitors() : removeBlackWindow()
        }
      }
    case PK.useLegacyFullScreen.rawValue:
      resetCollectionBehavior()
    case PK.displayTimeAndBatteryInFullScreen.rawValue:
      if let newValue = change[.newKey] as? Bool {
        displayTimeAndBatteryInFullScreen = newValue
        if !newValue {
          additionalInfoView.isHidden = true
        }
        fadeableViews.update()
      }
    case PK.controlBarToolbarButtons.rawValue:
      if let newValue = change[.newKey] as? [Int] {
        setupOSCToolbarButtons(newValue.compactMap(Preference.ToolBarButton.init(rawValue:)))
      }
    case PK.alwaysShowOnTopIcon.rawValue:
      titleBarView.updateOnTopIcon()
    case PK.dockedControlBarAndTitlebar.rawValue:
      setupVideoContainerConstraints()
      fadeableViews.update()
    case PK.edgeToEdgeVideo.rawValue:
      setupVideoContainerConstraints()
      fallthrough
    case PK.unlockWindowAspectRatio.rawValue:
      fadeableViews.update()
      titleBarView.updateRemoveBlackBarButton()
      if interactiveMode.isActive, let window {
        setWindowAspectRatio(window.frame.size)
        interactiveMode.resize()
      } else {
        handleVideoSizeChange(keepWindowSize: true)
      }
    case PK.compactUI.rawValue:
      setWindowToolbar()
    case PK.useLiquidGlassOSD.rawValue:
      [timePreviewView, chapterPreviewView, osdView, additionalInfoView, bufferIndicatorView].forEach {
        $0?.setStyle(Preference.liquidGlass(.osd) ? .liquidGlass : .visualEffect)
      }
    case PK.enableLiveText.rawValue:
      if #available(macOS 13, *), let newValue = change[.newKey] as? Bool {
        let buttons = oscToolbarView.subviews as! [NSButton]
        if let btn = buttons.first(where: { $0.tag == Preference.ToolBarButton.liveText.rawValue }) {
          btn.image = newValue ? Preference.ToolBarButton.liveText.alternateImage() : Preference.ToolBarButton.liveText.image()
        }
        if newValue {
          liveText.requestAnalysis()
        } else {
          liveText.clearAnalysis()
        }
      }
    default:
      return
    }
  }

  // MARK: - Outlets

  var standardWindowButtons: [NSButton] {
    get {
      return ([.closeButton, .miniaturizeButton, .zoomButton, .documentIconButton] as [NSWindow.ButtonType]).compactMap {
        window?.standardWindowButton($0)
      }
    }
  }

  private func updateWindowButtonLayout() {
    if fsState == .windowed { titleBarView?.trackWindowButtons() }
    else { titleBarView?.restoreWindowButtons() }
  }

  /** Get the `NSTextField` of widow's title. */
  var titleTextField: NSTextField? {
    get {
      guard titleBarView?.tracksWindowButtons != true else { return nil }
      return window?.standardWindowButton(.closeButton)?.superview?.subviews.compactMap({ $0 as? NSTextField }).first
    }
  }

  @IBOutlet weak var pipOverlayView: NSVisualEffectView!

  lazy var pluginOverlayViewContainer: NSView! = {
    guard let window, let cv = window.contentView else { return nil }
    let view = PluginOverlayViewContainer(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    cv.addSubview(view, positioned: .below, relativeTo: bufferIndicatorView)
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": view])
    return view
  }()

  private var videoViewConstraints: [NSLayoutConstraint.Attribute: NSLayoutConstraint] = [:]
  private var videoContainerConstraints: [NSLayoutConstraint.Attribute: NSLayoutConstraint] = [:]
  private var videoContainerPhysicalConstraints: [NSLayoutConstraint] = []

  override var mouseActionDisabledViews: [NSView?] {
    sidebars.mouseActionDisabledViews + [currentControlBar, titleBarView]
  }

  // MARK: - PIP

  lazy var _pip: PIPViewController = {
    let pip = VideoPIPViewController()
    pip.delegate = self
    return pip
  }()

  var pip: PIPViewController {
    _pip
  }

  var pipVideo: NSViewController!

  // MARK: - Initialization

  override func windowDidLoad() {
    super.windowDidLoad()
    MemoryUsage.shared.logUsage("after window loaded")

    guard let window, let cv = window.contentView else { return }

    window.styleMask.insert(.fullSizeContentView)

    // need to deal with control bar, so we handle it manually
    // w.isMovableByWindowBackground  = true

    // set background color to black
    window.backgroundColor = window.effectiveAppearance.isDark ? .black : .white

    // size
    applyNativeMinimumWindowSize()
    window.aspectRatio = AppData.sizeWhenNoVideo
    setWindowToolbar()
    cv.autoresizesSubviews = false
    cv.addGestureRecognizer(magnificationGestureRecognizer)

    // Work around a bug in macOS Ventura where HDR content becomes dimmed when playing in full
    // screen mode once overlaying views are fully hidden (issue #3844). After applying this
    // workaround another bug in Ventura where an external monitor goes black could not be
    // reproduced (issue #4015). The workaround adds a tiny subview with such a low alpha level it
    // is invisible to the human eye. This workaround may not be effective in all cases.
    if #available(macOS 13, *), Preference.bool(for: .enableHdrWorkaround) {
      let view = NSView(frame: NSRect(origin: .zero, size: NSSize(width: 0.1, height: 0.1)))
      view.wantsLayer = true
      view.layer?.backgroundColor = NSColor.black.cgColor
      view.layer?.opacity = 0.01
      cv.addSubview(view)
    }

    videoViewContainer = NSView()
    videoViewContainer.translatesAutoresizingMaskIntoConstraints = false

    DispatchQueue.main.async { [weak self] in
      if #available(macOS 14, *) {
        self?.sidebars.quickSettingView.loadViewIfNeeded()
        self?.sidebars.playlistView.loadViewIfNeeded()
        self?.sidebars.pluginView.loadViewIfNeeded()
      } else {
        _ = self?.sidebars.quickSettingView.view
        _ = self?.sidebars.playlistView.view
        _ = self?.sidebars.pluginView.view
      }
    }

    // create translucent views
    oscBottomView = OSCBottomView(mainWindow: self)
    cv.addSubview(oscBottomView)
    oscFloatingView = OSCFloatingView(mainWindow: self)
    cv.addSubview(oscFloatingView)
    osdView = OSDView(mainWindow: self)
    cv.addSubview(osdView)
    additionalInfoView = AdditionalInfoView(mainWindow: self)
    cv.addSubview(additionalInfoView)
    bufferIndicatorView = BufferIndicatorView(mainWindow: self)
    cv.addSubview(bufferIndicatorView)
    titleBarView = Titlebar(mainWindow: self)
    cv.addSubview(titleBarView)
    sidebars.installSubviews(in: cv)

    // thumbnail peek view
    thumbnailPeekView = ThumbnailPeekView()
    cv.addSubview(thumbnailPeekView)
    self.timePreviewView = TimePreviewView(mainWindow: self)
    cv.addSubview(timePreviewView)
    chapterPreviewView = TimePreviewView(mainWindow: self)
    chapterPreviewView.textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    cv.addSubview(chapterPreviewView)
    hideSeekPreview()
    timePreviewView.textField.font = .monospacedDigitFont(for: .small)

    // osc

    oscBottomView.padding(.horizontal)

    self.oscVolumeView = NSView()
    oscVolumeView.translatesAutoresizingMaskIntoConstraints = false

    volumeSlider.size(width: 70)

    oscVolumeView.addSubview(muteButton)
    oscVolumeView.addSubview(volumeSlider)
    muteButton.size(width: 24, height: 24)
      .padding(.vertical, .leading(4)).spacing(.trailing(4), to: volumeSlider)
    volumeSlider.size(width: 70).center(.y)
      .padding(.trailing(6))

    self.oscPlayControlView = NSStackView()
    oscPlayControlView.translatesAutoresizingMaskIntoConstraints = false
    oscPlayControlView.orientation = .horizontal
    oscPlayControlView.alignment = .centerY
    oscPlayControlView.spacing = 0

    self.leftArrowButton = NSButton(image: .speedl, target: self, action: #selector(leftButtonAction))
    leftArrowButton.maxAcceleratorLevel = 5

    self.rightArrowButton = NSButton(image: .speed, target: self, action: #selector(rightButtonAction))
    rightArrowButton.maxAcceleratorLevel = 5

    [playButton, leftArrowButton, rightArrowButton].forEach { button in
      button!.translatesAutoresizingMaskIntoConstraints = false
      button!.bezelStyle = .smallSquare
      button!.isBordered = false
      button!.size(width: 24, height: 24)
    }

    self.oscSpeedLabelLeftContainer = NSView()
    self.oscSpeedLabelRightContainer = NSView()
    [oscSpeedLabelLeftContainer, oscSpeedLabelRightContainer].forEach { view in
      view!.translatesAutoresizingMaskIntoConstraints = false
      view!.size(width: 30)  // label: 26 + padding: 8
    }

    self.oscSpeedLabelLeft = NSTextField(labelWithString: "")
    self.oscSpeedLabelRight = NSTextField(labelWithString: "")
    [oscSpeedLabelLeft, oscSpeedLabelRight].forEach { label in
      label!.translatesAutoresizingMaskIntoConstraints = false
      label!.font = .systemFont(ofSize: 10)
      label!.textColor = .secondaryLabelColor
    }
    oscSpeedLabelLeftContainer.addSubview(oscSpeedLabelLeft)
    oscSpeedLabelLeft.padding(.vertical, .trailing(8))
    oscSpeedLabelRightContainer.addSubview(oscSpeedLabelRight)
    oscSpeedLabelRight.padding(.vertical, .leading(8))

    self.oscPlayControlMiddleView = NSStackView(views: [leftArrowButton, playButton, rightArrowButton])
    oscPlayControlMiddleView.translatesAutoresizingMaskIntoConstraints = false
    oscPlayControlMiddleView.orientation = .horizontal
    oscPlayControlMiddleView.alignment = .centerY
    oscPlayControlMiddleView.spacing = 24

    self.oscToolbarView = NSStackView()
    oscToolbarView.translatesAutoresizingMaskIntoConstraints = false
    oscToolbarView.orientation = .horizontal
    oscToolbarView.alignment = .centerY
    oscToolbarView.spacing = 0
    oscToolbarView.size(height: 24)

    self.oscSliderView = TimeLabelOverflowedView()
    [leftLabel, rightLabel].forEach { label in
      label!.textColor = .secondaryLabelColor
      label!.alignment = .center
      label!.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
      label!.widthAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
    }
    oscSliderView.translatesAutoresizingMaskIntoConstraints = false
    oscSliderView.addSubview(leftLabel)
    oscSliderView.addSubview(rightLabel)
    oscSliderView.addSubview(playSlider)
    leftLabel.padding(.leading(2)).spacing(.trailing(2), to: playSlider)
      .center(.y, with: playSlider)
    rightLabel.padding(.trailing(2)).spacing(.leading(2), to: playSlider)
      .center(.y, with: playSlider)
    playSlider.padding(.vertical(6))

    // XIB controls can have duplicate dimension constraints; scale all of them together.
    let sizedViews: [NSView] = [muteButton, volumeSlider, playButton, leftArrowButton,
                              rightArrowButton, oscSpeedLabelLeftContainer,
                              oscSpeedLabelRightContainer, oscToolbarView, leftLabel, rightLabel]
    floatingOSCControlConstraints = sizedViews.flatMap { view in
      view.constraints.filter {
        $0.secondItem == nil && ($0.firstAttribute == .width || $0.firstAttribute == .height)
      }.map { (constraint: $0, original: $0.constant) }
    }
    // Scale container padding; retain the timeline slider's native knob and padding.
    let paddedViews = [oscVolumeView!, oscSpeedLabelLeftContainer!, oscSpeedLabelRightContainer!]
    floatingOSCControlConstraints += paddedViews.flatMap { view in
      view.constraints.filter { $0.secondItem != nil && $0.constant != 0 }
        .map { (constraint: $0, original: $0.constant) }
    }
    [playButton, leftArrowButton, rightArrowButton].forEach { button in
      floatingOSCOriginalImageScaling[button!] = button!.imageScaling
    }

    // osd

    osdView.padding(.trailing(greaterThan: 8), .bottom(greaterThan: 8))
      .spacing(.top(8), to: titleBarView)
    let osdSidebarInset = osdView.leadingAnchor.constraint(equalTo: sidebars.leadingSidebar.view.trailingAnchor, constant: 8)
    osdSidebarInset.priority = .defaultLow
    osdSidebarInset.isActive = true

    // additional info view

    additionalInfoView.padding(.leading(greaterThan: 8), .bottom(greaterThan: 8))
      .spacing(.top(8), to: titleBarView)
    let additionalInfoSidebarInset = sidebars.trailingSidebar.view.leadingAnchor.constraint(equalTo: additionalInfoView.trailingAnchor, constant: 8)
    additionalInfoSidebarInset.priority = .defaultLow
    additionalInfoSidebarInset.isActive = true
    additionalInfoView.isHidden = true

    // buffer indicator view

    bufferIndicatorView.center()
    bufferIndicatorView.update()

    [timePreviewView, chapterPreviewView, osdView, additionalInfoView, bufferIndicatorView].forEach {
      $0?.setStyle(Preference.liquidGlass(.osd) ? .liquidGlass : .visualEffect)
    }

    // titlebar

    titleBarView.padding(.horizontal)

    // video view

    cv.addSubview(videoViewContainer, positioned: .below, relativeTo: nil)
    setupVideoContainerConstraints()

    addVideoViewToWindow()
    player.initVideo()
    videoView.postsFrameChangedNotifications = true

    // osc views

    oscFloatingView.setupConstraints()
    oscPlayControlView.addView(oscSpeedLabelLeftContainer, in: .center)
    oscPlayControlView.addView(oscPlayControlMiddleView, in: .center)
    oscPlayControlView.addView(oscSpeedLabelRightContainer, in: .center)
    // Video controllers and timeline indicators should not flip in a right-to-left language.
    oscPlayControlView.userInterfaceLayoutDirection = .leftToRight
    setupOnScreenController(withPosition: oscPosition, forced: true)
    let buttons = (Preference.array(for: .controlBarToolbarButtons) as? [Int] ?? []).compactMap(Preference.ToolBarButton.init(rawValue:))
    updateArrowButtons()
    setupOSCToolbarButtons(buttons)

    // fade-able views

    updateWindowButtonLayout()

    fadeableViews.add(titleBarView, visibilityHandler: { [unowned self] state in
      switch state {
      case .alwaysShown: titleBarView.setRevealed(true, animated: false)
      case .alwaysHidden: titleBarView.setRevealed(false, animated: false)
      case .auto: break
      }
    }) { [unowned self] in
      if fsState == .windowed {
        Preference.isDocked ? .alwaysShown : .auto
      } else { // full screen
        oscPosition == .top ? .auto : .alwaysHidden
      }
    }

    fadeableViews.add(additionalInfoView) { [unowned self] in
      if fsState == .windowed {
        .alwaysHidden
      } else {
        Preference.bool(for: .displayTimeAndBatteryInFullScreen) ? .auto : .alwaysHidden
      }
    }

    fadeableViews.add(oscBottomView) { [unowned self] in
      if oscPosition == .bottom {
        Preference.isDocked ? .alwaysShown : .auto
      } else {
        .alwaysHidden
      }
    }

    fadeableViews.add(oscFloatingView) { [unowned self] in
      oscPosition == .floating ? .auto : .alwaysHidden
    }

    fadeableViews.update()
    showUI()

    // other initialization
    cachedScreens = NSScreen.screens
    [pipOverlayView].forEach {
      $0?.state = .active
    }
    // hide other views
    osdView.isHidden = true
    oscSpeedLabelLeft.isHidden = true
    oscSpeedLabelRight.isHidden = true
    pipOverlayView.isHidden = true

    if player.disableUI { hideUI() }

    if let wf = windowFrameFromGeometry() {
      window.setFrame(wf, display: false)
    }

    // add user default observers
    observedPrefKeys.append(contentsOf: localObservedPrefKeys)
    localObservedPrefKeys.forEach { key in
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }

    // add notification observers

    addObserver(to: .default, forName: NSView.frameDidChangeNotification, object: videoView) { [unowned self] _ in
      if case .animating(_, _, _) = fsState {
        forceDraw("window resized during animated enter or exit full screen")
      } else if !videoView.videoLayer.inLiveResize {
        forceDraw("window resized")
      } else if Preference.unlockWindowAspectRatio && videoView.isIdle {
        forceDraw("window resized with aspect ratio unlocked and paused")
      }
    }

    addObserver(to: .default, forName: NSApplication.didChangeScreenParametersNotification) { [unowned self] _ in
      // This observer handles a situation that the user connected a new screen or removed a screen
      let screens = NSScreen.screens

      // Activating extended dynamic range will cause notifications to be posted at a high rate
      // because the screen's maximumExtendedDynamicRangeColorComponentValue property keeps changing
      // as the display's brightness ramps up. This can continue to change if the display is
      // configured to automatically adjust brightness if ambient lighting is changing. Instruments
      // identified processing these notifications as a performance problem when they occur at a
      // high rate. Compare the current list of screens to the cached list and only process this
      // notification if changes require processing this notification.
      let screensChanged: Bool = {
        guard screens.count == cachedScreens.count else { return true }
        return zip(screens, cachedScreens).contains {
          $0.frame != $1.frame || $0.displayId != $1.displayId
        }
      }()
      guard screensChanged else { return }
      // Update the cached screens
      cachedScreens = screens

      log("Screen parameters have changed")
      DisplayController.shared.addNewDisplays()
      NSScreen.logAll(subsystem: subsystem)
      NSScreen.log("Window is on screen", window.screen, details: false, subsystem: subsystem)

      if fsState.isFullscreen && Preference.bool(for: .blackOutMonitor) {
        removeBlackWindow()
        blackOutOtherMonitors()
      }
      videoView.updateDisplayLink()
      // In normal full screen mode AppKit will automatically adjust the window frame if the window
      // is moved to a new screen such as when the window is on an external display and that display
      // is disconnected. In legacy full screen mode IINA is responsible for adjusting the window's
      // frame.
      guard fsState.isFullscreen, Preference.bool(for: .useLegacyFullScreen) else { return }
      setWindowFrameForLegacyFullScreen()
    }

    // Observe the loop knobs on the progress bar and update mpv when the knobs move.
    addObserver(to: .default, forName: .iinaPlaySliderLoopKnobChanged, object: playSlider.abLoopA) { [weak self] _ in
      guard let self else { return }
      let seconds = self.percentToSeconds(self.playSlider.abLoopA.doubleValue)
      self.player.abLoopA = seconds
      self.player.sendOSD(.abLoopUpdate(.aSet, VideoTime(seconds).stringRepresentation))
    }
    addObserver(to: .default, forName: .iinaPlaySliderLoopKnobChanged, object: playSlider.abLoopB) { [weak self] _ in
      guard let self else { return }
      let seconds = self.percentToSeconds(self.playSlider.abLoopB.doubleValue)
      self.player.abLoopB = seconds
      self.player.sendOSD(.abLoopUpdate(.bSet, VideoTime(seconds).stringRepresentation))
    }

    // Observers for toolbar buttons
    let notifications: [Notification.Name] = [.iinaPIPStatusChanged, .iinaFullscreenChanged, .iinaSidebarStatusChanged]
    notifications.forEach {
      NotificationCenter.default
        .addObserver(forName: $0, object: nil, queue: .main) { [weak self] n in
          self?.updateOSCToolbarButtons(n)
        }
    }

    player.events.emit(.windowLoaded)

    // Must workaround an AppKit defect in some versions of macOS. This defect is known to exist in
    // Catalina and Big Sur. The problem was not reproducible in early versions of Monterey. It
    // reappeared in Ventura. The status of other versions of macOS is unknown, however the
    // workaround should be safe to apply in any version of macOS. The problem was reported in
    // issues #4229, #3159, #3097 and #3253. The titles of open windows shown in the "Window" menu
    // are automatically managed by the AppKit framework. To improve performance PlayerCore caches
    // and reuses player instances along with their windows. This technique is valid and recommended
    // by Apple. But in some versions of macOS, if a window is reused the framework will display the
    // title first used for the window in the "Window" menu even after IINA has updated the title of
    // the window. This problem can also be seen when right-clicking or control-clicking the IINA
    // icon in the dock. As a workaround reset the window's title to "Window" before it is reused.
    // This is the default title AppKit assigns to a window when it is first created. Surprising and
    // rather disturbing this works as a workaround, but it does.
    window.title = "Window"

    // As there have been issues in this area, log details about the screen selection process.
    NSScreen.logAll(subsystem: subsystem)
    NSScreen.log("Window is on screen", window.screen, details: false, subsystem: subsystem)

    // If a video is not actively playing then the initial drawing of the view needs to be forced.
    // The forceDraw method will check to see if drawing is actually needed.
    forceDraw("window loaded")
  }

  func setWindowToolbar() {
    guard let window else { return }

    let compactUI = Preference.bool(for: .compactUI)
    titleBarView?.restoreWindowButtons()

    applyNativeMinimumWindowSize()

    if compactUI || fsState != .windowed {
      if window.toolbar != nil { window.toolbar = nil }
    } else {
      let style: NSWindow.ToolbarStyle = .unifiedCompact
      if window.toolbar == nil { window.toolbar = NSToolbar() }
      if window.toolbarStyle != style { window.toolbarStyle = style }
      if window.toolbar?.displayMode != .iconOnly { window.toolbar?.displayMode = .iconOnly }
    }
    updateWindowButtonLayout()
  }

  /// Returns the position in seconds for the given percent of the total duration of the video the percentage represents.
  ///
  /// The number of seconds returned must be considered an estimate that could change. The duration of the video is obtained from
  /// the [mpv](https://mpv.io/manual/stable/) `duration` property. The documentation for this property cautions that
  /// mpv is not always able to determine the duration and when it does return a duration it may be an estimate. If the duration is
  /// unknown this method will fallback to using the current playback position, if that is known. Otherwise this method will return zero.
  /// - Parameter percent: Position in the video as a percentage of the duration.
  /// - Returns: The position in the video the given percentage represents.
  private func percentToSeconds(_ percent: Double) -> Double {
    if let duration = player.info.videoDuration?.second {
      return duration * percent / 100
    } else if let position = player.info.videoPosition?.second {
      return position * percent / 100
    } else {
      return 0
    }
  }

  func addVideoViewToWindow() {
    if videoView.superview != nil {
      videoView.removeFromSuperview()
    }
    videoViewContainer.addSubview(videoView)
    videoView.translatesAutoresizingMaskIntoConstraints = false

    for constraint in videoViewConstraints.values {
      constraint.isActive = false
    }
    videoViewConstraints = [
      .leading: videoView.leadingAnchor.constraint(equalTo: videoViewContainer.leadingAnchor),
      .trailing: videoViewContainer.trailingAnchor.constraint(equalTo: videoView.trailingAnchor),
      .top: videoView.topAnchor.constraint(equalTo: videoViewContainer.topAnchor),
      .bottom: videoViewContainer.bottomAnchor.constraint(equalTo: videoView.bottomAnchor)
    ]
    layoutSides.forEach { videoViewConstraints[$0]?.isActive = true }
  }

  func updateVideoViewConstraints(_ constraints: [NSLayoutConstraint.Attribute: CGFloat],
                                  priority: NSLayoutConstraint.Priority = .required) {
    let updated = constraints.keys.compactMap { videoViewConstraints[$0] }
    let changingPriority = updated.filter { $0.isActive && $0.priority != priority }
    NSLayoutConstraint.deactivate(changingPriority)
    for (attr, value) in constraints {
      videoViewConstraints[attr]?.constant = value
      videoViewConstraints[attr]?.priority = priority
    }
    NSLayoutConstraint.activate(changingPriority)
  }

  private func setupVideoContainerConstraints() {
    guard let cv = window?.contentView else { return }

    layoutSides.forEach { videoContainerConstraints[$0].flatMap(cv.removeConstraint) }
    NSLayoutConstraint.deactivate(videoContainerPhysicalConstraints)
    videoContainerPhysicalConstraints = []
    if Preference.bool(for: .edgeToEdgeVideo) {
      layoutSides.forEach { attr in
        videoContainerConstraints[attr] = NSLayoutConstraint(item: videoViewContainer!, attribute: attr, relatedBy: .equal,
                                                        toItem: cv, attribute: attr, multiplier: 1, constant: 0)
      }
    } else {
      let docked = Preference.bool(for: .dockedControlBarAndTitlebar)
      videoContainerConstraints[.top] = videoViewContainer.topAnchor
        .constraint(equalTo: docked ? titleBarView.bottomAnchor : cv.topAnchor)
      videoContainerConstraints[.bottom] = videoViewContainer.bottomAnchor
        .constraint(equalTo: docked ? oscBottomView.topAnchor : cv.bottomAnchor)
      videoContainerConstraints[.leading] = videoViewContainer.leadingAnchor
        .constraint(equalTo: sidebars.leadingSidebar.view.trailingAnchor)
      videoContainerConstraints[.trailing] = videoViewContainer.trailingAnchor
        .constraint(equalTo: sidebars.trailingSidebar.view.leadingAnchor)
      // Sidebar insets must yield before they enlarge a narrow window.
      videoContainerConstraints[.leading]?.priority = .defaultLow
      videoContainerConstraints[.trailing]?.priority = .defaultLow
      videoContainerPhysicalConstraints = [
        videoViewContainer.leftAnchor.constraint(greaterThanOrEqualTo: cv.leftAnchor),
        videoViewContainer.rightAnchor.constraint(lessThanOrEqualTo: cv.rightAnchor),
        videoViewContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
      ]
      NSLayoutConstraint.activate(videoContainerPhysicalConstraints)
    }
    layoutSides.forEach { videoContainerConstraints[$0]?.isActive = true }
  }

  @objc func removeVideoViewBlackBars() {
    guard let window, Preference.unlockWindowAspectRatio, !fsState.isFullscreen else { return }

    let currentSize = videoViewContainer.frame.size
    let videoSize = player.videoSizeForDisplay
    let newSize = currentSize.crop(withAspect: CGFloat(videoSize.0) / CGFloat(videoSize.1))
    let dw = newSize.width - currentSize.width
    let dh = newSize.height - currentSize.height
    let currWindowSize = window.frame.size
    let newWindowSize = NSSize(width: max(currWindowSize.width + dw, minimumWindowSize.width),
                               height: max(currWindowSize.height + dh, minimumWindowSize.height))
    let newFrame = windowFrameConstrainedToScreen(window.frame.centeredResize(to: newWindowSize),
                                                 screenFrame: window.screen?.visibleFrame)

    window.setFrame(newFrame, display: true, animate: true)
  }

  private func setupOSCToolbarButtons(_ buttons: [Preference.ToolBarButton]) {
    let effectiveButtons = buttons.filter { $0 != .liveText || Preference.isLiveTextEnabled }
    oscToolbarView.views.forEach { oscToolbarView.removeView($0) }
    let liveTextEnabled = Preference.bool(for: .enableLiveText)
    for buttonType in effectiveButtons {
      let button = NSButton()
      OSCToolbarButton.setStyle(of: button, buttonType: buttonType, reducedWidth: false)
      if buttonType == .liveText && liveTextEnabled {
        button.image = Preference.ToolBarButton.liveText.alternateImage()
      }
      button.action = #selector(self.toolBarButtonAction(_:))
      oscToolbarView.addView(button, in: .trailing)
    }

    floatingOSCToolbarConstraints = oscToolbarView.views.flatMap { view in
      view.constraints.filter {
        $0.secondItem == nil && ($0.firstAttribute == .width || $0.firstAttribute == .height)
      }.map { (constraint: $0, original: $0.constant) }
    }
    applyFloatingOSCControlScale()

//    let menuButton = NSButton()
//    menuButton.bezelStyle = .regularSquare
//    menuButton.image = .sf("chevron.forward.2")
//    menuButton.isBordered = false
//    menuButton.refusesFirstResponder = true
//    menuButton.size(width: Preference.ToolBarButton.frameSize, height: Preference.ToolBarButton.frameSize)
//    oscToolbarView.addView(menuButton, in: .trailing)
  }

  @objc
  private func updateOSCToolbarButtons(_ notification: Notification) {
    func highlight(_ button: Preference.ToolBarButton, _ isHighlighted: Bool) {
      let buttons = oscToolbarView.subviews as! [NSButton]
      let currentButton = buttons.first(where: { $0.tag == button.rawValue })
      currentButton?.image = isHighlighted ? button.alternateImage() : button.image()
    }

    let enable = (notification.userInfo?["enable"] as? Bool ?? false)
    switch notification.name {
    case .iinaPIPStatusChanged:
      highlight(.pip, enable)
    case .iinaFullscreenChanged:
      highlight(.fullScreen, enable)
    case .iinaSidebarStatusChanged:
      // no userInfo is provided in this notification
      highlight(.settings, sidebars.isShowing(.settings))
      highlight(.plugins, sidebars.isShowing(.plugins))
      highlight(.playlist, sidebars.isShowing(.playlist))
      fadeableViews.update()
    default:
      break
    }
  }

  private func setupOnScreenController(withPosition newPosition: Preference.OSCPosition, forced: Bool = false) {
    guard forced || oscPosition != newPosition else { return }

    let isSwitchingToTop = newPosition == .top
    let isSwitchingFromTop = oscPosition == .top
    let isFloating = newPosition == .floating

    // reset
    hideSeekPreview()
    oscFloatingView.cancelPositionAnimation()
    [oscFloatingView, oscBottomView].forEach { $0.isHidden = true }

    oscFloatingView.isDragging = false

    floatingOSCControlsView?.detachControls()
    floatingOSCControlsView = nil

    // detach all fragment views
    [oscFloatingView.oscTopView, titleBarView.oscView, oscBottomView.oscView].forEach { stackView in
      stackView!.views.forEach {
        stackView!.removeView($0)
      }
    }
    [oscSliderView, oscPlayControlView, oscToolbarView, oscVolumeView].forEach {
        $0!.removeFromSuperview()
    }

    let isInFullScreen = fsState.isFullscreen
    titleBarView.update(hasOSC: isSwitchingToTop, inFullScreen: isInFullScreen)

    if isSwitchingFromTop && isInFullScreen {
      titleBarView.isHidden = true
    }

    oscBottomView.updateVerticalConstraint(isDisplaying: newPosition == .bottom)

    oscPosition = newPosition

    // add fragment views
    switch oscPosition {
    case .floating:
      currentControlBar = oscFloatingView
      applyFloatingOSCControlScale()
      let row = FloatingOSCControlsView(volume: oscVolumeView, playback: oscPlayControlView,
                                        toolbar: oscToolbarView,
                                        speedLabels: [oscSpeedLabelLeftContainer, oscSpeedLabelRightContainer],
                                        scale: floatingOSCScale, buttonCount: oscToolbarView.views.count)
      floatingOSCControlsView = row
      oscFloatingView.oscTopView.addSubview(row)
      NSLayoutConstraint.activate([
        row.leadingAnchor.constraint(equalTo: oscFloatingView.oscTopView.leadingAnchor),
        row.trailingAnchor.constraint(equalTo: oscFloatingView.oscTopView.trailingAnchor),
        row.topAnchor.constraint(equalTo: oscFloatingView.oscTopView.topAnchor),
        row.bottomAnchor.constraint(equalTo: oscFloatingView.oscTopView.bottomAnchor)
      ])
      oscFloatingView.oscBottomView.addSubview(oscSliderView)
      Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": oscSliderView])
      oscFloatingView.updatePosition()
    case .top:
      let oscTopMainView = titleBarView.oscView!
      currentControlBar = nil
      oscPlayControlView.setVisibilityPriority(.notVisible, for: oscSpeedLabelLeftContainer)
      oscPlayControlView.setVisibilityPriority(.notVisible, for: oscSpeedLabelRightContainer)
      oscTopMainView.addView(oscVolumeView, in: .trailing)
      oscTopMainView.addView(oscToolbarView, in: .trailing)
      oscTopMainView.addView(oscPlayControlView, in: .leading)
      oscTopMainView.addView(oscSliderView, in: .leading)
      oscTopMainView.setClippingResistancePriority(.defaultLow, for: .horizontal)
      oscTopMainView.setVisibilityPriority(.mustHold, for: oscSliderView)
      oscTopMainView.setVisibilityPriority(.detachEarly, for: oscVolumeView)
      oscTopMainView.setVisibilityPriority(.detachEarlier, for: oscToolbarView)
    case .bottom:
      oscBottomView.isHidden = false
      let oscBottomMainView = oscBottomView.oscView!
      currentControlBar = oscBottomView
      oscPlayControlView.setVisibilityPriority(.notVisible, for: oscSpeedLabelLeftContainer)
      oscPlayControlView.setVisibilityPriority(.notVisible, for: oscSpeedLabelRightContainer)
      oscBottomMainView.addView(oscVolumeView, in: .trailing)
      oscBottomMainView.addView(oscToolbarView, in: .trailing)
      oscBottomMainView.addView(oscPlayControlView, in: .leading)
      oscBottomMainView.addView(oscSliderView, in: .leading)
      oscBottomMainView.setClippingResistancePriority(.defaultLow, for: .horizontal)
      oscBottomMainView.setVisibilityPriority(.mustHold, for: oscSliderView)
      oscBottomMainView.setVisibilityPriority(.detachEarly, for: oscVolumeView)
      oscBottomMainView.setVisibilityPriority(.detachEarlier, for: oscToolbarView)
    }

    oscPlayControlMiddleView.spacing = isFloating ? 24: 16

    // Docked layouts reuse the same controls; restore their unscaled dimensions.
    applyFloatingOSCControlScale()
    updateMinimumWindowSize()

    fadeableViews.update()
    showUI()
  }

  func updateFloatingOSCScale(scale: CGFloat) {
    let boundedScale = scale.isFinite ? max(FloatingOSCScale.minimum, min(FloatingOSCScale.maximum, scale)) : 1
    guard floatingOSCScale != boundedScale else { return }
    floatingOSCScale = boundedScale
    applyFloatingOSCControlScale()
  }

  private func configureFloatingOSCDistributions() {
    for stack in [oscPlayControlView!, oscPlayControlMiddleView!, oscToolbarView!] {
      if oscPosition == .floating {
        if floatingOSCOriginalDistributions[stack] == nil {
          floatingOSCOriginalDistributions[stack] = stack.distribution
        }
        if stack.distribution != .fill { stack.distribution = .fill }
      } else if let distribution = floatingOSCOriginalDistributions.removeValue(forKey: stack) {
        if stack.distribution != distribution { stack.distribution = distribution }
      }
    }
  }

  private func applyFloatingOSCControlScale() {
    configureFloatingOSCDistributions()
    let scale = oscPosition == .floating ? floatingOSCScale : 1
    for item in floatingOSCControlConstraints + floatingOSCToolbarConstraints {
      let constant = item.original * scale
      if item.constraint.constant != constant { item.constraint.constant = constant }
    }
    let spacing = oscPosition == .floating ? 24 * scale : 16
    if oscPlayControlMiddleView.spacing != spacing { oscPlayControlMiddleView.spacing = spacing }
    let labelFont = NSFont.monospacedDigitSystemFont(ofSize: max(10, 11 * scale), weight: .regular)
    [leftLabel, rightLabel].forEach {
      if $0!.font != labelFont { $0!.font = labelFont }
    }
    // The already-small speed labels stay readable while their padding contracts.
    let speedFont = NSFont.systemFont(ofSize: 10)
    [oscSpeedLabelLeft, oscSpeedLabelRight].forEach { if $0!.font != speedFont { $0!.font = speedFont } }
    for (button, originalScaling) in floatingOSCOriginalImageScaling {
      let scaling = scale < 1 ? NSImageScaling.scaleProportionallyDown : originalScaling
      if button.imageScaling != scaling { button.imageScaling = scaling }
    }
    muteButton.imageView.symbolConfiguration = scale < 1 ? .init(pointSize: 13 * scale, weight: .regular) : nil
    for case let button as NSButton in oscToolbarView.views {
      let type = Preference.ToolBarButton(rawValue: button.tag)
      let pointSize: CGFloat = type == .pip || type == .plugins ? 13.5 : 14
      button.symbolConfiguration = scale < 1 ? .init(pointSize: pointSize * scale, weight: .medium) : nil
    }
    floatingOSCControlsView?.update(scale: scale, buttonCount: oscToolbarView.views.count)
    oscPlayControlView.needsLayout = true
    oscToolbarView.needsLayout = true
  }

  // MARK: - Mouse / Trackpad events

  override func keyDown(with event: NSEvent) {
    if isShowingPersistentOSD {
      let keyCode = KeyCodeHelper.mpvKeyCode(from: event)
      let normalizedKeyCode = KeyCodeHelper.normalizeMpv(keyCode)

      if normalizedKeyCode == "ESC", osdView.performKeyEquivalent(with: event) {
        log("ESC key was handled by OSD", level: .verbose)
        return
      }
    }

    super.keyDown(with: event)
  }

  /// Native tracking, sheets and Crop own Escape before player menus or plugin content.
  func handleDefaultEscape(with event: NSEvent) -> Bool {
    guard KeyCodeHelper.normalizeMpv(KeyCodeHelper.mpvKeyCode(from: event)) == "ESC",
          PlayerCore.keyBindings["ESC"]?.usesDefaultEscape == true,
          let window, event.window === window, NSApp.keyWindow === window,
          window.attachedSheet == nil, !interactiveMode.isActive, !isPluginMenuTracking else { return false }
    if event.isARepeat { return true }
    if isCropTransitionInProgress {
      cancelCropExitTransition()
      handleVideoSizeChange(keepWindowSize: true)
      return true
    }
    if isShowingPersistentOSD, osdView.performKeyEquivalent(with: event) { return true }
    guard sidebars.isAnyVisibleOrTransitioning else { return false }
    sidebars.hideAllSideBars()
    window.makeFirstResponder(window)
    return true
  }

  @discardableResult
  override func handleKeyBinding(_ keyBinding: KeyMapping) -> Bool {
    let success = super.handleKeyBinding(keyBinding)
    guard success, let command = keyBinding.action.first else { return success }
    if command == MPVCommand.screenshot.rawValue {
      player.sendOSD(.screenshot)
    }

    if !keyBinding.isIINACommand {
      switch command {
      case MPVCommand.showProgress.rawValue:
        player.sendOSD(.showTime(player.info.progress))
      default: ()
      }
    }

    return success
  }

  override func pressureChange(with event: NSEvent) {
    if isCurrentPressInSecondStage == false && event.stage == 2 {
      performMouseAction(Preference.enum(for: .forceTouchAction))
      isCurrentPressInSecondStage = true
    } else if event.stage == 1 {
      isCurrentPressInSecondStage = false
    }
  }

  /// Workaround for issue #4183, Cursor remains visible after resuming playback with the touchpad using secondary click
  ///
  /// When IINA hides the OSC it also calls the macOS AppKit method `NSCursor.setHiddenUntilMouseMoves` to hide the
  /// cursor. In macOS Catalina that method works as documented and keeps the cursor hidden until the mouse moves. Starting with
  /// macOS Big Sur the cursor becomes visible if mouse buttons are clicked without moving the mouse. To workaround this defect
  /// call this method again to keep the cursor hidden when the OSC is not visible.
  ///
  /// This erroneous behavior has been reported to Apple as: "Regression in NSCursor.setHiddenUntilMouseMoves"
  /// Feedback number FB11963121
  private func workaroundCursorDefect() {
    guard animationState == .hidden else { return }
    NSCursor.setHiddenUntilMouseMoves(true)
  }

  override func mouseDown(with event: NSEvent) {
    cancelWindowDrag()
    guard let window, event.type == .leftMouseDown, event.window === window else { return }
    if interactiveMode.isActive {
      if !fsState.isFullscreen, NSEvent.pressedMouseButtons & 1 != 0,
         interactiveMode.canDragWindow(at: event.locationInWindow) {
        window.performDrag(with: event)
      }
      return
    }
    if Logger.isEmitting(.verbose) {
      log("MainWindow mouseDown @ \(event.locationInWindow)", level: .verbose)
    }
    workaroundCursorDefect()
    // do nothing if it's related to floating OSC
    guard !oscFloatingView.isDragging else { return }
    let consumedBySidebar = sidebars.handleMouseDown(event, at: event.locationInWindow)
    if !fsState.isFullscreen, sidebars.resizingSidebarSide == nil {
      windowDragMouseDownEvent = event
    }
    // currently, it only passes the event to plugins in super
    if !consumedBySidebar {
      super.mouseDown(with: event)
    }
  }

  override func mouseDragged(with event: NSEvent) {
    guard !interactiveMode.isActive else { return }
    if sidebars.handleMouseDragged(event) {
      return
    }
    guard !fsState.isFullscreen, !oscFloatingView.isDragging, let window,
          event.type == .leftMouseDragged, event.window === window else {
      windowDragMouseDownEvent = nil
      return
    }
    let mouseDown = windowDragMouseDownEvent
    let exceededThreshold = mouseDown.map {
      $0.locationInWindow.distance(to: event.locationInWindow) > minimumInitialDragDistance
    } ?? false
    guard NSEvent.pressedMouseButtons & 1 != 0 else {
      didDragWindow = didDragWindow || exceededThreshold
      windowDragMouseDownEvent = nil
      return
    }
    if didDragWindow {
      super.informPluginMouseDragged(with: event)
      return
    }
    guard let mouseDown, exceededThreshold else { return }
    // Window Server may consume mouseUp, so hand off the original press only once.
    windowDragMouseDownEvent = nil
    didDragWindow = true
    window.performDrag(with: mouseDown)
    super.informPluginMouseDragged(with: event)
  }

  func cancelWindowDrag() {
    windowDragMouseDownEvent = nil
    didDragWindow = false
  }

  override func mouseUp(with event: NSEvent) {
    let wasDragging = didDragWindow
    cancelWindowDrag()
    guard !interactiveMode.isActive else { return }
    if Logger.isEmitting(.verbose) {
      log("MainWindow mouseUp @ \(event.locationInWindow), didDragWindow: \(wasDragging), resizingSidebar: \(String(describing: sidebars.resizingSidebarSide)), clickCount: \(event.clickCount)", level: .verbose)
    }
    workaroundCursorDefect()
    guard !wasDragging else { return }
    if sidebars.handleMouseUp(event) {
      // sidebar handled it (resize finish or click-outside-to-dismiss)
    } else if restoreUIFromVideoClick(event) {
    } else {
      if event.clickCount == 2 && event.inAnyOf([titleBarView]) {
        // Honor the system titlebar action when our custom header receives it.
        let userDefault = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
        if userDefault == "Minimize" {
          window?.performMiniaturize(nil)
        } else if userDefault == "Maximize" {
          window?.performZoom(nil)
        }
        return
      }

      super.mouseUp(with: event)
    }
  }

  override func otherMouseDown(with event: NSEvent) {
    workaroundCursorDefect()
    super.otherMouseDown(with: event)
  }

  override func otherMouseUp(with event: NSEvent) {
    workaroundCursorDefect()
    super.otherMouseUp(with: event)
  }

  /// Workaround for issue #4183, Cursor remains visible after resuming playback with the touchpad using secondary click
  ///
  /// AppKit contains special handling for [rightMouseDown](https://developer.apple.com/documentation/appkit/nsview/event_handling/1806802-rightmousedown) having to do with contextual menus.
  /// Even though the documentation indicates the event will be passed up the responder chain, the event is not being received by the
  /// window controller. We are having to catch the event in the view. Because of that we do not call the super method and instead
  /// return to the view.`
  override func rightMouseDown(with event: NSEvent) {
    workaroundCursorDefect()
    super.rightMouseDown(with: event)
  }

  override func rightMouseUp(with event: NSEvent) {
    workaroundCursorDefect()
    super.rightMouseUp(with: event)
  }

  override internal func performMouseAction(_ action: Preference.MouseClickAction) {
    super.performMouseAction(action)
    switch action {
    case .fullscreen:
      toggleWindowFullScreen()
    case .hideOSC:
      hideUIAndCursor()
    case .togglePIP:
      menuTogglePIP(.dummy)
    case .abLoop:
      player.abLoop()
    case .resetSpeed:
      player.setSpeed(1.0)
    default:
      break
    }
  }

  override func scrollWheel(with event: NSEvent) {
    guard !interactiveMode.isActive else { return }
    // A slider's coordinates alone do not make it interactive behind a sidebar.
    guard !sidebars.isEventTargetingVisibleSidebar(event) else { return }
    if !isMomentumScrollingAllowed && !event.momentumPhase.isEmpty {
      // ignore delta caused by abrupt momentum phases
      return
    }
    /**
     reference: https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html#//apple_ref/doc/uid/10000060i-CH13

     normal momentum scrolling will be like this:
        phase=Began momentumPhase=None
        phase=Changed momentumPhase=None
        ...
        **phase=Ended** momentumPhase=None
        **phase=None** momentumPhase=None
        phase=None **momentumPhase=Began**

     abnormal momentum scrolling, e.g. after dismissing notification banner quickly like:
        phase=None **momentumPhase=Began/Changed**
     */
    isMomentumScrollingAllowed = event.phase.contains(.ended) || isMouseInWindow // previous
    if event.inAnyOf([playSlider]) && playSlider.isEnabled {
      seekOverride = true
    } else if event.inAnyOf([volumeSlider]) && volumeSlider.isEnabled {
      volumeOverride = true
    } else {
      guard !event.inAnyOf([currentControlBar]) else { return }
    }

    guard !event.inAnyOf([titleBarView])
               || seekOverride || volumeOverride else { return }

    super.scrollWheel(with: event)

    seekOverride = false
    volumeOverride = false
  }

  override func mouseEntered(with event: NSEvent) {
    guard !interactiveMode.isActive else { return }
    guard let obj = event.trackingArea?.userInfo?["obj"] as? Int else {
      log("No data for tracking area", level: .warning)
      return
    }
    mouseExitEnterCount += 1
    if obj == 0 {
      // Popup dismissal can repeat entry without leaving the player.
      let wasOutside = !isMouseInWindow
      isMouseInWindow = true
      if !isUIHiddenByOSCClick || wasOutside {
        showUI()
        updateTimer()
      }
    } else if obj == 1 {
      // slider
      if oscFloatingView.isDragging || oscFloatingView.isReturningToDefault { return }
      refreshSeekTimeAndThumbnail(from: event)
    }
  }

  override func mouseExited(with event: NSEvent) {
    guard !interactiveMode.isActive else { return }
    guard let obj = event.trackingArea?.userInfo?["obj"] as? Int else {
      log("No data for tracking area", level: .warning)
      return
    }
    mouseExitEnterCount += 1
    if obj == 0 {
      // Menu tracking can report an exit while the pointer remains inside.
      if isUIHiddenByOSCClick, let contentView = window?.contentView,
         contentView.bounds.contains(contentView.convert(event.locationInWindow, from: nil)) { return }
      isMouseInWindow = false
      hideSeekPreview()
      if oscFloatingView.isDragging || oscFloatingView.isReturningToDefault { return }
      destroyTimer()
      hideUI()
      // reset after moved out of window
      isMomentumScrollingAllowed = false
    } else if obj == 1 {
      // slider
      refreshSeekTimeAndThumbnail(from: event)
    }
  }

  override func mouseMoved(with event: NSEvent) {
    guard !interactiveMode.isActive else { return }

    refreshSeekTimeAndThumbnail(from: event)
    if isMouseInWindow && !isUIHiddenByOSCClick &&
      animationState != .shown && animationState != .willShow {
      showUI()
    }
    // check whether mouse is in osc
    if event.inAnyOf([currentControlBar, titleBarView]) {
      destroyTimer()
    } else {
      updateTimer()
    }
  }

  @objc func handleMagnifyGesture(recognizer: NSMagnificationGestureRecognizer) {
    if interactiveMode.isActive {
      interactiveMode.handleMagnifyGesture(recognizer)
      return
    }
    guard pinchAction != .none else { return }
    guard !interactiveMode.isActive, let window, let screenFrame = NSScreen.main?.visibleFrame else { return }

    switch pinchAction {
    case .none:
      return
    case .fullscreen:
      // enter/exit fullscreen
      if recognizer.state == .began {
        let isEnlarge = recognizer.magnification > 0
        if isEnlarge != fsState.isFullscreen {
          recognizer.state = .recognized
          self.toggleWindowFullScreen()
        }
      }
    case .windowSize:
      if fsState.isFullscreen { return }

      // adjust window size
      if recognizer.state == .began {
        // began
        cancelVideoGeometryTransition(settleWindowFrame: false)
        lastMagnification = recognizer.magnification
        videoView.videoLayer.inLiveResize = true
        frameWhenStartedPinching = window.frame
      } else if recognizer.state == .changed {
        // changed
        let offset = recognizer.magnification - lastMagnification + 1.0;
        let newWidth = window.frame.width * offset
        let newHeight = newWidth / frameWhenStartedPinching.size.aspect

        //Check against max & min threshold
        if newHeight < screenFrame.height && newHeight > minimumWindowSize.height && newWidth > minimumWindowSize.width {
          let newSize = NSSize(width: newWidth, height: newHeight);
          window.setFrame(frameWhenStartedPinching.centeredResize(to: newSize), display: true)
        }

        lastMagnification = recognizer.magnification
      } else if recognizer.state == .ended {
        rememberVideoTransformWindowResize()
        updateWindowParametersForMPV()
        videoView.videoLayer.inLiveResize = false
      }
    }
  }

  // MARK: - Window delegate: Open / Close

  /// Displays the window.
  /// - Important: AppKit will refuse to move a window to a different screen before the window has been shown. If the origin
  ///     places the window on a screen other than `window.screen` then
  ///     [showWindow](https://developer.apple.com/documentation/appkit/nswindowcontroller/showwindow(_:))
  ///     will adjust the origin such that the window is within the current screen of the window. This will happen when
  ///     `determineScreenToUse` selects a different screen for the window based on `MainWindowLastPosition`.  To
  ///     workaround the AppKit behavior requires allowing `showWindow` to complete and then resetting the origin to display the
  ///     window on the correct screen. As of macOS Tahoe this AppKit defect has been fixed.
  /// - Parameter sender: The control sending the message; can be `nil`.
  override func showWindow(_ sender: Any?) {
    guard let window else { return }
    sidebars.pluginView.beginWindowSession()
    oscFloatingView?.beginWindowSession()
    log("Showing window at \(window.frame)")
    let origin = window.frame.origin
    super.showWindow(sender)
    if #unavailable(macOS 26), Preference.bool(for: .enableWrongScreenWorkaround),
       NSScreen.screens.count > 1, window.frame.origin != origin {
      log("NSWindowController.showWindow changed origin from \(origin) to \(window.frame.origin)")
      if player.info.state == .loaded, Preference.bool(for: .fullScreenWhenOpen),
         !fsState.isFullscreen, !player.isInMiniPlayer {
        // PlayerCore.notifyWindowVideoSizeChanged will be toggling the window into full screen
        // mode. Merely resetting the origin works when NSWindow.toggleFullScreen is called.
        log("Resetting window origin to \(origin)")
        window.setFrameOrigin(origin)
      } else {
        // When not immediately toggling into full screen mode resetting the origin will not work
        // unless it is done in another task.
        log("Applying workaround for AppKit using the wrong screen")
        window.alphaValue = 0
        DispatchQueue.main.async {
          self.log("Resetting window origin to \(origin)")
          window.setFrameOrigin(origin)
          window.alphaValue = 1
        }
      }
    }
    resetCollectionBehavior()
    // update buffer indicator view
    bufferIndicatorView.update()
    // start tracking mouse event
    guard let cv = window.contentView else { return }
    if cv.trackingAreas.isEmpty {
      cv.addTrackingArea(NSTrackingArea(rect: cv.bounds,
                                        options: [.activeAlways, .enabledDuringMouseDrag, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                                        owner: self, userInfo: ["obj": 0]))
    }
    if playSlider.trackingAreas.isEmpty {
      playSlider.addTrackingArea(NSTrackingArea(rect: playSlider.bounds,
                                                options: [.activeAlways, .enabledDuringMouseDrag, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                                                owner: self, userInfo: ["obj": 1]))
    }
    // Track the thumbs on the progress bar representing the A-B loop points and treat them as part
    // of the slider.
    if playSlider.abLoopA.trackingAreas.count <= 1 {
      playSlider.abLoopA.addTrackingArea(NSTrackingArea(rect: playSlider.abLoopA.bounds, options:  [.activeAlways, .enabledDuringMouseDrag, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self, userInfo: ["obj": 1]))
    }
    if playSlider.abLoopB.trackingAreas.count <= 1 {
      playSlider.abLoopB.addTrackingArea(NSTrackingArea(rect: playSlider.abLoopB.bounds, options: [.activeAlways, .enabledDuringMouseDrag, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self, userInfo: ["obj": 1]))
    }

    // update timer
    updateTimer()
    // truncate middle for title
    if let attrTitle = titleTextField?.attributedStringValue.mutableCopy() as? NSMutableAttributedString, attrTitle.length > 0 {
      let p = attrTitle.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSMutableParagraphStyle
      p.lineBreakMode = .byTruncatingMiddle
      attrTitle.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: attrTitle.length))
    }
  }

  func windowWillClose(_ notification: Notification) {
    cancelOperationFeedback()
    cancelWindowDrag()
    cancelCropExitTransition()
    finishFullscreenVideoTransition(cancelled: true)
    finishVideoAspectTransition()
    isSeekingWithSlider = false
    interactiveMode.exit()
    sidebars.pluginView.endWindowSession()
    oscFloatingView?.endWindowSession()
    // Close PIP
    if pipStatus == .inPIP {
      exitPIP()
    }
    // stop playing
    if case .fullscreen(legacy: true, priorWindowedFrame: _) = fsState {
      restoreDockSettings()
      cameraHousingWindow?.orderOut(self)
      cameraHousingWindow = nil
    }
    player.stop()
    resetWindowSizingForNewSession()
    // stop tracking mouse event
    guard let w = self.window, let cv = w.contentView else { return }
    cv.trackingAreas.forEach(cv.removeTrackingArea)
    playSlider.trackingAreas.forEach(playSlider.removeTrackingArea)
    UserDefaults.standard.set(NSStringFromRect(window!.frame), forKey: "MainWindowLastPosition")
    // Reset default visibilities
    hideSeekPreview()

    player.events.emit(.windowWillClose)
  }

  // MARK: - Window delegate: Full screen

  private func beginFullscreenVideoTransition() {
    guard fullscreenVideoConstraints.isEmpty, pipStatus == .notInPIP,
          !interactiveMode.isActive, !isCropTransitionInProgress,
          player.info.state.active, let window else { return }
    let (width, height) = player.videoSizeForDisplay
    guard width > 0, height > 0 else { return }
    videoView.videoLayer.beginFullscreenTransition()
    // Keep mpv's surface at the image aspect while AppKit changes the window aspect.
    NSLayoutConstraint.deactivate(Array(videoViewConstraints.values))
    let widthFit = videoView.widthAnchor.constraint(equalTo: videoViewContainer.widthAnchor)
    let heightFit = videoView.heightAnchor.constraint(equalTo: videoViewContainer.heightAnchor)
    widthFit.priority = .defaultHigh
    heightFit.priority = .defaultHigh
    fullscreenVideoConstraints = [
      videoView.centerXAnchor.constraint(equalTo: videoViewContainer.centerXAnchor),
      videoView.centerYAnchor.constraint(equalTo: videoViewContainer.centerYAnchor),
      videoView.widthAnchor.constraint(equalTo: videoView.heightAnchor, multiplier: CGFloat(width) / CGFloat(height)),
      videoView.widthAnchor.constraint(lessThanOrEqualTo: videoViewContainer.widthAnchor),
      videoView.heightAnchor.constraint(lessThanOrEqualTo: videoViewContainer.heightAnchor),
      widthFit, heightFit
    ]
    NSLayoutConstraint.activate(fullscreenVideoConstraints)
    window.contentView?.layoutSubtreeIfNeeded()
  }

  private func finishFullscreenVideoTransition(cancelled: Bool = false) {
    guard !fullscreenVideoConstraints.isEmpty else { return }
    // The old fitted surface must stay fitted until mpv publishes the full-bounds surface.
    videoView.videoLayer.endFullscreenTransition(cancelled: cancelled)
    NSLayoutConstraint.deactivate(fullscreenVideoConstraints)
    fullscreenVideoConstraints.removeAll()
    NSLayoutConstraint.activate(Array(videoViewConstraints.values))
    window?.contentView?.layoutSubtreeIfNeeded()
    if !cancelled { videoView.videoLayer.update(force: true) }
    if loaded, oscPosition == .floating {
      invalidateFloatingOSCLayout()
      oscFloatingView.updatePosition()
    }
  }

  func customWindowsToEnterFullScreen(for window: NSWindow) -> [NSWindow]? {
    return [window]
  }

  func customWindowsToExitFullScreen(for window: NSWindow) -> [NSWindow]? {
    return [window]
  }

  func window(_ window: NSWindow, startCustomAnimationToEnterFullScreenOn screen: NSScreen, withDuration duration: TimeInterval) {
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = Preference.bool(for: PK.disableAnimations) ? 0 : duration
      window.animator().setFrame(screen.frame, display: true)
    }, completionHandler: nil)
  }

  func window(_ window: NSWindow, startCustomAnimationToExitFullScreenWithDuration duration: TimeInterval) {
    if NSMenu.menuBarVisible() {
      NSMenu.setMenuBarVisible(false)
    }
    let priorWindowedFrame = fsState.priorWindowedFrame!

    NSAnimationContext.runAnimationGroup({ context in
      context.duration = Preference.bool(for: PK.disableAnimations) ? 0 : duration
      window.animator().setFrame(priorWindowedFrame, display: true)
    }, completionHandler: nil)

    NSMenu.setMenuBarVisible(true)
  }

  /// The window is about to enter full screen mode.
  ///
  /// The `NSWindowDelegate` method
  /// [windowWillEnterFullScreen](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowwillenterfullscreen(_:))
  /// is called after the AppKit
  /// [toggleFullScreen](https://developer.apple.com/documentation/appkit/nswindow/togglefullscreen(_:))
  /// method has been called when the window is not in full screen mode. Prepare the window to start transitioning to full screen mode.
  /// - Attention: After altering this method you _must_ update the
  ///     [windowDidFailToEnterFullScreen](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowdidfailtoenterfullscreen(_:))
  ///     method which is responsible for reverting changes made by this method should the transition to full screen mode fail.
  /// - Parameter notification: A notification named
  ///     [willEnterFullScreenNotification](https://developer.apple.com/documentation/appkit/nswindow/willenterfullscreennotification).
  func windowWillEnterFullScreen(_ notification: Notification) {
    log("Entering full screen mode")
    interruptPlayerCropTransition()
    if isCropTransitionInProgress { cancelCropExitTransition() }
    interactiveMode.exit()
    let isLegacyFullScreen = notification.name == .iinaLegacyFullScreen
    fsState.startAnimatingToFullScreen(legacy: isLegacyFullScreen, priorWindowedFrame: window!.frame)
    if notification.name != .iinaLegacyFullScreen { beginFullscreenVideoTransition() }
    // When playback is paused the display link is stopped in order to avoid wasting energy on
    // needless processing. It must be running while transitioning to full screen mode.
    videoView.displayActive()

    liveText.clearAnalysis()

    // Set the appearance to match the theme so the titlebar matches the theme
    let iinaTheme = Preference.enum(for: .themeMaterial) as Preference.Theme
    window?.appearance = NSAppearance(iinaTheme: iinaTheme)

    // show titlebar
    titleBarView.update(hasOSC: oscPosition == .top, inFullScreen: true)
    standardWindowButtons.forEach { $0.alphaValue = 0 }
    titleTextField?.alphaValue = 0

    setWindowFloatingOnTop(false, updateOnTopStatus: false)

    hideSeekPreview()

    // Keep fullscreen content below the native window controls.
    if !isLegacyFullScreen { window?.styleMask.remove(.fullSizeContentView) }
    setWindowToolbar()
    fadeableViews.update()
  }

  /// The window has entered full screen mode.
  ///
  /// The `NSWindowDelegate` method
  /// [windowDidEnterFullScreen](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowdidenterfullscreen(_:))
  /// is called after the transition into full screen mode has finished. Finish configuring the window for full screen mode.
  /// - Parameter notification: A notification named
  ///     [didEnterFullScreenNotification](https://developer.apple.com/documentation/appkit/nswindow/didenterfullscreennotification).
  func windowDidEnterFullScreen(_ notification: Notification) {
    log("Entered full screen mode")
    defer { finishFullscreenVideoTransition() }
    fsState.finishAnimating()

    titleTextField?.alphaValue = 1
    for view in standardWindowButtons {
      view.alphaValue = 1
      view.isHidden = false
    }
    window?.titlebarAppearsTransparent = false

    liveText.requestAnalysis()

    videoView.needsLayout = true
    videoView.layoutSubtreeIfNeeded()
    forceDraw("entered full screen mode")

    if Preference.bool(for: .blackOutMonitor) {
      blackOutOtherMonitors()
    }
    fadeableViews.update()

    if player.info.state == .paused {
      if Preference.bool(for: .playWhenEnteringFullScreen) {
        player.resume()
      } else {
        // When playback is paused the display link is stopped in order to avoid wasting energy on
        // needless processing. It must be running while transitioning to full screen mode. Now that
        // the transition has completed it can be stopped.
        videoView.displayIdle()
      }
    }

    player.touchBarSupport.toggleTouchBarEsc(enteringFullScr: true)

    updateWindowParametersForMPV()

    // Exit PIP if necessary
    if pipStatus == .inPIP {
      exitPIP()
    }

    additionalInfoView.update()
    player.events.emit(.windowFullscreenChanged, data: true)
    NotificationCenter.default.post(name: .iinaFullscreenChanged, object: nil, userInfo: ["enable": true])
  }

  /// Called if the window failed to enter full screen mode.
  ///
  /// The AppKit [toggleFullScreen](https://developer.apple.com/documentation/appkit/nswindow/togglefullscreen(_:))
  /// method can fail. If that happens while transitioning into full screen mode the `NWWindowDelegate` method
  /// [windowDidFailToEnterFullScreen](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowdidfailtoenterfullscreen(_:))
  /// is called. When this happens the changes made by `windowWillEnterFullScreen` must be reverted.
  /// - Parameter window: The window that failed to enter to full screen mode.
  func windowDidFailToEnterFullScreen(_ window: NSWindow) {
    log("AppKit failed to enter full screen mode! Restoring previous windowed state", level: .warning)
    defer { finishFullscreenVideoTransition() }
    guard case .animating(let toFullscreen, let legacy, let priorWindowedFrame) = fsState,
            toFullscreen, !legacy else {
      // Must not occur! Represents an error in IINA or AppKit.
      log("Unable to restore windowed state: \(fsState)", level: .error)
      return
    }

    liveText.requestAnalysis()

    // Reset the full screen state to indicate exiting full screen mode so that finishAnimating
    // will correctly set the state to windowed.
    fsState = .animating(toFullscreen: false, legacy: legacy, priorWindowedFrame: priorWindowedFrame)
    fsState.finishAnimating()
    window.styleMask.insert(.fullSizeContentView)
    updateMinimumWindowSize()

    titleBarView.update(hasOSC: oscPosition == .top, inFullScreen: false)
    setWindowToolbar()
    fadeableViews.update()
    showUI()
    updateTimer()

    if player.info.state == .playing {
      setWindowFloatingOnTop(isOntop, updateOnTopStatus: false)
    }

    videoView.needsLayout = true
    videoView.layoutSubtreeIfNeeded()
    forceDraw("failed to enter full screen mode")
  }

  /// The window is about to exit full screen mode.
  ///
  /// The `NSWindowDelegate` method [windowWillExitFullScreen](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowwillexitfullscreen(_:))
  /// is called after the AppKit
  /// [toggleFullScreen](https://developer.apple.com/documentation/appkit/nswindow/togglefullscreen(_:))
  /// method has been called when the window is in full screen mode. Prepare the window to start transitioning to windowed mode.
  /// - Attention: After altering this method you _must_ update the
  ///     [windowDidFailToExitFullScreen](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowdidfailtoexitfullscreen(_:))
  ///     method which is responsible for reverting changes made by this method should the transition to windowed mode fail.
  /// - Parameter notification: A notification named
  ///     [willExitFullScreenNotification](https://developer.apple.com/documentation/appkit/nswindow/willexitfullscreennotification).
  func windowWillExitFullScreen(_ notification: Notification) {
    log("Exiting full screen mode")
    interruptPlayerCropTransition()
    if isCropTransitionInProgress { cancelCropExitTransition() }
    interactiveMode.exit()
    fsState.startAnimatingToWindow()
    // AppKit reuses the fullscreen titlebar surface while shrinking the window.
    window?.titlebarAppearsTransparent = true
    if notification.name != .iinaLegacyFullScreen { beginFullscreenVideoTransition() }
    // When playback is paused the display link is stopped in order to avoid wasting energy on
    // needless processing. It must be running while transitioning from full screen mode.
    videoView.displayActive()

    liveText.clearAnalysis()

    titleBarView.update(hasOSC: oscPosition == .top, inFullScreen: false)

    hideSeekPreview()
    additionalInfoView.isHidden = true

    window?.styleMask.insert(.fullSizeContentView)
    fadeableViews.update()
  }

  /// The window has left full screen mode.
  ///
  /// The `NSWindowDelegate` method
  /// [windowDidExitFullScreen](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowdidexitfullscreen(_:))
  /// is called after the transition to windowed mode initiated by calling
  /// [toggleFullScreen](https://developer.apple.com/documentation/appkit/nswindow/togglefullscreen(_:))
  /// completes. Finish configuring IINA for windowed mode.
  /// - Important: The following unexpected sequence of calls from AppKit has been encountered:
  ///     - windowWillExitFullScreen
  ///     - windowDidFailToExitFullScreen
  ///     - windowDidExitFullScreen
  ///
  ///     As this AppKit behavior is very hard to trigger it is not entirely clear why is happening. The working assumption is that this
  ///     occurs when the app starts to terminate after failing to exit full screen mode. See issue
  ///     [#5368](https://github.com/iina/iina/issues/5368) for more details.
  /// - Parameter notification: A notification named
  ///     [didExitFullScreenNotification](https://developer.apple.com/documentation/appkit/nswindow/didexitfullscreennotification).
  func windowDidExitFullScreen(_ notification: Notification) {
    log("Exited full screen mode")
    defer { finishFullscreenVideoTransition() }

    if fsState.isFullscreen {
      // IINA should not be in full screen mode at this point. The fsState should indicate IINA is
      // animating to the windowed state. This happens when AppKit calls windowDidExitFullScreen
      // after having called windowDidFailToExitFullScreen. As we think this is triggered when the
      // app starts terminating we only change fsState to indicate IINA was animating to windowed
      // mode. If this is not done the call to finishAnimating below will trigger a fatal error.
      log("AppKit exited full screen mode without informing IINA", level: .warning)
      fsState.startAnimatingToWindow()
    }

    liveText.requestAnalysis()

    if let frame = fsState.priorWindowedFrame, window?.frame != frame {
      // AppKit's fullscreen entry frame becomes stale after crop, track or media changes.
      window?.setFrame(frame, display: true, animate: false)
    }

    window?.titlebarAppearsTransparent = true

    fsState.finishAnimating()
    updateMinimumWindowSize()
    setWindowToolbar()
    fadeableViews.update()

    if Preference.bool(for: .blackOutMonitor) {
      removeBlackWindow()
    }

    if player.info.state == .paused {
      // When playback is paused the display link is stopped in order to avoid wasting energy on
      // needless processing. It must be running while transitioning from full screen mode. Now that
      // the transition has completed it can be stopped.
      videoView.displayIdle()
    }

    player.touchBarSupport.toggleTouchBarEsc(enteringFullScr: false)

    // Must not access mpv while it is asynchronously processing stop and quit commands.
    // See comments in windowWillExitFullScreen for details.
    guard player.info.state.active else { return }
    showUI()
    updateTimer()

    videoView.needsLayout = true
    videoView.layoutSubtreeIfNeeded()
    forceDraw("exited full screen mode")

    if Preference.bool(for: .pauseWhenLeavingFullScreen) && player.info.state == .playing {
      player.pause()
    }

    // restore ontop status
    if player.info.state == .playing {
      setWindowFloatingOnTop(isOntop, updateOnTopStatus: false)
    }

    resetCollectionBehavior()
    updateWindowParametersForMPV()

    player.events.emit(.windowFullscreenChanged, data: false)
    NotificationCenter.default.post(name: .iinaFullscreenChanged, object: nil, userInfo: ["enable": false])
  }

  /// Called if the window failed to exit full screen mode.
  ///
  /// The AppKit [toggleFullScreen](https://developer.apple.com/documentation/appkit/nswindow/togglefullscreen(_:))
  /// method can fail. If that happens while transitioning out of full screen mode the `NWWindowDelegate` method
  /// [windowDidFailToExitFullScreen](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowdidfailtoexitfullscreen(_:))
  /// is called. When this happens the changes made by `windowWillExitFullScreen` must be reverted.
  /// - Parameter window: The window that failed to exit to full screen mode.
  func windowDidFailToExitFullScreen(_ window: NSWindow) {
    log("AppKit failed to exit full screen mode! Restoring full screen state", level: .error)
    defer { finishFullscreenVideoTransition() }
    guard case .animating(let toFullscreen, let legacy, let priorWindowedFrame) = fsState,
            !toFullscreen, !legacy else {
      // Must not occur! Represents an error in IINA or AppKit.
      log("Unable to restore full screen state: \(fsState)", level: .error)
      return
    }

    liveText.requestAnalysis()

    // Reset the full screen state to indicate entering full screen mode so that finishAnimating
    // will correctly set the state to  full screen mode.
    fsState = .animating(toFullscreen: true, legacy: legacy, priorWindowedFrame: priorWindowedFrame)
    fsState.finishAnimating()

    window.styleMask.remove(.fullSizeContentView)
    window.titlebarAppearsTransparent = false
    titleBarView.update(hasOSC: oscPosition == .top, inFullScreen: true)
    setWindowToolbar()
    fadeableViews.update()
    showUI()
    updateTimer()

    additionalInfoView.update()

    videoView.needsLayout = true
    videoView.layoutSubtreeIfNeeded()
    forceDraw("failed to exit full screen mode")
  }

  func toggleWindowFullScreen() {
    guard let window = self.window else { fatalError("make sure the window exists before animating") }

    switch fsState {
    case .windowed:
      guard !player.isInMiniPlayer else { return }
      if Preference.bool(for: .useLegacyFullScreen) {
        log("Will enter legacy full screen mode")
        self.legacyAnimateToFullscreen()
      } else {
        log("Requesting AppKit enter full screen mode")
        window.toggleFullScreen(self)
      }
    case let .fullscreen(legacy, oldFrame):
      if legacy {
        log("Will exit legacy full screen mode")
        self.legacyAnimateToWindowed(framePriorToBeingInFullscreen: oldFrame)
      } else {
        log("Requesting AppKit exit full screen mode")
        window.toggleFullScreen(self)
      }
    case let .animating(toFullscreen, legacy, _):
      let legacyAppKit = legacy ? "IINA" : "AppKit"
      let enteringExiting = toFullscreen ? "entering" : "exiting"
      log("""
        \(legacyAppKit) is currently \(enteringExiting) full screen mode, \
        ignoring request to toggle full screen mode
        """)
    }
  }

  private func restoreDockSettings() {
    log("Restoring dock settings")
    NSApp.presentationOptions.remove(.autoHideMenuBar)
    NSApp.presentationOptions.remove(.autoHideDock)
  }

  private func legacyAnimateToWindowed(framePriorToBeingInFullscreen: NSRect) {
    guard let window = self.window else { fatalError("make sure the window exists before animating") }

    // call delegate
    windowWillExitFullScreen(Notification(name: .iinaLegacyFullScreen))
    // stylemask
    window.styleMask.remove(.borderless)
    window.styleMask.insert(.resizable)
    window.styleMask.insert(.titled)
    updateWindowButtonLayout()
    window.hasShadow = true
    (window as! MainWindow).forceKeyAndMain = false
    window.level = .normal

    restoreDockSettings()
    // restore window frame and aspect ratio
    let videoSize = player.videoSizeForDisplay
    let aspectRatio = NSSize(width: videoSize.0, height: videoSize.1)
    let useAnimation = {
      // Animation causes lagging under the macOS Tahoe beta, so don't allow it for now.
      guard #unavailable(macOS 26) else { return false }
      return !Preference.bool(for: .disableAnimations)
    }()
    if useAnimation {
      // firstly resize to a big frame with same aspect ratio for better visual experience
      let aspectFrame = aspectRatio.shrink(toSize: window.frame.size).centeredRect(in: window.frame)
      window.setFrame(aspectFrame, display: true, animate: false)
    }
    // then animate to the original frame
    window.setFrame(framePriorToBeingInFullscreen, display: true, animate: useAnimation)
    setWindowAspectRatio(aspectRatio)
    cameraHousingWindow?.orderOut(self)
    cameraHousingWindow = nil
    // call delegate
    windowDidExitFullScreen(Notification(name: .iinaLegacyFullScreen))
  }

  /// Set the window frame and if needed view frames to appropriately use the full screen.
  ///
  /// For screens that contain a camera housing views will be adjusted to not use that area of the screen.
  private func setWindowFrameForLegacyFullScreen() {
    guard let window,
          let screen = window.screen ?? NSScreen.main else {return }

    let unusable = screen.cameraHousingHeight ?? 0
    let frame = NSRect(
      x: screen.frame.minX,
      y: screen.frame.minY,
      width: screen.frame.width,
      height: screen.frame.height - unusable,
    )

    let useAnimation = {
      // Animation causes lagging under the macOS Tahoe beta, so don't allow it for now.
      guard #unavailable(macOS 26) else { return false }
      return !Preference.bool(for: .disableAnimations)
    }()

    window.setFrame(frame, display: true, animate: useAnimation)

    if unusable > 0 {
      // Force black background in camera housing. Cannot extend the window frame
      // to cover the area because window background is white in light theme.
      let housingWindow = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false, screen: screen)
      housingWindow.backgroundColor = .black
      // the level must be exactly .mainMenu, otherwise the main menu will not show
      housingWindow.level = .mainMenu
      let cameraRect = NSRect(
        x: screen.frame.minX,
        y: screen.frame.maxY - unusable,
        width: screen.frame.width,
        height: unusable
      )
      housingWindow.setFrame(cameraRect, display: false)
      housingWindow.orderFront(self)
      self.cameraHousingWindow = housingWindow
    }
  }

  private func legacyAnimateToFullscreen() {
    guard let window = self.window else { fatalError("make sure the window exists before animating") }
    // call delegate
    windowWillEnterFullScreen(Notification(name: .iinaLegacyFullScreen))
    // stylemask
    window.styleMask.insert(.borderless)
    window.styleMask.remove(.resizable)
    window.styleMask.remove(.titled)
    window.hasShadow = false
    (window as! MainWindow).forceKeyAndMain = true
    window.level = .floating

    // cancel aspect ratio
    window.resizeIncrements = NSSize(width: 1, height: 1)
    // auto hide menubar and dock
    NSApp.presentationOptions.insert(.autoHideMenuBar)
    NSApp.presentationOptions.insert(.autoHideDock)
    // set window frame and in some cases content view frame
    setWindowFrameForLegacyFullScreen()

    // The volume slider and the toolbar views in the floating OSC will be detached and not shown in
    // the floating OSC if the window is too narrow. Once in full screen mode there is enough space
    // for the full OSC to be shown. Sometimes, but not always, the subview holding the pause/resume
    // and left/right buttons will not be centered after the OSC expands to full size. Forcing
    // layout corrects this. See issue #5244.
    if oscPosition == .floating {
      oscPlayControlView.needsLayout = true
    }

    // call delegate
    windowDidEnterFullScreen(Notification(name: .iinaLegacyFullScreen))
  }

  // MARK: - Window delegate: Size

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    guard loaded, let window else { return frameSize }
    // Keep the grabbed edge tied to the pointer rather than AppKit's aspect-constrained proposal.
    let frameSize = if window.inLiveResize, !Preference.unlockWindowAspectRatio,
                       let session = windowResizeSession {
      session.size(at: NSEvent.mouseLocation, maximum: window.maxSize)
    } else {
      frameSize
    }
    // Rejected size proposals may not send windowDidResize; refresh the row here too.
    defer {
      if oscPosition == .floating, !isApplyingVideoTransformWindowFrame, !isFullscreenTransitionInProgress {
        invalidateFloatingOSCLayout()
        window.contentView?.layoutSubtreeIfNeeded()
      }
    }
    if !window.inLiveResize, !isCropTransitionInProgress, !isFullscreenTransitionInProgress {
      liveText.clearAnalysis()
    }
    if frameSize.height <= minimumWindowSize.height || frameSize.width <= minimumWindowSize.width {
      let frame = NSRect(origin: sender.frame.origin,
                         size: NSSize(width: max(frameSize.width, minimumWindowSize.width),
                                      height: max(frameSize.height, minimumWindowSize.height)))
      return windowFrameConstrainedToScreen(frame, screenFrame: sender.screen?.visibleFrame).size
    }
    return frameSize
  }

  func windowDidResize(_ notification: Notification) {
    updateWindowButtonLayout()
    guard loaded, let window else { return }
    if interactiveMode.isActive { interactiveMode.resize() }
    if !window.inLiveResize, !isApplyingVideoTransformWindowFrame, !isCropTransitionInProgress,
       !isFullscreenTransitionInProgress {
      liveText.requestAnalysis()
    }

    // update control bar position
    if oscPosition == .floating {
      if !isApplyingVideoTransformWindowFrame, !isFullscreenTransitionInProgress { invalidateFloatingOSCLayout() }
      // The crop tick positions the OSC after setFrame completes, then settles
      // its constraints together with the final video/container layout.
      if cropExitOverlay?.isTransforming != true || !isApplyingVideoTransformWindowFrame {
        oscFloatingView.updatePosition()
      }
    }

    player.events.emit(.windowResized, data: window.frame)
  }

  /// Native stack geometry can go stale even when scale and bounds are unchanged.
  private func invalidateFloatingOSCLayout() {
    floatingOSCControlsView?.needsLayout = true
    [oscFloatingView.oscTopView, oscPlayControlView, oscPlayControlMiddleView,
     oscToolbarView, oscVolumeView].forEach { view in
      view?.needsUpdateConstraints = true
      view?.needsLayout = true
    }
  }

  func finishPendingNativeCropFrame(_ overlay: CropTransitionOverlay) {
    guard overlay.isAwaitingNativeFrame, overlay.nativeFrameWasRendered, !player.isRefreshingPausedCrop else { return }
    overlay.isAwaitingNativeFrame = false
    let completion = overlay.pendingNativeFrameCompletion
    overlay.pendingNativeFrameCompletion = nil
    completion?()
  }

  func afterNativeCropFrame(_ overlay: CropTransitionOverlay, preparing: Bool = false,
                            outputIsReady: Bool = false, completion: @escaping () -> Void) {
    overlay.isAwaitingNativeFrame = true
    overlay.nativeFrameWasRendered = false
    overlay.pendingNativeFrameCompletion = completion
    // playback-restart has already delivered the refreshed frame, or the
    // unchanged source is still current. Do not wait for another decoded PTS.
    if outputIsReady {
      overlay.nativeFrameWasRendered = true
      finishPendingNativeCropFrame(overlay)
      return
    }
    let receive: (Bool) -> Void = { [weak self, weak overlay] ready in
      guard let self, let overlay else { return }
      guard overlay.pendingNativeFrameCompletion != nil else { return }
      guard player.info.state.active, player.info.trackSelectionGeneration == overlay.mediaGeneration else { return }
      guard ready else {
        if cropExitOverlay === overlay { cancelCropExitTransition() }
        else { interactiveMode.cancelEntryTransition() }
        return
      }
      overlay.nativeFrameWasRendered = true
      finishPendingNativeCropFrame(overlay)
    }
    if preparing { videoView.videoLayer.afterNextPreparedCropFrame(receive) }
    else { videoView.videoLayer.afterNextCropFrame(receive) }
    player.requestNativeCropFrame()
  }

  func bindCropVideo(_ overlay: CropTransitionOverlay, pixelSize: NSSize) {
    let constraints = videoViewConstraints.values.filter { $0.isActive }
    let translates = videoView.translatesAutoresizingMaskIntoConstraints
    let resizing = videoView.autoresizingMask
    overlay.useNativeVideo(videoView, in: videoViewContainer, pixelSize: pixelSize,
      beginLayout: { [weak self] in
        guard let self else { return }
        NSLayoutConstraint.deactivate(constraints)
        videoView.translatesAutoresizingMaskIntoConstraints = true
        videoView.autoresizingMask = []
      }, restoreLayout: { [weak self] in
        guard let self else { return }
        videoView.translatesAutoresizingMaskIntoConstraints = translates
        videoView.autoresizingMask = resizing
        NSLayoutConstraint.activate(constraints)
        videoViewContainer.layoutSubtreeIfNeeded()
      })
  }

  func deferCropVideoRestoration(transform: CATransform3D, mask: CALayer?) -> Bool {
    guard let nativeVideo = cropExitOverlay?.nativeVideo else { return false }
    nativeVideo.setRestoration(transform: transform, mask: mask)
    return true
  }

  @discardableResult
  func prepareCropChange(_ apply: @escaping () -> Void, selection: NSRect,
                         displaySize: NSSize, filterRect: NSRect) -> Bool {
    cancelVideoGeometryTransition()
    if isPlayerCropTransitionInProgress {
      // Finish the current native handoff, then use only the latest selection.
      pendingPlayerCropChange = { [weak self] in
        guard let self else { return }
        if !prepareCropChange(apply, selection: selection, displaySize: displaySize, filterRect: filterRect) { apply() }
      }
      return true
    }
    guard loaded, let window, window.isVisible, !videoViewContainer.bounds.isEmpty,
          !selection.isEmpty, displaySize.width > 0, displaySize.height > 0, !filterRect.isEmpty,
          player.info.state.active, !player.info.justStartedFile,
          fsState == .windowed, pipStatus == .notInPIP,
          !interactiveMode.isActive, !isCropTransitionInProgress,
          cropTransitionDuration(0.35) > 0,
          let frame = player.cropTransitionFrame(in: videoViewContainer.bounds) else { return false }
    let geometry = player.interactiveVideoGeometry(uncropped: true)
    let overlay = CropTransitionOverlay(frame: videoViewContainer.bounds)
    overlay.isPlayerTransition = true
    overlay.wasAnimatingWindowResize = videoView.videoLayer.isAnimatingWindowResize
    videoView.videoLayer.isInCropTransition = true
    videoView.videoLayer.isAnimatingWindowResize = true
    videoView.videoLayer.setCropFramePreparation(true)
    overlay.mediaGeneration = player.info.trackSelectionGeneration
    overlay.showPlayerFrame(frame: frame)
    overlay.targetSelection = selection
    overlay.targetDisplaySize = displaySize
    overlay.targetFilterRect = filterRect
    overlay.expectedSourceSize = geometry.sourceSize
    overlay.sourceVideoSize = geometry.displaySize
    overlay.applyCrop = apply
    overlay.isPreparingSource = true
    overlay.waitsForOutput = player.info.cropFilter != nil
    cropExitOverlay = overlay
    videoViewContainer.addSubview(overlay, positioned: .above, relativeTo: nil)
    overlay.beginPreparationFeedback(pulse: !AccessibilityPreferences.motionReductionEnabled)
    bindCropVideo(overlay, pixelSize: geometry.selectionSize)
    if player.info.cropFilter != nil {
      videoView.videoLayer.setCropFramePreparation(true)
      player.removeCropFilter()
      guard player.info.cropFilter == nil else { cancelCropExitTransition(); return true }
    }
    overlay.isPreparing = false
    finishCropExitTransition()
    return true
  }

  func prepareCropExit(selection: NSRect, sourceSize: NSSize, initialFrame: NSRect,
                       initialClip: NSRect, initialSelection: NSRect,
                       controlsImage: NSImage?, controlsFrame: NSRect,
                       completion: @escaping () -> Bool) {
    guard player.canAnimateCropSource else { _ = completion(); return }
    guard cropExitOverlay == nil, !selection.isEmpty, !initialFrame.isEmpty,
          sourceSize.width > 0, sourceSize.height > 0 else { return }
    let geometry = player.interactiveVideoGeometry(uncropped: true)
    let overlay = CropTransitionOverlay(frame: videoViewContainer.bounds)
    overlay.wasAnimatingWindowResize = videoView.videoLayer.isAnimatingWindowResize
    videoView.videoLayer.isInCropTransition = true
    videoView.videoLayer.isAnimatingWindowResize = true
    overlay.mediaGeneration = player.info.trackSelectionGeneration
    overlay.targetDisplaySize = NSSize(width: geometry.displaySize.width * selection.width / sourceSize.width,
                                      height: geometry.displaySize.height * selection.height / sourceSize.height)
    let filterRect = geometry.filterRect(for: selection)
    overlay.targetFilterRect = NSRect(x: Int(filterRect.minX), y: Int(filterRect.minY),
                                     width: Int(filterRect.width), height: Int(filterRect.height))
    overlay.expectedSourceSize = geometry.sourceSize
    overlay.sourceVideoSize = geometry.displaySize
    overlay.applyCrop = { [weak self] in
      if !completion() { self?.cancelCropExitTransition() }
    }
    cropExitOverlay = overlay
    bindCropVideo(overlay, pixelSize: geometry.selectionSize)
    videoView.videoLayer.withCropFrameHandoff {
      videoViewContainer.addSubview(overlay, positioned: .above, relativeTo: nil)
      overlay.beginPreparationFeedback(pulse: !AccessibilityPreferences.motionReductionEnabled)
      // Keep the unfiltered live source until the visual aperture reaches its
      // destination. Canonical crop installation happens after that motion.
      interactiveMode.beginNativeExitPresentation()
      videoViewContainer.layoutSubtreeIfNeeded()
      overlay.show(selection: selection, sourceSize: sourceSize, initialFrame: initialFrame,
                   initialClip: initialClip, initialSelection: initialSelection,
                   controlsImage: controlsImage, controlsFrame: controlsFrame)
      overlay.nativeVideo?.present(frame: initialFrame, clip: initialClip)
    }
    hideOSD()
    overlay.isPreparing = false
    finishCropExitTransition()
  }

  func cropTransitionDuration(_ duration: TimeInterval) -> TimeInterval {
    player.disableWindowAnimation || Preference.bool(for: .disableAnimations) || AccessibilityPreferences.motionReductionEnabled
      ? 0 : AccessibilityPreferences.adjustedDuration(duration)
  }

  func finishCropExitTransition(outputIsReady: Bool = false) {
    interactiveMode.finishEntryTransition(outputIsReady: outputIsReady)
    guard let overlay = cropExitOverlay, !overlay.isPreparing else { return }
    guard player.info.state.active,
          player.info.trackSelectionGeneration == overlay.mediaGeneration else { cancelCropExitTransition(); return }
    if overlay.isAwaitingNativeFrame {
      if outputIsReady { overlay.nativeFrameWasRendered = true }
      finishPendingNativeCropFrame(overlay)
      return
    }
    let actual = NSSize(width: player.mpv.getInt(MPVProperty.videoOutParams + "/w"),
                        height: player.mpv.getInt(MPVProperty.videoOutParams + "/h"))
    guard !player.isRefreshingPausedCrop else { return }
    if overlay.isCommitting {
      guard !overlay.isAwaitingNativeFrame, actual == overlay.targetFilterRect.size else { return }
      // None leaves the full source in place; no filter mutation will produce
      // another playback-restart or native frame while paused.
      afterNativeCropFrame(overlay, preparing: true,
                           outputIsReady: outputIsReady || player.info.cropFilter == nil) { [weak self, weak overlay] in
        guard let self, let overlay, cropExitOverlay === overlay else { return }
        videoView.videoLayer.withCropFrameHandoff {
          overlay.releaseNativeVideo()
        }
        let pending = pendingPlayerCropChange
        pendingPlayerCropChange = nil
        updateWindowParametersForMPV()
        cancelCropExitTransition()
        if player.info.state == .paused { liveText.requestAnalysis() }
        pending?()
      }
      return
    }
    guard !overlay.isFinishing else { return }
    if overlay.isPreparingSource {
      guard actual == overlay.expectedSourceSize else { return }
      overlay.isPreparingSource = false
    }
    overlay.isFinishing = true
    handleVideoSizeChange(keepWindowSize: true)
    guard let target = overlay.targetWindowFrame, let window else { cancelCropExitTransition(); return }
    let bounds = NSRect(origin: .zero, size: NSSize(
      width: overlay.bounds.width + target.width - window.frame.width,
      height: overlay.bounds.height + target.height - window.frame.height))
    overlay.hasRenderedVideo = true
    if overlay.isPlayerTransition {
      overlay.setPlayerTargetFrame(.init(selection: overlay.targetSelection,
        videoRect: CropTransitionOverlay.fit(overlay.targetDisplaySize, in: bounds), viewport: bounds), present: false)
    }
    afterNativeCropFrame(overlay, preparing: overlay.isPlayerTransition,
                         outputIsReady: outputIsReady || !overlay.waitsForOutput) { [weak self, weak overlay] in
      guard let self, let overlay, cropExitOverlay === overlay else { return }
      videoView.videoLayer.withCropFrameHandoff {
        if overlay.isPlayerTransition {
          overlay.presentPlayerTransition(progress: 0)
        } else {
          let selectionSize = NSSize(width: overlay.imageFrame.width * overlay.selection.width / overlay.sourceSize.width,
                                     height: overlay.imageFrame.height * overlay.selection.height / overlay.sourceSize.height)
          let clip = CropTransitionOverlay.fit(selectionSize, in: bounds)
          overlay.nativeVideo?.prepareRaster(for: [overlay.imageFrame, overlay.transformedImage(fitting: clip)])
        }
      }
      startCropExitAnimation()
    }
  }

  private func startCropExitAnimation() {
    guard let overlay = cropExitOverlay, let window, !overlay.isPreparing,
          overlay.hasRenderedVideo, !overlay.isTransforming,
          let target = overlay.targetWindowFrame else { return }
    if overlay.isShowingPreparationFeedback {
      overlay.finishPreparationFeedback { [weak self, weak overlay] in
        guard let self, let overlay, cropExitOverlay === overlay else { return }
        startCropExitAnimation()
      }
      return
    }
    overlay.isTransforming = true
    let initialWindow = window.frame
    let initialImage = overlay.imageFrame
    let finalBounds = NSRect(origin: .zero, size: NSSize(
      width: overlay.bounds.width + target.width - initialWindow.width,
      height: overlay.bounds.height + target.height - initialWindow.height))
    let selectionSize = overlay.isPlayerTransition ? finalBounds.size : NSSize(
      width: initialImage.width * overlay.selection.width / overlay.sourceSize.width,
      height: initialImage.height * overlay.selection.height / overlay.sourceSize.height)
    let finalClip = CropTransitionOverlay.fit(selectionSize, in: finalBounds)
    let letterboxed = !finalClip.insetBy(dx: -1, dy: -1).contains(finalBounds)
    overlay.animate(duration: cropTransitionDuration(overlay.isPlayerTransition ? 0.4 : 0.35),
                    curve: overlay.isPlayerTransition ? .smoothstep : .easeOut,
                    update: { [weak self, weak overlay] progress in
      guard let self, let overlay, cropExitOverlay === overlay else { return }
      let nextFrame = CropTransitionOverlay.interpolate(initialWindow, target, progress)
      let wasApplying = self.isApplyingVideoTransformWindowFrame
      self.isApplyingVideoTransformWindowFrame = true
      if oscPosition == .floating, let contentView = window.contentView {
        oscFloatingView.prepareForResize(to: NSSize(
          width: contentView.bounds.width + nextFrame.width - window.frame.width,
          height: contentView.bounds.height + nextFrame.height - window.frame.height))
      }
      window.setFrame(nextFrame, display: true)
      self.isApplyingVideoTransformWindowFrame = wasApplying
      if oscPosition == .floating {
        oscFloatingView.updatePosition(deferringFinalLayout: true, afterPreparedResize: true)
      }
      window.contentView?.layoutSubtreeIfNeeded()
      if overlay.isPlayerTransition {
        overlay.presentPlayerTransition(progress: progress)
      } else {
        overlay.presentTransition(to: finalClip, progress: progress, letterboxed: letterboxed)
      }
    }) { [weak self, weak overlay] in
      guard let self, let overlay, cropExitOverlay === overlay else { return }
      finishVideoAspectTransition()
      if oscPosition == .floating {
        invalidateFloatingOSCLayout()
        oscFloatingView.updatePosition()
      }
      overlay.isCommitting = true
      videoView.videoLayer.setCropFramePreparation(true)
      let apply = overlay.applyCrop
      overlay.applyCrop = nil
      apply?()
      finishCropExitTransition()

    }
  }

  func interruptPlayerCropTransition(settleWindowFrame: Bool = true) {
    cancelVideoGeometryTransition(settleWindowFrame: settleWindowFrame)
    guard let overlay = cropExitOverlay, overlay.isPlayerTransition else { return }
    cancelCropExitTransition()
    guard player.info.state.active, player.info.trackSelectionGeneration == overlay.mediaGeneration else { return }
    if settleWindowFrame, let target = overlay.targetWindowFrame, let window, fsState == .windowed {
      let wasApplying = isApplyingVideoTransformWindowFrame
      isApplyingVideoTransformWindowFrame = true
      window.setFrame(target, display: true)
      isApplyingVideoTransformWindowFrame = wasApplying
      updateWindowParametersForMPV(withFrame: target)
    }
  }

  func cancelCropExitTransition() {
    cancelVideoGeometryTransition()
    interactiveMode.cancelEntryTransition()
    let overlay = cropExitOverlay
    overlay?.stopAnimation()
    overlay?.endPreparationFeedback(animated: false)
    overlay?.pendingNativeFrameCompletion = nil
    videoView.videoLayer.cancelCropFrameRequests()
    pendingPlayerCropChange = nil
    if let overlay, player.info.state.active,
       overlay.mediaGeneration == player.info.trackSelectionGeneration {
      let apply = overlay.applyCrop
      overlay.applyCrop = nil
      apply?()
    }
    overlay?.releaseNativeVideo()
    if overlay != nil { videoView.videoLayer.setCropFramePreparation(false) }
    overlay?.removeFromSuperview()
    cropExitOverlay = nil
    if let overlay {
      videoView.videoLayer.isAnimatingWindowResize = overlay.wasAnimatingWindowResize
      videoView.videoLayer.isInCropTransition = false
    }
    interactiveMode.restoreExitPresentation()
  }

  /// Explicit aspect/rotation requests share Crop's native surface and motion clock.
  func enqueueVideoGeometryChange(_ kind: VideoGeometryChange, request: @escaping () -> Void) -> Bool {
    guard geometryMotion != nil else { return false }
    pendingGeometryChanges[kind] = request
    return true
  }

  func performVideoGeometryChange(_ kind: VideoGeometryChange, apply: @escaping () -> Bool) {
    if geometryMotion != nil {
      pendingGeometryChanges[kind] = { [weak self] in self?.performVideoGeometryChange(kind, apply: apply) }
      return
    }
    interruptPlayerCropTransition()
    finishVideoAspectTransition()
    guard loaded, player.info.state.loaded else { _ = apply(); return }
    let geometry = player.interactiveVideoGeometry(uncropped: false)
    guard geometry.sourceSize.width > 0, geometry.sourceSize.height > 0 else { _ = apply(); return }
    let viewport = videoViewContainer?.bounds ?? .zero
    let canAnimate = loaded && window?.isVisible == true && player.info.state.loaded
      && !player.info.justStartedFile && fsState == .windowed && pipStatus == .notInPIP
      && !interactiveMode.isActive && cropExitOverlay == nil && !viewport.isEmpty
      && geometry.displaySize.width > 0 && geometry.displaySize.height > 0
      && [0, 90, 180, 270].contains(geometry.rotation) && player.canAnimateVideoGeometry
      && [MPVOption.Video.videoZoom, MPVOption.Video.videoPanX, MPVOption.Video.videoPanY,
          MPVOption.Video.panscan].allSatisfy { abs(player.mpv.getDouble($0)) < 0.000001 }
      && cropTransitionDuration(0.4) > 0
    let overlay = canAnimate ? CropTransitionOverlay(frame: viewport) : nil
    let motion = GeometryMotion(generation: player.info.trackSelectionGeneration,
      osdToken: player.beginVideoGeometryOSDRefresh(),
      oldVisibleRect: geometry.displaySize.width > 0 && geometry.displaySize.height > 0
        ? CropTransitionOverlay.fit(geometry.displaySize, in: viewport) : viewport,
      oldRotation: geometry.rotation, overlay: overlay,
      wasAnimating: videoView.videoLayer.isAnimatingWindowResize)
    geometryMotion = motion
    if let overlay {
      videoView.displayActive()
      videoView.videoLayer.isInCropTransition = true
      videoView.videoLayer.isAnimatingWindowResize = true
      videoView.videoLayer.setCropFramePreparation(true)
      videoViewContainer.addSubview(overlay, positioned: .above, relativeTo: nil)
      overlay.beginPreparationFeedback(pulse: !AccessibilityPreferences.motionReductionEnabled)
    }
    guard apply() else { cancelVideoGeometryTransition(); return }
    // Option writes commit synchronously; decoder metadata may still describe
    // the old frame. Derive the requested signature without accepting that frame.
    motion.expectedRotation = (player.defaultVideoRotation + player.mpv.getInt(MPVOption.Video.videoRotate) + 360) % 360
    let ratio = player.mpv.getDouble(MPVOption.Video.videoAspectOverride)
    let width = player.mpv.getInt(MPVProperty.videoParams + "/w")
    let height = player.mpv.getInt(MPVProperty.videoParams + "/h")
    motion.expectedPAR = ratio > 0 && width > 0 && height > 0
      ? ratio * Double(height) / Double(width) : player.defaultVideoPixelAspect
    geometryVideoOutputDidChange(fromOutputEvent: false)
  }

  func geometryVideoOutputDidChange(outputIsReady: Bool = false, fromOutputEvent: Bool = true) {
    guard let motion = geometryMotion, !motion.animating else { return }
    guard player.info.state.loaded, motion.generation == player.info.trackSelectionGeneration else {
      cancelVideoGeometryTransition(settleWindowFrame: false); return
    }
    motion.outputIsReady = motion.outputIsReady || outputIsReady
    if motion.waitingForFrame {
      // A paused refresh may have been consumed before its waiter was installed.
      // Playback-restart confirms that mpv now owns the refreshed current frame.
      if motion.outputIsReady { motion.pendingFrame?(true) }
      return
    }
    let geometry = player.interactiveVideoGeometry(uncropped: false)
    let par = player.mpv.getDouble(MPVProperty.videoOutParams + "/par")
    let matchesOutput = geometry.rotation == motion.expectedRotation && abs(par - motion.expectedPAR) < 0.00001
    // Arbitrary filter graphs can replace PAR/rotation. They retain the normal
    // reconfiguration path rather than waiting for a decoder signature they do not expose.
    guard geometry.sourceSize.width > 0, geometry.sourceSize.height > 0,
          matchesOutput || motion.overlay == nil && fromOutputEvent else { return }
    motion.targetDisplaySize = geometry.displaySize
    motion.waitingForFrame = true
    // Calculate exactly the same reference-scale/minimum/screen target as Crop.
    handleVideoSizeChange(keepWindowSize: true)
    guard let overlay = motion.overlay else {
      finishVideoGeometryTransition(motion, runPending: true)
      return
    }
    let receive: (Bool) -> Void = { [weak self, weak motion] ready in
      guard let self, let motion, geometryMotion === motion, motion.pendingFrame != nil else { return }
      motion.pendingFrame = nil
      guard ready, player.info.state.loaded,
            motion.generation == player.info.trackSelectionGeneration else {
        cancelVideoGeometryTransition(settleWindowFrame: false); return
      }
      let delta = VideoGeometryTransition.shortestQuarterTurnDelta(from: motion.oldRotation, to: geometry.rotation)
      let compensation = CGFloat(delta) * .pi / 180
      let initial = VideoGeometryTransition.startFrame(oldVisibleRect: motion.oldVisibleRect, quarterTurnDelta: delta)
      videoView.videoLayer.withCropFrameHandoff {
        self.bindCropVideo(overlay, pixelSize: geometry.selectionSize)
        // Allocate at the new raster's true aspect, then compensate its live
        // pixels back to the previous appearance before publishing this draw.
        overlay.nativeVideo?.present(frame: CropTransitionOverlay.fit(geometry.displaySize, in: self.videoViewContainer.bounds),
                                     clip: self.videoViewContainer.bounds)
        overlay.nativeVideo?.present(frame: initial, clip: self.videoViewContainer.bounds, rotation: compensation)
      }
      overlay.finishPreparationFeedback { [weak self, weak motion] in
        guard let self, let motion, geometryMotion === motion else { return }
        startVideoGeometryAnimation(motion, initial: initial, compensation: compensation)
      }
    }
    motion.pendingFrame = receive
    if motion.outputIsReady { receive(true) }
    else {
      videoView.videoLayer.afterNextPreparedCropFrame(receive)
      player.requestNativeCropFrame()
    }
  }

  private func startVideoGeometryAnimation(_ motion: GeometryMotion, initial: NSRect, compensation: CGFloat) {
    guard geometryMotion === motion, let overlay = motion.overlay,
          let target = motion.targetWindowFrame, let window,
          let display = motion.targetDisplaySize else { return }
    motion.animating = true
    let initialWindow = window.frame
    let finalViewport = NSRect(origin: .zero, size: NSSize(
      width: overlay.bounds.width + target.width - initialWindow.width,
      height: overlay.bounds.height + target.height - initialWindow.height))
    let finalImage = CropTransitionOverlay.fit(display, in: finalViewport)
    overlay.animate(duration: cropTransitionDuration(0.4), curve: .smoothstep, startOnFirstTick: true,
                    update: { [weak self, weak motion] progress in
      guard let self, let motion, geometryMotion === motion else { return }
      let next = CropTransitionOverlay.interpolate(initialWindow, target, progress)
      let wasApplying = isApplyingVideoTransformWindowFrame
      isApplyingVideoTransformWindowFrame = true
      if oscPosition == .floating, let content = window.contentView {
        oscFloatingView.prepareForResize(to: NSSize(width: content.bounds.width + next.width - window.frame.width,
                                                   height: content.bounds.height + next.height - window.frame.height))
      }
      window.setFrame(next, display: true)
      isApplyingVideoTransformWindowFrame = wasApplying
      if oscPosition == .floating { oscFloatingView.updatePosition(deferringFinalLayout: true, afterPreparedResize: true) }
      window.contentView?.layoutSubtreeIfNeeded()
      let sample = VideoGeometryTransition.sample(from: initial, to: finalImage, viewport: videoViewContainer.bounds,
                                                 progress: progress, initialRotation: compensation)
      overlay.nativeVideo?.present(frame: sample.frame, clip: videoViewContainer.bounds, rotation: sample.rotation)
    }) { [weak self, weak motion] in
      guard let self, let motion, geometryMotion === motion else { return }
      finishVideoGeometryTransition(motion, runPending: true)
    }
  }

  func cancelVideoGeometryTransition(settleWindowFrame: Bool = true) {
    pendingGeometryChanges.removeAll()
    guard let motion = geometryMotion else { return }
    finishVideoGeometryTransition(motion, runPending: false, settleWindowFrame: settleWindowFrame)
  }

  private func finishVideoGeometryTransition(_ motion: GeometryMotion, runPending: Bool,
                                            settleWindowFrame: Bool = true) {
    guard geometryMotion === motion else { return }
    motion.overlay?.stopAnimation()
    motion.overlay?.endPreparationFeedback(animated: false)
    let wasApplying = isApplyingVideoTransformWindowFrame
    isApplyingVideoTransformWindowFrame = true
    if settleWindowFrame, fsState == .windowed, let target = motion.targetWindowFrame {
      window?.setFrame(target, display: true)
    }
    if let overlay = motion.overlay {
      videoView.videoLayer.cancelCropFrameRequests()
      videoView.videoLayer.withCropFrameHandoff { overlay.releaseNativeVideo() }
      videoView.videoLayer.setCropFramePreparation(false)
      overlay.removeFromSuperview()
      videoView.videoLayer.isAnimatingWindowResize = motion.wasAnimating
      videoView.videoLayer.isInCropTransition = false
    }
    geometryMotion = nil
    isApplyingVideoTransformWindowFrame = wasApplying
    player.endVideoGeometryOSDRefresh(motion.osdToken)
    if player.info.state.loaded, motion.generation == player.info.trackSelectionGeneration {
      updateWindowParametersForMPV()
      if oscPosition == .floating { invalidateFloatingOSCLayout(); oscFloatingView.updatePosition() }
      if player.info.state == .paused { videoView.displayIdle(); liveText.requestAnalysis() }
    }
    let pending = pendingGeometryChanges
    pendingGeometryChanges.removeAll()
    if runPending { for kind in [VideoGeometryChange.aspect, .rotation] { pending[kind]?() } }
  }

  /// File-local panscan lets stop/unload clean up an unfinished aspect transition.
  @discardableResult
  func beginVideoAspectTransition() -> Bool {
    guard videoAspectTransition == nil, loaded, let window, window.isVisible,
          player.info.state.active, !player.info.justStartedFile,
          !Preference.unlockWindowAspectRatio, fsState == .windowed,
          pipStatus == .notInPIP, !interactiveMode.isActive, !isCropTransitionInProgress,
          !player.disableWindowAnimation, !Preference.bool(for: .disableAnimations) else { return false }
    let original = player.mpv.getDouble(MPVOption.Video.panscan)
    guard player.mpv.setString("file-local-options/panscan", "1") >= 0 else { return false }
    videoAspectTransition = (original, player.info.trackSelectionGeneration)
    videoView.displayActive()
    return true
  }

  func finishVideoAspectTransition(restore: Bool = true) {
    guard let transition = videoAspectTransition else { return }
    videoAspectTransition = nil
    guard restore, player.info.state.active,
          transition.mediaGeneration == player.info.trackSelectionGeneration else { return }
    // A plugin/user change made during the transition belongs to that caller.
    if player.mpv.getDouble(MPVOption.Video.panscan) == 1 {
      player.mpv.setString("file-local-options/panscan", String(transition.panscan))
      videoView.videoLayer.update(force: true)
    }
    if player.mpv.getFlag(MPVOption.PlaybackControl.pause) { videoView.displayIdle() }
  }

  func resetWindowSizingForNewSession() {
    // Idle player cores retain their window controller after a window closes.
    shouldApplyInitialWindowSize = true
    cachedGeometry = nil
    videoTransformWindowReferenceSize = nil
    videoTransformWindowSize = nil
    videoTransformWindowDisplaySize = nil
    videoTransformWindowGeneration = nil
    windowSizingFileGeneration = nil
  }

  /// The explicit restart handoff overrides initial-size preferences once and
  /// establishes the same geometry reference as the restored visible window.
  func applyRestartWindowFrame(_ frame: NSRect) {
    guard let window, frame.width > 0, frame.height > 0 else { return }
    shouldApplyInitialWindowSize = false
    windowSizingFileGeneration = player.info.trackSelectionGeneration
    window.setFrame(frame, display: false, animate: false)
    let size = player.videoSizeForDisplay
    establishVideoTransformWindowReference(windowSize: frame.size,
                                          displaySize: NSSize(width: size.0, height: size.1), initial: true)
    videoTransformWindowDisplaySize = NSSize(width: size.0, height: size.1)
    setWindowAspectRatio(frame.size)
    updateWindowParametersForMPV(withFrame: frame)
  }

  private func establishVideoTransformWindowReference(windowSize: NSSize, displaySize: NSSize,
                                                       initial: Bool = false) {
    let generation = player.info.trackSelectionGeneration
    guard initial || videoTransformWindowGeneration != generation else { return }
    if initial || videoTransformWindowGeneration == nil {
      let source = player.interactiveVideoGeometry(uncropped: true).displaySize
      if source.width > 0, source.height > 0, displaySize.width > 0, displaySize.height > 0,
         abs(source.aspect - displaySize.aspect) > 0.000001 {
        // An already cropped file has no uncropped window to sample; recover its limiting axis from source geometry.
        videoTransformWindowReferenceSize = source.grow(toSize: displaySize.shrink(toSize: windowSize))
      } else {
        videoTransformWindowReferenceSize = windowSize
      }
    }
    videoTransformWindowGeneration = generation
    videoTransformWindowDisplaySize = nil
    videoTransformWindowSize = windowSize
  }

  private func updateVideoTransformWindowReference(to size: NSSize) {
    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
    if let reference = videoTransformWindowReferenceSize, let previous = videoTransformWindowSize {
      if abs(previous.width - size.width) > 2 || abs(previous.height - size.height) > 2 {
        // Padding is a window constraint, not part of the user's video scale.
        // Once a live resize removes it, Reset must retain the image's new scale.
        let display = interactiveMode.isActive ? nil : videoTransformWindowDisplaySize
        let before = display?.shrink(toSize: previous) ?? previous
        let after = display?.shrink(toSize: size) ?? size
        let scale = min(after.width / before.width, after.height / before.height)
        videoTransformWindowReferenceSize = reference.multiply(scale)
      }
    } else {
      videoTransformWindowReferenceSize = size
    }
    videoTransformWindowSize = size
  }

  private func rememberVideoTransformWindowResize() {
    prepareVideoTransformWindowReference()
  }

  func prepareVideoTransformWindowReference() {
    guard !isApplyingVideoTransformWindowFrame, !isCropTransitionInProgress,
          loaded, player.info.state.active, !shouldApplyInitialWindowSize,
          fsState == .windowed, pipStatus == .notInPIP, let window else { return }
    if !interactiveMode.isActive {
      let (width, height) = player.videoSizeForDisplay
      establishVideoTransformWindowReference(windowSize: window.frame.size,
                                             displaySize: NSSize(width: width, height: height))
    }
    guard videoTransformWindowReferenceSize != nil else { return }
    updateVideoTransformWindowReference(to: window.frame.size)
  }

  func windowWillStartLiveResize(_ notification: Notification) {
    if !isApplyingVideoTransformWindowFrame { interruptPlayerCropTransition(settleWindowFrame: false) }
    if !isApplyingVideoTransformWindowFrame { finishVideoAspectTransition() }
    rememberVideoTransformWindowResize()
    windowResizeSession = nil
    if !isApplyingVideoTransformWindowFrame, !isCropTransitionInProgress, loaded, let window, fsState == .windowed,
       !Preference.unlockWindowAspectRatio, !window.resizeFlags.contains(.option) {
      let aspect = interactiveMode.isActive ? currentWindowAspectRatio
        : videoTransformWindowDisplaySize ?? currentWindowAspectRatio
      windowResizeSession = WindowResizeSession(frame: window.frame, mouse: NSEvent.mouseLocation,
                                               aspectRatio: aspect)
      // The pointer session owns proportions; AppKit's aspect/minimum coupling would grow the other axis.
      if windowResizeSession != nil { window.aspectRatio = .zero }
    }
    videoView.videoLayer.inLiveResize = true
    liveText.clearAnalysis()
  }

  // resize framebuffer in videoView after resizing.
  func windowDidEndLiveResize(_ notification: Notification) {
    if windowResizeSession != nil, let window {
      setWindowAspectRatio(window.frame.size)
    }
    windowResizeSession = nil
    rememberVideoTransformWindowResize()
    if loaded, oscPosition == .floating {
      invalidateFloatingOSCLayout()
      oscFloatingView.updatePosition()
      window?.contentView?.layoutSubtreeIfNeeded()
    }
    // Must not access mpv while it is asynchronously processing stop and quit commands.
    // See comments in windowWillExitFullScreen for details.
    guard player.info.state.active else { return }
    videoView.videoLayer.inLiveResize = false
    updateWindowParametersForMPV()
    liveText.requestAnalysis()
  }

  func windowDidChangeBackingProperties(_ notification: Notification) {
    if let oldScale = (notification.userInfo?[NSWindow.oldScaleFactorUserInfoKey] as? NSNumber)?.doubleValue,
      oldScale != Double(window!.backingScaleFactor) {
      // The active owner holds a fixed raster density for one screen. Settle
      // its projection before transferring density to a different display.
      if isCropTransitionInProgress { cancelCropExitTransition() }
      videoView.videoLayer.contentsScale = window!.backingScaleFactor
    }
  }

  override func windowDidChangeScreen(_ notification: Notification) {
    super.windowDidChangeScreen(notification)

    player.events.emit(.windowScreenChanged)
  }

  // MARK: - Window delegate: Activeness status
  func windowDidMove(_ notification: Notification) {
    guard loaded, let window else { return }
    player.events.emit(.windowMoved, data: window.frame)
  }

  func windowDidBecomeKey(_ notification: Notification) {
    updateWindowButtonLayout()
    // Reapply this window session's placement after startup/media geometry settles.
    if loaded, oscPosition == .floating {
      oscFloatingView.updatePosition()
    }
    window!.makeFirstResponder(window!)
    if Preference.bool(for: .pauseWhenInactive) && isPausedDueToInactive {
      player.resume()
      isPausedDueToInactive = false
    }
  }

  func windowDidResignKey(_ notification: Notification) {
    cancelWindowDrag()
    // keyWindow is nil: The whole app is inactive
    // keyWindow is another MainWindow: Switched to another video window
    if NSApp.keyWindow == nil ||
      (NSApp.keyWindow?.windowController is MainWindowController ||
        (NSApp.keyWindow?.windowController is MiniPlayerWindowController && NSApp.keyWindow?.windowController != player.miniPlayer)) {
      if Preference.bool(for: .pauseWhenInactive), player.info.state == .playing {
        player.pause()
        isPausedDueToInactive = true
      }
    }
  }

  override func windowDidBecomeMain(_ notification: Notification) {
    super.windowDidBecomeMain(notification)

    if fsState.isFullscreen && Preference.bool(for: .blackOutMonitor) {
      blackOutOtherMonitors()
    }
    player.events.emit(.windowMainStatusChanged, data: true)
  }

  override func windowDidResignMain(_ notification: Notification) {
    super.windowDidResignMain(notification)
    if Preference.bool(for: .blackOutMonitor) {
      removeBlackWindow()
    }
    player.events.emit(.windowMainStatusChanged, data: false)
  }

  func windowWillMiniaturize(_ notification: Notification) {
    if Preference.bool(for: .pauseWhenMinimized), player.info.state == .playing {
      isPausedDueToMiniaturization = true
      player.pause()
    }
  }

  func windowDidMiniaturize(_ notification: Notification) {
    if Preference.bool(for: .togglePipByMinimizingWindow) && (!Preference.bool(for: .togglePipByMinimizingWindowForVideoOnly) ||  player.info.isAudio == .notAudio) && !isWindowMiniaturizedDueToPip {
      enterPIP()
    }
    player.events.emit(.windowMiniaturized)
  }

  func windowDidDeminiaturize(_ notification: Notification) {
    if Preference.bool(for: .pauseWhenMinimized) && isPausedDueToMiniaturization {
      player.resume()
      isPausedDueToMiniaturization = false
    }
    if Preference.bool(for: .togglePipByMinimizingWindow) && (!Preference.bool(for: .togglePipByMinimizingWindowForVideoOnly) ||  player.info.isAudio == .notAudio) && !isWindowMiniaturizedDueToPip {
      exitPIP()
    }
    player.events.emit(.windowDeminiaturized)
  }

  // MARK: - UI: Show / Hide

  func hideUIFromOSC() {
    guard !oscFloatingView.isDragging, !oscFloatingView.isReturningToDefault else { return }
    destroyTimer()
    isUIHiddenByOSCClick = sidebars.isAnyVisibleOrTransitioning
    hideUI(force: true)
  }

  func restoreUIFromVideoClick(_ event: NSEvent) -> Bool {
    guard isUIHiddenByOSCClick || animationState == .hidden || animationState == .willHide,
          event.clickCount <= 1,
          videoView.lastEventId == event.eventNumber,
          !sidebars.isAnyVisibleOrTransitioning,
          sidebars.resizingSidebarSide == nil,
          !sidebars.isEventCoveringVisibleSidebar(event) else { return false }
    showUI()
    updateTimer()
    return true
  }

  func resumeUIAutoRevealIfSidebarsClosed() {
    guard !sidebars.isAnyVisibleOrTransitioning else { return }
    restoreUIFromSidebarBackground()
  }

  func restoreUIFromSidebarBackground() {
    guard isUIHiddenByOSCClick else { return }
    showUI()
    updateTimer()
  }

  @objc func hideUIAndCursor() {
    // don't hide UI when dragging control bar
    if oscFloatingView.isDragging || oscFloatingView.isReturningToDefault || sidebars.isAnyVisibleOrTransitioning { return }
    hideUI()
    NSCursor.setHiddenUntilMouseMoves(true)
  }

  func hideUI(force: Bool = false) {
    guard force || !oscFloatingView.isReturningToDefault else { return }
    guard force || !sidebars.isAnyVisibleOrTransitioning else { return }
    guard pipStatus == .notInPIP || animationState == .hidden else { return }
    guard force || Preference.bool(for: .enableControlBarAutoHide) else { return }
    guard animationState != .hidden && animationState != .willHide else { return }
    hideSeekPreview()
    uiAnimationGeneration += 1
    let generation = uiAnimationGeneration
    animationState = .willHide
    player.refreshSyncUITimer()
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = AccessibilityPreferences.adjustedDuration(UIAnimationDuration)
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      fadeableViews.forEach { view in
        if view === titleBarView { titleBarView.setRevealed(false, animated: true) }
        else { view.animator().alphaValue = 0 }
      }
    }) { [weak self] in
      guard let self, uiAnimationGeneration == generation, animationState == .willHide else { return }
      fadeableViews.forEach { view in
        if let button = view as? NSButton, self.standardWindowButtons.contains(button) {
          view.alphaValue = 1e-100
        } else {
          view.isHidden = true
        }
        (view as? Titlebar)?.finishHiding()
      }
      animationState = .hidden
    }
  }

  func trackPluginMenu(_ body: () -> Void) {
    hideSeekPreview()
    isPluginMenuTracking = true
    defer {
      isPluginMenuTracking = false
      // Closing a popup resumes tracking inside its owning player.
      if isUIHiddenByOSCClick { isMouseInWindow = true }
    }
    body()
  }

  func showUI() {
    // Native PiP can activate the player before flyback finishes; reveal only after video returns.
    guard pipReturnWindowAlpha == nil else { return }
    guard !(isPluginMenuTracking && isUIHiddenByOSCClick) else { return }
    guard !player.disableUI, !liveText.isActive, !interactiveMode.isActive, !isCropTransitionInProgress else { return }
    isUIHiddenByOSCClick = false
    uiAnimationGeneration += 1
    let generation = uiAnimationGeneration
    animationState = .willShow
    fadeableViews.forEach { view in
      if view !== titleBarView { view.isHidden = false }
    }
    player.refreshSyncUITimer()
    standardWindowButtons.forEach { $0.isEnabled = true }
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = AccessibilityPreferences.adjustedDuration(UIAnimationDuration)
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      fadeableViews.forEach { view in
        if view === titleBarView { titleBarView.setRevealed(true, animated: true) }
        else { view.animator().alphaValue = 1 }
      }
    }) { [weak self] in
      guard let self, uiAnimationGeneration == generation, animationState == .willShow else { return }
      fadeableViews.forEach { ($0 as? Titlebar)?.finishShowing() }
      animationState = .shown
    }
  }

  // MARK: - UI: Show / Hide Timer

  func updateTimer() {
    destroyTimer()
    createTimer()
  }

  private func destroyTimer() {
    // if timer exist, destroy first
    if hideControlTimer != nil {
      hideControlTimer!.invalidate()
      hideControlTimer = nil
    }
  }

  private func createTimer() {
    guard !sidebars.isAnyVisibleOrTransitioning else { return }
    // create new timer
    let timeout = Preference.float(for: .controlBarAutoHideTimeout)
    hideControlTimer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self, selector: #selector(self.hideUIAndCursor), userInfo: nil, repeats: false)
  }

  // MARK: - UI: Title

  @objc
  override func updateTitle() {
    if player.info.isNetworkResource {
      window?.representedURL = nil
      window?.title = player.getMediaTitle()
    } else {
      window?.representedURL = player.info.currentURL
      // Workaround for issue #3543, IINA crashes reporting:
      // NSInvalidArgumentException [NSNextStepFrame _displayName]: unrecognized selector
      // When running on an M1 under Big Sur and using legacy full screen.
      //
      // Changes in Big Sur broke the legacy full screen feature. The MainWindowController method
      // legacyAnimateToFullscreen had to be changed to get this feature working again. Under
      // Big Sur that method now calls "window.styleMask.remove(.titled)". Removing titled from the
      // style mask causes the AppKit method NSWindow.setTitleWithRepresentedFilename to trigger the
      // exception listed above. This appears to be a defect in the Cocoa framework. The window's
      // title can still be set directly without triggering the exception. The problem seems to be
      // isolated to the setTitleWithRepresentedFilename method, possibly only when running on an
      // Apple Silicon based Mac. Based on the Apple documentation setTitleWithRepresentedFilename
      // appears to be a convenience method. As a workaround for the issue directly set the window
      // title.
      //
      // This problem has been reported to Apple as:
      // "setTitleWithRepresentedFilename throws NSInvalidArgumentException: NSNextStepFrame _displayName"
      // Feedback number FB9789129
      if Preference.bool(for: .useLegacyFullScreen) {
        window?.title = player.info.currentURL?.lastPathComponent ?? ""
      } else {
        window?.setTitleWithRepresentedFilename(player.info.currentURL?.path ?? "")
      }
    }
    titleBarView?.updateTitle()
    updateWindowButtonLayout()

    // Sometimes the doc icon may not be available, eg. when opened an online video.
    // We should try to add it every time when window title changed.
    if let docIcon = window?.standardWindowButton(.documentIconButton) {
      fadeableViews.add(docIcon) { [unowned self] in
        fsState == .windowed ? .auto : .alwaysShown
      }
    }
  }

  // MARK: - UI: OSD

  /// Show a message in the on screen display.
  /// - Parameters:
  ///   - message: The `OSDMessage` to display.
  ///   - autoHide: If `true` (the default) the message will be hidden after a timeout.
  ///   - forcedTimeout: Timeout after which the message will be hidden (overrides user configured timeout).
  ///   - accessoryView: Custom view to display (if not supplied normal OSD views are used).
  ///   - context: Additional information associated with the message.
  /// - Attention: Do not call `displayOSD` directly, call `PlayerCore.sendOSD` instead.
  /// - Important: As per Apple's [Internationalization and Localization Guide](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPInternational/SupportingRight-To-LeftLanguages/SupportingRight-To-LeftLanguages.html)
  ///     timeline indicators should not flip in a right-to-left language. Thus OSD messages referencing a position within the video
  ///     must always use a left to right layout.
  func displayOSD(_ message: OSDMessage, autoHide: Bool = true, forcedTimeout: Float? = nil, accessoryView: NSView? = nil, context: Any? = nil) {
    guard geometryMotion != nil || !isCropTransitionInProgress else { return }
    guard player.displayOSD || message.alwaysEnabled, !isShowingPersistentOSD else { return }

    if hideOSDTimer != nil {
      hideOSDTimer!.invalidate()
      hideOSDTimer = nil
    }
    if osdAnimationState != .shown {
      osdAnimationState = .shown  /// set this before calling `refreshSyncUITimer()`
      player.refreshSyncUITimer()
    } else {
      osdAnimationState = .shown
    }

    osdView.updateViews(fromMessage: message, player: player)

    osdView.alphaValue = 1
    osdView.isHidden = false
    osdView.layoutSubtreeIfNeeded()

    if let accessoryView {
      isShowingPersistentOSD = true
      if context != nil {
        osdContext = context
      }

      let heightConstraint = NSLayoutConstraint(item: accessoryView, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 300)
      heightConstraint.priority = .defaultLow
      heightConstraint.isActive = true

      osdView.addAccessoryView(accessoryView)

      // enlarge window if too small
      let winFrame = window!.frame
      var newFrame = winFrame
      if (winFrame.height < 300) {
        newFrame = winFrame.centeredResize(to: winFrame.size.satisfyMinSizeWithSameAspectRatio(NSSize(width: 500, height: 300)))
      }

      accessoryView.wantsLayer = true
      accessoryView.layer?.opacity = 0

      NSAnimationContext.runAnimationGroup({ context in
        context.duration = AccessibilityPreferences.adjustedDuration(0.3)
        context.allowsImplicitAnimation = true
        window!.setFrame(newFrame, display: true)
        osdView.layoutSubtreeIfNeeded()
      }, completionHandler: {
        accessoryView.layer?.opacity = 1
      })
    }

    if autoHide {
      let timeout = forcedTimeout ?? Preference.float(for: .osdAutoHideTimeout)
      hideOSDTimer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self, selector: #selector(self.hideOSD), userInfo: nil, repeats: false)
    }
  }

  @objc
  func hideOSD() {
    NSAnimationContext.runAnimationGroup({ (context) in
      self.osdAnimationState = .willHide
      context.duration = OSDAnimationDuration
      osdView.animator().alphaValue = 0
    }) {
      if self.osdAnimationState == .willHide {
        self.osdAnimationState = .hidden
        self.osdView.isHidden = true
        self.osdView.removeAccessoryView()
      }
    }
    isShowingPersistentOSD = false
    osdContext = nil
    player.refreshSyncUITimer()
  }

  // MARK: - UI: Interactive mode

  private func refreshSeekTimeAndThumbnail(from event: NSEvent) {
    let point = event.locationInWindow
    guard isSeekPreviewAvailable(at: point) else { hideSeekPreview(); return }
    if isPointInPlaySlider(point) {
      if seekPreviewHover == nil {
        seekPreviewHover = SeekPreviewHoverController(canShow: { [weak self] point in
          guard let self else { return false }
          return self.isSeekPreviewAvailable(at: point) && self.isPointInPlaySlider(point)
        }, show: { [weak self] point in
          self?.updateTimePreviewAndThumbnail(point)
        }, hide: { [weak self] in
          self?.thumbnailPeekView.isHidden = true
          self?.timePreviewView.isHidden = true
          self?.chapterPreviewView.isHidden = true
        }, setOpacity: { [weak self] opacity in
          guard let self else { return }
          [self.thumbnailPeekView, self.timePreviewView, self.chapterPreviewView].forEach { $0?.alphaValue = opacity }
        }, shouldAnimate: {
          !Preference.bool(for: .disableAnimations) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        })
      }
      seekPreviewHover?.hover(at: point)
    } else {
      seekPreviewHover?.leave()
    }
  }

  private func isPointInPlaySlider(_ point: NSPoint) -> Bool {
    playSlider.isMousePoint(playSlider.convert(point, from: nil), in: playSlider.bounds)
  }

  private func isSeekPreviewAvailable(at point: NSPoint) -> Bool {
    guard let window, window.isVisible, !window.isMiniaturized, playSlider.window === window,
          !interactiveMode.isActive, !isSeekingWithSlider, !isPluginMenuTracking,
          !oscFloatingView.isDragging, !oscFloatingView.isReturningToDefault, !isUIHiddenByOSCClick,
          animationState != .hidden, animationState != .willHide,
          !playSlider.isHiddenOrHasHiddenAncestor, pipStatus == .notInPIP else { return false }
    if !osdView.isHidden && osdView.isMousePoint(osdView.convert(point, from: nil), in: osdView.bounds) { return false }
    guard let contentView = window.contentView else { return false }
    let hit = contentView.hitTest(contentView.superview?.convert(point, from: nil) ?? point)
    return !sidebars.sideBars.contains { !$0.view.isHidden && hit?.isDescendant(of: $0.view) == true }
  }

  func cancelSeekPreviewHover() {
    seekPreviewHover?.cancel(hidePreview: false)
  }

  func hideSeekPreview() {
    cancelSeekPreviewHover()
    thumbnailPeekView.isHidden = true
    timePreviewView.isHidden = true
    chapterPreviewView.isHidden = true
  }

  // MARK: - UI: Window size / aspect

  var minimumWindowSize: NSSize {
    oscPosition == .floating ? AppData.floatingOSCWindowMinSize : AppData.mainWindowMinSize
  }

  /// Convert frame to content minimum to avoid counting toolbar height twice.
  private func applyNativeMinimumWindowSize() {
    guard let window else { return }
    let frame = NSRect(origin: .zero, size: minimumWindowSize)
    window.contentMinSize = window.contentRect(forFrameRect: frame).size
  }

  private func updateMinimumWindowSize() {
    guard let window else { return }
    let minimum = minimumWindowSize
    applyNativeMinimumWindowSize()
    guard fsState == .windowed, !interactiveMode.isActive,
          window.frame.width < minimum.width || window.frame.height < minimum.height else { return }
    let size = NSSize(width: max(window.frame.width, minimum.width),
                      height: max(window.frame.height, minimum.height))
    let frame = windowFrameConstrainedToScreen(window.frame.centeredResize(to: size),
                                               screenFrame: window.screen?.visibleFrame)
    setWindowAspectRatio(frame.size)
    window.setFrame(frame, display: true)
  }

  /// Preserve the floating minimum after screen fitting, allowing letterboxing.
  func windowFrameConstrainedToScreen(_ frame: NSRect, screenFrame: NSRect?) -> NSRect {
    guard let screenFrame else { return frame }
    var result = frame.constrain(in: screenFrame)
    guard oscPosition == .floating else { return result }
    let minimum = minimumWindowSize
    result = result.centeredResize(to: NSSize(
      width: max(result.width, min(minimum.width, screenFrame.width)),
      height: max(result.height, min(minimum.height, screenFrame.height))))
    result.origin.x = max(screenFrame.minX, min(result.minX, screenFrame.maxX - result.width))
    result.origin.y = max(screenFrame.minY, min(result.minY, screenFrame.maxY - result.height))
    return result
  }

  private var currentWindowAspectRatio: NSSize {
    guard let window else { return .zero }
    return Preference.unlockWindowAspectRatio || window.aspectRatio == .zero ? window.frame.size : window.aspectRatio
  }

  private func setWindowAspectRatio(_ aspectRatio: NSSize) {
    guard let window else { return }
    if Preference.unlockWindowAspectRatio {
      window.aspectRatio = .zero
      window.resizeIncrements = .init(width: 1, height: 1)
    } else {
      window.aspectRatio = aspectRatio
    }
  }

  /// Calculate the window frame from a parsed struct of mpv's `geometry` option.
  func windowFrameFromGeometry(newSize: NSSize? = nil, screen: NSScreen? = nil) -> NSRect? {
    guard let geometry = cachedGeometry ?? player.getGeometry(),
      let screenFrame = (screen ?? window?.screen)?.visibleFrame else { return nil }

    cachedGeometry = geometry
    var winFrame = window!.frame
    if let ns = newSize {
      winFrame.size.width = ns.width
      winFrame.size.height = ns.height
    }
    let winAspect = winFrame.size.aspect
    var widthOrHeightIsSet = false
    let independentSize = geometry.hasExplicitSize
    if independentSize, let width = geometry.w, let height = geometry.h {
      func dimension(_ token: String, extent: CGFloat) -> CGFloat {
        token.hasSuffix("%") ? CGFloat(Double(token.dropLast())!) * extent / 100 : CGFloat(Int(token)!)
      }
      winFrame.size = NSSize(
        width: min(screenFrame.width, max(minimumWindowSize.width, dimension(width, extent: screenFrame.width))),
        height: min(screenFrame.height, max(minimumWindowSize.height, dimension(height, extent: screenFrame.height))))
      widthOrHeightIsSet = true
    } else if let strw = geometry.w, strw != "0" {
      var w: CGFloat
      if strw.hasSuffix("%") {
        w = CGFloat(Double(String(strw.dropLast()))! * 0.01 * Double(screenFrame.width))
      } else {
        w = CGFloat(Int(strw)!)
      }
      w = max(minimumWindowSize.width, w)
      winFrame.size.width = w
      winFrame.size.height = w / winAspect
      widthOrHeightIsSet = true
    } else if let strh = geometry.h, strh != "0" {
      var h: CGFloat
      if strh.hasSuffix("%") {
        h = CGFloat(Double(String(strh.dropLast()))! * 0.01 * Double(screenFrame.height))
      } else {
        h = CGFloat(Int(strh)!)
      }
      h = max(minimumWindowSize.height, h)
      winFrame.size.height = h
      winFrame.size.width = h * winAspect
      widthOrHeightIsSet = true
    }
    if widthOrHeightIsSet && !independentSize {
      winFrame.size = oscPosition == .floating
        ? NSSize(width: max(winFrame.width, minimumWindowSize.width),
                 height: max(winFrame.height, minimumWindowSize.height))
        : winFrame.size.satisfyMinSizeWithSameAspectRatio(minimumWindowSize)
    }
    // Resolve position against the fitted dimensions to avoid stale centers and edge gaps.
    winFrame.size = windowFrameConstrainedToScreen(
      NSRect(origin: .zero, size: winFrame.size),
      screenFrame: NSRect(origin: .zero, size: screenFrame.size)).size
    // x, origin is window center
    if let strx = geometry.x, let xSign = geometry.xSign {
      let x: CGFloat
      if strx.hasSuffix("%") {
        x = CGFloat(Double(String(strx.dropLast()))! * 0.01 * Double(screenFrame.width)) - winFrame.width / 2
      } else {
        x = CGFloat(Int(strx)!)
      }
      winFrame.origin.x = xSign == "+" ? x : screenFrame.width - x
      // if xSign equals "-", need set right border as origin
      if (xSign == "-") {
        winFrame.origin.x -= winFrame.width
      }
    }
    // y
    if let stry = geometry.y, let ySign = geometry.ySign {
      let y: CGFloat
      if stry.hasSuffix("%") {
        y = CGFloat(Double(String(stry.dropLast()))! * 0.01 * Double(screenFrame.height)) - winFrame.height / 2
      } else {
        y = CGFloat(Int(stry)!)
      }
      winFrame.origin.y = ySign == "+" ? y : screenFrame.height - y
      if (ySign == "-") {
        winFrame.origin.y -= winFrame.height
      }
    }
    // if x and y are not specified
    if geometry.x == nil && geometry.y == nil && widthOrHeightIsSet {
      winFrame.origin.x = (screenFrame.width - winFrame.width) / 2
      winFrame.origin.y = (screenFrame.height - winFrame.height) / 2
    }
    // if the screen has offset
    winFrame.origin.x += screenFrame.origin.x
    winFrame.origin.y += screenFrame.origin.y

    return winFrame
  }

  /// Determine the screen to use for the window.
  /// - Parameter window: Window to determine the screen for.
  /// - Returns: Screen to use for the given window.
  private func determineScreenToUse(_ window: NSWindow) -> NSScreen {
    // If the window is currently showing on a screen, use this screen
    if window.isOnActiveSpace, let currentScreen = window.screen {
      NSScreen.log("Window is currently showing on screen", currentScreen, subsystem: subsystem)
      return currentScreen
    }
    guard let rectString = UserDefaults.standard.value(forKey: "MainWindowLastPosition") as? String else {
      let selected = window.selectDefaultScreen()
      NSScreen.log("MainWindowLastPosition not found, using default screen", selected,
                   subsystem: subsystem)
      return selected
    }
    let rect = NSRectFromString(rectString)
    guard let lastScreen = NSScreen.screens.first(where: { NSPointInRect(rect.origin, $0.frame) }) else {
      // The previous window origin is not on any screen. Could be an external screen is no longer
      // connected or the arrangement of the screens has changed.
      let selected = window.selectDefaultScreen()
      NSScreen.log("MainWindowLastPosition \(rect.origin) is not within any screens, using default screen",
                   selected, subsystem: subsystem)
      return selected
    }
    // Found a screen containing the previous window origin. Use that screen for the window.
    NSScreen.log("MainWindowLastPosition \(rect.origin) matched", lastScreen, subsystem: subsystem)
    return lastScreen
  }

  override func handleVideoSizeChange() {
    handleVideoSizeChange(keepWindowSize: false)
  }

  /** Set window size when info available, or video size changed. */
  func handleVideoSizeChange(keepWindowSize: Bool) {
    guard loaded, let window else { return }
    if let motion = geometryMotion, !motion.waitingForFrame {
      geometryVideoOutputDidChange()
      return
    }
    if let overlay = cropExitOverlay, overlay.isPreparingSource || overlay.isCommitting { return }
    // AppKit sends live-resize callbacks during our animated frame changes too.
    let wasApplyingFrame = isApplyingVideoTransformWindowFrame
    isApplyingVideoTransformWindowFrame = true
    defer {
      isApplyingVideoTransformWindowFrame = wasApplyingFrame
      finishVideoAspectTransition()
      if !wasApplyingFrame, !isCropTransitionInProgress {
        if oscPosition == .floating {
          invalidateFloatingOSCLayout()
          oscFloatingView.updatePosition()
        }
        liveText.requestAnalysis()
      }
    }
    if interactiveMode.isActive, cropExitOverlay == nil {
      interactiveMode.resize()
      return
    }

    // When starting to play the file try and find the screen the window was previously on.
    let screen = player.info.justStartedFile ? determineScreenToUse(window) : window.selectDefaultScreen()
    let screenRect = screen.visibleFrame
    let screenSize = screenRect.size

    let displaySize = geometryMotion?.targetDisplaySize ?? cropExitOverlay.flatMap { $0.targetDisplaySize.width > 0 && $0.targetDisplaySize.height > 0 ? $0.targetDisplaySize : nil }
    let (width, height) = displaySize.map { (Int($0.width.rounded()), Int($0.height.rounded())) } ?? player.videoSizeForDisplay

    if !player.info.justStartedFile { beginVideoAspectTransition() }

    // set aspect ratio
    let originalVideoSize = NSSize(width: width, height: height)
    setWindowAspectRatio(originalVideoSize)
    pip.aspectRatio = originalVideoSize

    var rect: NSRect
    let isInitialWindowSizing = shouldApplyInitialWindowSize
    // Consume file-size preferences once; output transforms retain the established scale.
    let isNewFileSizing = player.info.justStartedFile && !keepWindowSize && !isCropTransitionInProgress
      && windowSizingFileGeneration != player.info.trackSelectionGeneration
    let resizeTiming = Preference.enum(for: .resizeWindowTiming) as Preference.ResizeWindowTiming
    let shouldResizeForNewFile = isNewFileSizing
      && (resizeTiming == .always || (resizeTiming == .onlyWhenOpen && player.info.justOpenedFile))
      && (!Preference.unlockWindowAspectRatio || player.info.justOpenedFile)
    let usesSourceSize = isInitialWindowSizing || shouldResizeForNewFile

    let frame = fsState.priorWindowedFrame ?? window.frame

    if !usesSourceSize {
      if Preference.unlockWindowAspectRatio || width <= 0 || height <= 0 {
        rect = frame
        videoTransformWindowReferenceSize = nil
        videoTransformWindowSize = nil
        videoTransformWindowDisplaySize = nil
        videoTransformWindowGeneration = nil
      } else {
        establishVideoTransformWindowReference(windowSize: frame.size, displaySize: originalVideoSize)
        let reference = videoTransformWindowReferenceSize ?? frame.size
        let size = videoTransformWindowDisplaySize == originalVideoSize
          ? videoTransformWindowSize ?? frame.size : originalVideoSize.shrink(toSize: reference)
        rect = frame.centeredResize(to: size)
      }
    } else {
      log("Need to resize window")
      // get videoSize on screen
      var videoSize = originalVideoSize
      if Preference.bool(for: .usePhysicalResolution) {
        videoSize = window.convertFromBacking(
          NSMakeRect(window.frame.origin.x, window.frame.origin.y, CGFloat(width), CGFloat(height))).size
        if videoSize != originalVideoSize {
          log("""
            Adjusted size from \(originalVideoSize) to \(videoSize) based on physical \
            resolution of display
            """)
        }
      }
      let resizePreference = Preference.enum(for: .resizeWindowOption) as Preference.ResizeWindowOption
      if player.info.justStartedFile {
        let sizeBefore = videoSize
        if resizePreference == .fitScreen {
          videoSize = videoSize.shrink(toSize: screenSize)
          if sizeBefore != videoSize {
            log("Resized window to \(videoSize) to fit in screen")
          }
        } else {
          let resizeRatio = resizePreference.ratio
          videoSize = videoSize.multiply(CGFloat(resizeRatio))
          if sizeBefore != videoSize {
            log("Resized window to \(resizeRatio)x video size \(videoSize)")
          }
        }
      }
      // check screen size
      videoSize = videoSize.satisfyMaxSizeWithSameAspectRatio(screenSize)
      // guard min size
      // must be slightly larger than the min size, or it will crash when the min size is auto saved as window frame size.
      videoSize = videoSize.satisfyMinSizeWithSameAspectRatio(minimumWindowSize)
      if shouldApplyInitialWindowSize {
        // check if have geometry set (initial window position/size)
        if let wfg = windowFrameFromGeometry(newSize: videoSize, screen: screen) {
          rect = wfg
          log("Adjusted window frame based on geometry option: \(rect)")
        } else {
          rect = videoSize.centeredRect(in: screenRect)
          log("Centered window in screen: \(rect)")
        }
      } else if player.info.justStartedFile, resizePreference == .fitScreen {
        rect = screenRect.centeredResize(to: videoSize)
        log("Centered window in screen and resized: \(rect)")
      } else {
        rect = frame.centeredResize(to: videoSize)
        log("Resized window preserving centering: \(rect)")
      }
    }

    shouldApplyInitialWindowSize = false
    if isInitialWindowSizing || isNewFileSizing {
      windowSizingFileGeneration = player.info.trackSelectionGeneration
    }

    let hasExplicitSize = cachedGeometry?.hasExplicitSize == true
    if !isInitialWindowSizing || hasExplicitSize {
      rect = rect.centeredResize(to: NSSize(width: max(rect.width, minimumWindowSize.width),
                                           height: max(rect.height, minimumWindowSize.height)))
    } else {
      rect = rect.centeredResize(to: rect.size.satisfyMinSizeWithSameAspectRatio(minimumWindowSize))
    }
    let rectBefore = rect
    rect = windowFrameConstrainedToScreen(rect, screenFrame: screenRect)
    if rectBefore != rect {
      log("Constrained window frame to be in screen: \(rect)")
    }

    // Explicit geometry already includes the titlebar.
    if isInitialWindowSizing && !Preference.bool(for: .edgeToEdgeVideo) && Preference.bool(for: .dockedControlBarAndTitlebar)
      && !hasExplicitSize {
      rect.size.height += titleBarView.frame.height
      if oscPosition == .bottom {
        rect.size.height += oscBottomView.frame.height
      }
      rect = windowFrameConstrainedToScreen(rect, screenFrame: screenRect)
    }

    if usesSourceSize && !Preference.unlockWindowAspectRatio {
      establishVideoTransformWindowReference(windowSize: rect.size, displaySize: originalVideoSize, initial: true)
    }
    setWindowAspectRatio(rect.size)

    if Preference.unlockWindowAspectRatio && !usesSourceSize {
      // do nothing when window aspect ratio is unlocked
      // however, if this is the first time opening the window, still apply the sizing logic
      updateMinimumWindowSize()
      cropExitOverlay?.targetWindowFrame = window.frame
      geometryMotion?.targetWindowFrame = window.frame
    } else if fsState.isFullscreen {
      log("In full screen mode, setting prior window frame")
      fsState.priorWindowedFrame = rect
      cropExitOverlay?.targetWindowFrame = window.frame
      geometryMotion?.targetWindowFrame = window.frame
    } else {
      log("Setting window frame to: \(rect)")
      if let motion = geometryMotion {
        motion.targetWindowFrame = rect
      } else if let overlay = cropExitOverlay {
        overlay.targetWindowFrame = rect
      } else if player.disableWindowAnimation || Preference.bool(for: .disableAnimations) || !window.isVisible {
        window.setFrame(rect, display: true, animate: false)
      } else {
        // animated `setFrame` can be inaccurate!
        let videoLayer = videoView.videoLayer
        let wasAnimating = videoLayer.isAnimatingWindowResize
        videoLayer.isAnimatingWindowResize = true
        defer { videoLayer.isAnimatingWindowResize = wasAnimating }
        window.setFrame(rect, display: true, animate: true)
        window.setFrame(rect, display: true)
      }
      if cropExitOverlay == nil && geometryMotion == nil { updateWindowParametersForMPV(withFrame: rect) }
    }

    if videoTransformWindowReferenceSize != nil {
      // Animated AppKit frame changes can still report the previous frame here.
      videoTransformWindowSize = rect.size
      videoTransformWindowDisplaySize = originalVideoSize
    }

    // generate thumbnails after video loaded if it's the first time
    if !isVideoLoaded {
      player.generateThumbnails()
      isVideoLoaded = true
    }

    // UI and slider
    updatePlayTime(withDuration: true, andProgressBar: true)
    player.events.emit(.windowSizeAdjusted, data: rect)
  }

  func updateWindowParametersForMPV(withFrame frame: NSRect? = nil) {
    guard let window else { return }
    if (player.info.videoWidth ?? 0) > 0 {
      let displayWidth = player.videoSizeForDisplay.0
      guard displayWidth > 0 else { return }
      let rect = frame ?? window.frame
      let width = Preference.bool(for: .usePhysicalResolution) ? window.convertToBacking(rect).width : rect.width
      let windowScale = Double(width) / Double(displayWidth)
      player.info.cachedWindowScale = windowScale
      player.mpv.setDouble(MPVOption.Window.windowScale, windowScale, level: .verbose)
    }
  }

  func setWindowScale(_ scale: Double) {
    guard loaded, let window, fsState == .windowed else { return }
    let (videoWidth, videoHeight) = player.videoSizeForDisplay
    guard scale.isFinite, scale > 0, videoWidth > 0, videoHeight > 0 else { return }
    finishVideoAspectTransition()
    rememberVideoTransformWindowResize()
    let screenFrame = (window.screen ?? NSScreen.main!).visibleFrame
    let newFrame: NSRect
    // calculate 1x size
    let useRetinaSize = Preference.bool(for: .usePhysicalResolution)
    let logicalFrame = NSRect(x: window.frame.origin.x,
                             y: window.frame.origin.y,
                             width: CGFloat(videoWidth),
                             height: CGFloat(videoHeight))
    var finalSize = (useRetinaSize ? window.convertFromBacking(logicalFrame) : logicalFrame).size
    // calculate scaled size
    let scalef = CGFloat(scale)
    finalSize.width *= scalef
    finalSize.height *= scalef
    // set size
    if finalSize.width > screenFrame.size.width || finalSize.height > screenFrame.size.height {
      // if final size is bigger than screen
      newFrame = window.frame.centeredResize(to: finalSize.shrink(toSize: screenFrame.size)).constrain(in: screenFrame)
    } else {
      // otherwise, resize the window normally
      let size = NSSize(width: max(finalSize.width, minimumWindowSize.width),
                        height: max(finalSize.height, minimumWindowSize.height))
      newFrame = window.frame.centeredResize(to: size).constrain(in: screenFrame)
    }
    let target = windowFrameConstrainedToScreen(newFrame, screenFrame: screenFrame)
    setUserWindowFrame(target)
    MemoryUsage.shared.logUsage("after window scale changed (\(newFrame.width)x\(newFrame.height))")
  }

  func setUserWindowFrame(_ frame: NSRect) {
    guard loaded, let window, fsState == .windowed, !isCropTransitionInProgress else { return }
    prepareVideoTransformWindowReference()
    setWindowAspectRatio(frame.size)
    updateVideoTransformWindowReference(to: frame.size)
    let wasApplyingFrame = isApplyingVideoTransformWindowFrame
    isApplyingVideoTransformWindowFrame = true
    defer { isApplyingVideoTransformWindowFrame = wasApplyingFrame }
    window.setFrame(frame, display: true, animate: !Preference.bool(for: .disableAnimations))
    window.setFrame(frame, display: true)
  }

  // MARK: - UI: Others

  private func blackOutOtherMonitors() {
    screens = NSScreen.screens.filter { $0 != window?.screen }

    for window in blackWindows {
      window.orderOut(self)
    }
    blackWindows = []

    for screen in screens {
      var screenRect = screen.frame
      screenRect.origin = CGPoint(x: 0, y: 0)
      let blackWindow = NSWindow(contentRect: screenRect, styleMask: [], backing: .buffered, defer: false, screen: screen)
      blackWindow.backgroundColor = .black
      blackWindow.level = .iinaBlackScreen

      blackWindows.append(blackWindow)
      blackWindow.orderFront(self)
    }
  }

  private func removeBlackWindow() {
    for window in blackWindows {
      window.orderOut(self)
    }
    blackWindows = []
  }

  override func setWindowFloatingOnTop(_ onTop: Bool, updateOnTopStatus: Bool = true) {
    guard !fsState.isFullscreen else { return }
    super.setWindowFloatingOnTop(onTop, updateOnTopStatus: updateOnTopStatus)

    resetCollectionBehavior()
    // don't know why they will be disabled
    standardWindowButtons.forEach { $0.isEnabled = true }
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

  @objc func menuToggleLiveText(_ item: NSMenuItem) {
    Preference.set(!Preference.bool(for: .enableLiveText), for: .enableLiveText)
  }

  // MARK: - Sync UI with playback

  func isUITimerNeeded() -> Bool {
    let isShowingFadeableViews = animationState == .shown || animationState == .willShow
    let isShowingOSD = osdAnimationState == .shown || osdAnimationState == .willShow
    return isShowingFadeableViews || isShowingOSD
  }

  override func updatePlayTime(withDuration duration: Bool, andProgressBar: Bool) {
    super.updatePlayTime(withDuration: duration, andProgressBar: andProgressBar)
    syncPIPPlaybackState()

    if osdAnimationState == .shown, let osdLastMessage = self.osdLastMessage {
      let message: OSDMessage
      switch osdLastMessage {
      case .pause, .resume, .showTime(_):
        message = osdLastMessage
      case .seek(_, _, _):
        let current = player.info.videoPosition?.stringRepresentation ?? Constants.String.videoTimePlaceholder
        let total = player.info.videoDuration?.stringRepresentation ?? Constants.String.videoTimePlaceholder
        let percentage = (player.info.videoPosition / player.info.videoDuration) ?? 1
        message = .seek(current, total, percentage)
      default:
        return
      }

      self.osdLastMessage = message
      osdView.updateViews(fromMessage: message, player: player)
    }
  }

  override func updatePlayButtonState(paused: Bool) {
    super.updatePlayButtonState(paused: paused)
    if paused {
      speedValueIndex = AppData.availableSpeedValues.count / 2
    }
    syncPIPPlaybackState()
  }

  /// Configure the OSC arrow buttons based on IINA's `Use left/right button for` setting.
  ///
  /// For most settings the button is configured to be a
  /// [momentaryPushIn](https://developer.apple.com/documentation/appkit/nsbutton/buttontype/momentarypushin)
  /// button. However if the button is set to control playback speed the button is configured to be a
  /// [multiLevelAccelerator](https://developer.apple.com/documentation/appkit/nsbutton/buttontype/multilevelaccelerator)
  /// button. This allows the user to control the speed using pressure when using devices that support pressure sensitivity.
  func updateArrowButtons() {
    if arrowBtnFunction == .playlist {
      leftArrowButton.image = #imageLiteral(resourceName: "nextl")
      rightArrowButton.image = #imageLiteral(resourceName: "nextr")
    } else {
      leftArrowButton.image = #imageLiteral(resourceName: "speedl")
      rightArrowButton.image = #imageLiteral(resourceName: "speed")
    }
    if arrowBtnFunction == .speed {
      leftArrowButton.setButtonType(.multiLevelAccelerator)
      rightArrowButton.setButtonType(.multiLevelAccelerator)
    } else {
      leftArrowButton.setButtonType(.momentaryPushIn)
      rightArrowButton.setButtonType(.momentaryPushIn)
    }
  }

  override func updateVolume() {
    guard loaded else { return }
    super.updateVolume()
  }

  // MARK: - IBActions

  @IBAction override func playButtonAction(_ sender: NSButton) {
    super.playButtonAction(sender)
    if player.info.state == .paused {
      // speed is already reset by playerCore
      speedValueIndex = AppData.availableSpeedValues.count / 2
      // set speed to 0 if is fastforwarding
      if isFastforwarding {
        player.setSpeed(1)
        isFastforwarding = false
      }
    }
  }

  @IBAction override func muteButtonAction(_ sender: NSButton) {
    super.muteButtonAction(sender)
    player.sendOSD(player.info.isMuted ? .mute : .unMute)
  }

  /// User has triggered the left button in the OSC.
  ///
  /// The behavior of the button depends upon the `Use left/right button for` setting found in the
  /// `On Screen Controller` section on the `UI` tab of IINA's settings. For most settings the button is configured to be a
  /// [momentaryPushIn](https://developer.apple.com/documentation/appkit/nsbutton/buttontype/momentarypushin)
  /// button. However if the button is set to control playback speed the button is configured to be a
  /// [multiLevelAccelerator](https://developer.apple.com/documentation/appkit/nsbutton/buttontype/multilevelaccelerator)
  /// button. This allows the user to control the speed using pressure when using devices that support pressure sensitivity.
  /// - Parameter sender: The button invoking this action.
  @IBAction func leftButtonAction(_ sender: NSButton) {
    switch arrowBtnFunction {
    case .playlist, .seek:
      arrowButtonAction(left: true)
    case .speed:
      let speeds = AppData.availableSpeedValues.count
      // If fast forwarding change speed to 1x
      if speedValueIndex > speeds / 2 {
        speedValueIndex = speeds / 2
      }

      if sender.intValue == 0 { // Released
        if maxPressure == 1 &&
          (speedValueIndex < speeds / 2 - 1 ||
          Date().timeIntervalSince(lastClick) < minimumPressDuration) { // Single click ended, 2x speed
          speedValueIndex = oldIndex - 1
        } else { // Force Touch or long press ended
          speedValueIndex = speeds / 2
        }
        maxPressure = 0
      } else {
        if sender.intValue == 1 && maxPressure == 0 { // First press
          oldIndex = speedValueIndex
          speedValueIndex -= 1
          lastClick = Date()
        } else { // Force Touch
          speedValueIndex = max(oldIndex - Int(sender.intValue), 0)
        }
        maxPressure = max(maxPressure, sender.intValue)
      }
      arrowButtonAction(left: true)
    }
  }

  /// User has triggered the right button in the OSC.
  ///
  /// The behavior of the button depends upon the `Use left/right button for` setting found in the
  /// `On Screen Controller` section on the `UI` tab of IINA's settings. For most settings the button is configured to be a
  /// [momentaryPushIn](https://developer.apple.com/documentation/appkit/nsbutton/buttontype/momentarypushin)
  /// button. However if the button is set to control playback speed the button is configured to be a
  /// [multiLevelAccelerator](https://developer.apple.com/documentation/appkit/nsbutton/buttontype/multilevelaccelerator)
  /// button. This allows the user to control the speed using pressure when using devices that support pressure sensitivity.
  /// - Parameter sender: The button invoking this action.
  @IBAction func rightButtonAction(_ sender: NSButton) {
    switch arrowBtnFunction {
    case .playlist, .seek:
      arrowButtonAction(left: false)
    case .speed:
      let speeds = AppData.availableSpeedValues.count
      // If rewinding change speed to 1x
      if speedValueIndex < speeds / 2 {
        speedValueIndex = speeds / 2
      }

      if sender.intValue == 0 { // Released
        if maxPressure == 1 &&
          (speedValueIndex > speeds / 2 + 1 ||
          Date().timeIntervalSince(lastClick) < minimumPressDuration) { // Single click ended
          speedValueIndex = oldIndex + 1
        } else { // Force Touch or long press ended
          speedValueIndex = speeds / 2
        }
        maxPressure = 0
      } else {
        if sender.intValue == 1 && maxPressure == 0 { // First press
          oldIndex = speedValueIndex
          speedValueIndex += 1
          lastClick = Date()
        } else { // Force Touch
          speedValueIndex = min(oldIndex + Int(sender.intValue), speeds - 1)
        }
        maxPressure = max(maxPressure, sender.intValue)
      }
      arrowButtonAction(left: false)
    }
  }

  /** handle action of both left and right arrow button */
  func arrowButtonAction(left: Bool) {
    switch arrowBtnFunction {
    case .speed:
      isFastforwarding = true
      let speedValue = AppData.availableSpeedValues[speedValueIndex]
      player.setSpeed(speedValue)
      // if is paused
      if player.info.state == .paused {
        player.resume()
      }

    case .playlist:
      player.navigateInPlaylist(nextMedia: !left)

    case .seek:
      let configuredStep = Preference.double(for: .oscArrowSeekSeconds)
      let step = configuredStep.isFinite && configuredStep >= 1 ? configuredStep : 10
      player.seek(relativeSecond: left ? -step : step, option: .relative)

    }
  }

  func updateSpeedLabel(speed: Double) {
    if (speed == 1) {
      oscSpeedLabelLeft.isHidden = true
      oscSpeedLabelRight.isHidden = true
    } else if speed < 1 {
      oscSpeedLabelLeft.isHidden = false
      oscSpeedLabelRight.isHidden = true
      oscSpeedLabelLeft.stringValue = String(format: "%.2fx", speed)
    } else if speed > 1 {
      oscSpeedLabelLeft.isHidden = true
      oscSpeedLabelRight.isHidden = false
      let fmt = NumberFormatter()
      fmt.numberStyle = .decimal
      fmt.maximumSignificantDigits = 3
      oscSpeedLabelRight.stringValue = fmt.string(for: speed)! + "x"
    }
  }

  @objc func ontopButtonAction(_ sender: NSButton) {
    setWindowFloatingOnTop(!isOntop)
  }

  /** When slider changes */
  @IBAction override func playSliderChanges(_ sender: NSSlider) {
    // guard let event = NSApp.currentEvent else { return }
    guard player.info.state.active, player.info.state != .loading else { return }
    super.playSliderChanges(sender)

    updateTimePreview(sender.doubleValue / sender.maxValue)
  }

  @objc func toolBarButtonAction(_ sender: NSButton) {
    guard let buttonType = Preference.ToolBarButton(rawValue: sender.tag) else { return }
    switch buttonType {
    case .fullScreen:
      toggleWindowFullScreen()
    case .musicMode:
      player.switchToMiniPlayer()
    case .pip:
      if pipStatus == .inPIP {
        exitPIP()
      } else if pipStatus == .notInPIP {
        enterPIP()
      }
    case .playlist:
      sidebars.show(sidebar: .playlist)
    case .settings:
      sidebars.show(sidebar: .settings)
    case .subTrack:
      showSubChooseMenu(forView: sender, showLoadedSubs: true)
    case .screenshot:
      player.screenshot()
    case .plugins:
      sidebars.show(sidebar: .plugins)
    case .liveText:
      Preference.set(!Preference.bool(for: .enableLiveText), for: .enableLiveText)
    }
  }

  override func handleIINACommand(_ cmd: IINACommand) {
    super.handleIINACommand(cmd)
    switch cmd {
    case .toggleMusicMode:
      player.switchToMiniPlayer()
    case .liveText:
      menuToggleLiveText(.dummy)
    default:
      break
    }
  }

  private lazy var oscPositionShortcutSheet = OSCPositionSettingsSheetController()

  override func handleInterfaceCommand(_ cmd: IINACommand, arguments: [String]) -> Bool {
    guard cmd.acceptsArguments(arguments), let window, window.attachedSheet == nil,
          !interactiveMode.isActive else { return false }
    switch cmd {
    case .escape:
      if sidebars.isAnyVisibleOrTransitioning {
        sidebars.hideAllSideBars()
        window.makeFirstResponder(window)
      } else if fsState.isFullscreen {
        toggleWindowFullScreen()
      }
    case .closeSidebars:
      sidebars.hideAllSideBars()
      window.makeFirstResponder(window)
    case .showPanel, .hidePanel, .togglePanel:
      guard let target = IINACommand.Panel(rawValue: arguments[0]) else { return false }
      let type: SidebarController.ViewType
      let tab: String?
      switch target {
      case .settings: type = .settings; tab = nil
      case .layout, .video, .audio, .sub: type = .settings; tab = target.rawValue
      case .playlist, .chapters: type = .playlist; tab = target.rawValue
      case .plugins: type = .plugins; tab = nil
      }
      if cmd == .hidePanel {
        sidebars.hide(type)
      } else {
        sidebars.show(sidebar: type, tab: tab, hideIfAlreadyShown: cmd == .togglePanel)
      }
    case .nextPlugin, .previousPlugin:
      sidebars.show(sidebar: .plugins, hideIfAlreadyShown: false)
      sidebars.pluginView.switchPlugin(cmd == .nextPlugin ? 1 : -1)
    case .openPlugin:
      let identifier = arguments[0]
      guard player.plugins.contains(where: { $0.plugin.identifier == identifier && $0.plugin.sidebarTabName != nil }) else { return false }
      sidebars.show(sidebar: .plugins, tab: identifier, hideIfAlreadyShown: false)
      sidebars.pluginView.selectPlugin(withIdentifier: identifier)
    case .showOSC:
      showUI()
      updateTimer()
    case .hideOSC:
      hideUIFromOSC()
    case .toggleOSC:
      if isUIHiddenByOSCClick || animationState == .hidden || animationState == .willHide {
        showUI()
        updateTimer()
      } else {
        hideUIFromOSC()
      }
    case .resetOSCPosition:
      guard oscPosition == .floating else { return false }
      showUI()
      oscFloatingView.resetPosition()
      updateTimer()
    case .configureOSCPosition:
      guard oscPosition == .floating else { return false }
      OSCPositionConfiguration.present(on: window, players: [player], using: oscPositionShortcutSheet)
    case .openCustomCrop:
      guard pipStatus == .notInPIP else { return false }
      player.openScopedCustomCrop()
    default:
      return false
    }
    return true
  }

  // MARK: - Time Preveiew & Thumbnail

  /** Display time label when mouse over slider */
  private func updateTimePreviewAndThumbnail(_ posInWindow: NSPoint) {
    guard let duration = player.info.videoDuration else {
      hideSeekPreview()
      return
    }

    let mouseXPos = playSlider.convert(posInWindow, from: nil).x
    let percentage = Double((mouseXPos - 3) / (playSlider.bounds.width - 6)).clamped(to: (0...1))

    timePreviewView.isHidden = false
    let previewTime = duration * percentage
    updateTimePreview(percentage)

    if player.info.thumbnailsReady, let image = player.info.getThumbnail(forSecond: previewTime.second)?.image {
      thumbnailPeekView.imageView.image = image.rotate(rotation)
      thumbnailPeekView.isHidden = false

      // In some formats (like most of Japanese TV video formats), display aspect ratios (DAR) are different from the
      // sample aspect ratio (SAR). A typical configuration is SAR 1440x1080i (4:3) w/ DAR 1920x1080 (16:9). We use video
      // display size to consider pixel formats as well as rotation from metadata properly display the thumbnail.
      let (videoWidth, videoHeight) = player.videoSizeForDisplay
      let displayAspectRatio = CGFloat(videoWidth) / CGFloat(videoHeight)

      let width = CGFloat(UserDefaults.standard.integer(forKey: "thumbnailWidth"))
      let height = round(width / displayAspectRatio)
      positionSeekPreview(percentage, thumbnailSize: NSSize(width: width, height: height))
    } else {
      thumbnailPeekView.isHidden = true
    }
  }

  private func updateTimePreview(_ percentage: Double) {
    guard let duration = player.info.videoDuration else { return }
    let time = duration * percentage
    timePreviewView.setText(time.stringRepresentation)
    let chapterTitle = player.info.getChapter(forVideoTime: time)?.title
      .components(separatedBy: .newlines).joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let maximumChapterWidth = min(CGFloat(UserDefaults.standard.integer(forKey: "thumbnailWidth")),
                                  window?.contentView?.bounds.width ?? .greatestFiniteMagnitude)
    chapterPreviewView.setText(chapterTitle, maximumWidth: maximumChapterWidth)
    chapterPreviewView.isHidden = chapterTitle.isEmpty || isSeekingWithSlider
    positionSeekPreview(percentage)
  }

  private func positionSeekPreview(_ percentage: Double, thumbnailSize: NSSize? = nil) {
    guard let window, let contentView = window.contentView else { return }
    contentView.layoutSubtreeIfNeeded()
    let sliderFrame = playSlider.convert(playSlider.bounds, to: nil)
    let centerX = sliderFrame.minX + sliderFrame.width * percentage
    let chapterHeight = chapterPreviewView.isHidden ? 0 : chapterPreviewView.frame.height + 4
    let thumbnailHeight = thumbnailSize.map { $0.height + 5 } ?? 0
    let topOfGroup = sliderFrame.maxY + 5 + timePreviewView.frame.height + chapterHeight + thumbnailHeight
    let contentHeight = min(window.contentLayoutRect.height, contentView.bounds.height)
    let showAbove = oscPosition == .bottom || (oscPosition != .top && topOfGroup <= contentHeight)

    func centeredX(_ width: CGFloat) -> CGFloat {
      max(0, min(round(centerX - width / 2), contentView.bounds.width - width))
    }
    timePreviewView.frame.origin = NSPoint(x: centeredX(timePreviewView.frame.width), y: showAbove
      ? sliderFrame.maxY + 5 : sliderFrame.minY - timePreviewView.frame.height - 5)
    if !chapterPreviewView.isHidden {
      chapterPreviewView.frame.origin = NSPoint(x: centeredX(chapterPreviewView.frame.width), y: showAbove
        ? timePreviewView.frame.maxY + 4 : timePreviewView.frame.minY - chapterPreviewView.frame.height - 4)
    }
    if let thumbnailSize {
      let labelFrame = chapterPreviewView.isHidden ? timePreviewView.frame : chapterPreviewView.frame
      thumbnailPeekView.frame = NSRect(x: centeredX(thumbnailSize.width), y: showAbove
        ? labelFrame.maxY + 5 : labelFrame.minY - thumbnailSize.height - 5,
        width: thumbnailSize.width, height: thumbnailSize.height)
    }
  }


  // MARK: - Utility

  private func resetCollectionBehavior() {
    guard !fsState.isFullscreen else { return }
    if Preference.bool(for: .useLegacyFullScreen) {
      window?.collectionBehavior = [.managed, .fullScreenAuxiliary]
    } else {
      window?.collectionBehavior = [.managed, .fullScreenPrimary]
    }
  }

}

// MARK: - Picture in Picture

extension MainWindowController {
  /// Feedback follows explicit work, including overlapping capture/import requests.
  /// A completed request cannot dismiss another request's indicator.
  func beginOperationFeedback() -> UUID {
    dispatchPrecondition(condition: .onQueue(.main))
    let request = UUID()
    operationFeedbackRequests.insert(request)
    guard operationFeedbackToken == nil, isWindowLoaded else { return request }
    let host: NSView = pipStatus == .inPIP && videoView.window !== window ? videoView : videoViewContainer
    let feedback = operationFeedbackView ?? PreparationFeedbackView(frame: host.bounds)
    feedback.frame = host.bounds
    feedback.autoresizingMask = [.width, .height]
    host.addSubview(feedback)
    operationFeedbackView = feedback
    operationFeedbackToken = feedback.feedback.begin(pulse: !AccessibilityPreferences.motionReductionEnabled)
    return request
  }

  func endOperationFeedback(_ request: UUID) {
    dispatchPrecondition(condition: .onQueue(.main))
    guard operationFeedbackRequests.remove(request) != nil,
          operationFeedbackRequests.isEmpty,
          let token = operationFeedbackToken else { return }
    operationFeedbackToken = nil
    operationFeedbackView?.feedback.cancel(token, animated: true)
  }

  private func relocateOperationFeedback(to host: NSView) {
    guard !operationFeedbackRequests.isEmpty, let feedback = operationFeedbackView else { return }
    feedback.frame = host.bounds
    host.addSubview(feedback)
  }

  private func cancelOperationFeedback() {
    dispatchPrecondition(condition: .onQueue(.main))
    operationFeedbackRequests.removeAll()
    if let token = operationFeedbackToken { operationFeedbackView?.feedback.cancel(token, animated: false) }
    operationFeedbackToken = nil
    pipPreparationFeedback = nil
    operationFeedbackView?.removeFromSuperview()
    operationFeedbackView = nil
  }
}

extension MainWindowController: PIPViewControllerDelegate {

  func enterPIP() {
    guard pipStatus == .notInPIP, loaded, let videoWindow = window,
          player.info.state.loaded, !player.info.activeTrackIDs(.video).isEmpty,
          !player.isInMiniPlayer, !isFullscreenTransitionInProgress,
          videoView.window === videoWindow, videoView.superview === videoViewContainer else { return }
    interruptPlayerCropTransition()
    if isCropTransitionInProgress { cancelCropExitTransition() }
    // The editor owns the layer projection and temporary uncropped source.
    interactiveMode.exit()
    pipStatus = .inPIP
    let mediaGeneration = player.info.trackSelectionGeneration
    liveText.clearAnalysis()
    let feedback = beginOperationFeedback()
    pipPreparationFeedback = feedback

    // Capture the live video's screen geometry before PiP reparents its view.
    let sourceWindow = window
    let shouldKeepWindow = sourceWindow.map {
      $0.styleMask.contains(.fullScreen) || $0.isMiniaturized
    } ?? true
    let behavior: Preference.WindowBehaviorWhenPip = shouldKeepWindow ? .doNothing : Preference.enum(for: .windowBehaviorWhenPip)
    let supportsPreparation = pip.responds(to: NSSelectorFromString("presentViewControllerAsPictureInPicture:completionHandler:"))
    let sourceRect = supportsPreparation && behavior == .hide ? sourceWindow.map {
      $0.convertToScreen(videoViewContainer.convert(videoViewContainer.bounds, to: nil))
    } : nil

    let presentation = NSViewController()
    pipVideo = presentation
    // The system prepares its remote host asynchronously. Keep playback in the
    // player until that host is ready, then transfer the same live view once.
    if supportsPreparation {
      let container = NSView(frame: videoView.bounds)
      container.autoresizingMask = [.width, .height]
      presentation.view = container
    } else {
      // Older systems offer no preparation boundary; retain their direct handoff.
      videoView.videoLayer.isHostedInPIP = true
      presentation.view = videoView
    }
    pip.playing = player.info.state == .playing
    pip.title = sourceWindow?.title

    // A hidden player must not flash its empty PiP placeholder during handoff.
    pipOverlayView.isHidden = behavior == .hide

    var prepared = false
    let finishPreparation: () -> Void = { [weak self, weak presentation, weak sourceWindow] in
      let update = {
        guard let self, let presentation,
              self.pipStatus == .inPIP, self.pipVideo === presentation,
              !prepared else { return }
        guard let sourceWindow else { self.exitPIP(); return }
        if supportsPreparation {
          guard self.player.info.state.loaded,
                self.player.info.trackSelectionGeneration == mediaGeneration,
                !self.player.info.activeTrackIDs(.video).isEmpty,
                !self.player.isInMiniPlayer, !self.isFullscreenTransitionInProgress,
                self.videoView.window === sourceWindow,
                self.videoView.superview === self.videoViewContainer else { self.exitPIP(); return }
        }
        prepared = true
        // This callback precedes the native launch-rectangle read; it does not mean remote video is visible.
        if let sourceRect, let host = presentation.view.window, host !== sourceWindow {
          host.setFrame(host.frameRect(forContentRect: sourceRect), display: false)
          host.contentView?.layoutSubtreeIfNeeded()
        }
        self.endOperationFeedback(feedback)
        self.pipPreparationFeedback = nil
        self.videoView.videoLayer.isHostedInPIP = true
        if presentation.view !== self.videoView {
          presentation.view.addSubview(self.videoView)
          self.videoView.frame = presentation.view.bounds
        }
        self.relocateOperationFeedback(to: self.videoView)
        // Render at launch geometry before hiding the source or starting native presentation.
        self.videoView.prepareForPIPDisplay()
        switch behavior {
        case .doNothing:
          break
        case .hide:
          self.isWindowHidden = true
          let animation = sourceWindow.animationBehavior
          sourceWindow.animationBehavior = .none
          sourceWindow.orderOut(self)
          sourceWindow.animationBehavior = animation
        case .minimize:
          self.isWindowMiniaturizedDueToPip = true
          sourceWindow.miniaturize(self)
        }
      }
      // Do not defer geometry until after the native launch rectangle is read.
      if Thread.isMainThread { update() } else { DispatchQueue.main.sync(execute: update) }
    }
    if supportsPreparation {
      pip.presentAsPicture(inPicture: presentation, completionHandler: finishPreparation)
    } else {
      pip.presentAsPicture(inPicture: presentation)
      finishPreparation()
    }
    syncPIPPlaybackState()
    if sourceWindow != nil, Preference.bool(for: .pauseWhenPip) {
      player.pause()
    }

    player.events.emit(.pipChanged, data: true)
    NotificationCenter.default.post(name: .iinaPIPStatusChanged, object: self, userInfo: ["enable": true])
  }

  func exitPIP() {
    guard pipStatus == .inPIP else { return }
    prepareForPIPClosure(pip)
    // Prod Swift to pick the dismiss(_ viewController: NSViewController)
    // overload over dismiss(_ sender: Any?). A change in the way implicitly
    // unwrapped optionals are handled in Swift means that the wrong method
    // is chosen in this case. See https://bugs.swift.org/browse/SR-8956.
    pip.dismiss(pipVideo!)
  }

  func doneExitingPIP() {
    pipStatus = .notInPIP
    addVideoViewToWindow()
    relocateOperationFeedback(to: videoViewContainer)
    window?.contentView?.layoutSubtreeIfNeeded()
    oscFloatingView.updatePosition()
    videoView.prepareForPIPDisplay()
    videoView.videoLayer.isHostedInPIP = false

    let revealUI = pipReturnWindowAlpha != nil
    if let alpha = pipReturnWindowAlpha { window?.alphaValue = alpha }
    pipReturnWindowAlpha = nil
    if isWindowHidden { window?.makeKeyAndOrderFront(self) }
    if revealUI { showUI() }

    updateTimer()

    isWindowMiniaturizedDueToPip = false
    isWindowHidden = false
    liveText.requestAnalysis()
    player.events.emit(.pipChanged, data: false)
    NotificationCenter.default.post(name: .iinaPIPStatusChanged, object: self, userInfo: ["enable": false])
  }

  func prepareForPIPClosure(_ pip: PIPViewController) {
    guard pipStatus == .inPIP else { return }
    if let feedback = pipPreparationFeedback { endOperationFeedback(feedback) }
    pipPreparationFeedback = nil
    guard let window else { return }
    // This is called right before we're about to close the PIP
    pipStatus = .intermediate
    if isWindowHidden {
      // Native PiP can activate the destination before flyback finishes.
      // Reveal it only after the live video has been reattached in pipDidClose.
      pipReturnWindowAlpha = window.alphaValue
      window.alphaValue = 0
      prepareUIForPIPReturn()
    }

    // Hide the overlay view preemptively, to prevent any issues where it does
    // not hide in time and ends up covering the video view (which will be added
    // to the window under everything else, including the overlay).
    pipOverlayView.isHidden = true

    // Set frame to animate back to
    window.contentView?.layoutSubtreeIfNeeded()
    pip.replacementRect = videoViewContainer.convert(videoViewContainer.bounds, to: nil)
    pip.replacementWindow = window

    // Bring the window to the front and deminiaturize it
    NSApp.activate(ignoringOtherApps: true)
    window.deminiaturize(pip)
  }

  private func prepareUIForPIPReturn() {
    destroyTimer()
    // Invalidate an old hide/show completion before resetting its starting state.
    uiAnimationGeneration += 1
    animationState = .hidden
    hideSeekPreview()
    fadeableViews.forEach { view in
      if view === titleBarView {
        titleBarView.setRevealed(false, animated: false)
      } else {
        view.alphaValue = 0
        if let button = view as? NSButton, standardWindowButtons.contains(button) {
          view.alphaValue = 1e-100
        } else {
          view.isHidden = true
        }
      }
    }
    window?.contentView?.layoutSubtreeIfNeeded()
  }

  func pipWillClose(_ pip: PIPViewController) {
    prepareForPIPClosure(pip)
  }

  func pipDidClose(_ pip: PIPViewController) {
    doneExitingPIP()
  }

  func pipActionPlay(_ pip: PIPViewController) {
    player.resume()
  }

  func pipActionPause(_ pip: PIPViewController) {
    player.pause()
  }

  func pipActionStop(_ pip: PIPViewController) {
    // Stopping PIP pauses playback
    player.pause()
  }

  func pipAction(_ pip: PIPViewController, skipInterval interval: TimeInterval) {
    player.seek(relativeSecond: interval, option: .relative)
  }

  func syncPIPPlaybackState() {
    guard pipStatus == .inPIP,
          pip.responds(to: NSSelectorFromString("updatePlaybackStateUsingBlock:")) else { return }
    let playing = player.info.state == .playing
    let elapsed = player.info.videoPosition?.second ?? 0
    let duration = player.info.videoDuration?.second ?? 0
    pip.updatePlaybackState { state in
      state.contentType = 1
      state.contentDuration = duration
      state.setPlaybackRate(playing ? player.info.playSpeed : 0, elapsedTime: elapsed, timeControlStatus: playing ? 2 : 0)
    }
  }
}
