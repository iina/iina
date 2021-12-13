//
//  PlayerWindowController.swift
//  iina
//
//  Created by Yuze Jiang on 2/15/20.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa

class PlayerWindowController: NSWindowController, NSWindowDelegate {

  unowned var player: PlayerCore
  
  var videoView: VideoView {
    fatalError("Subclass must implement")
  }

  var menuActionHandler: MainMenuActionHandler!
  
  var isOntop = false {
    didSet {
      player.mpv.setFlag(MPVOption.Window.ontop, isOntop)
    }
  }
  var loaded = false
  
  init(playerCore: PlayerCore) {
    self.player = playerCore
    super.init(window: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  // Cached user defaults values
  internal lazy var followGlobalSeekTypeWhenAdjustSlider: Bool = Preference.bool(for: .followGlobalSeekTypeWhenAdjustSlider)
  internal lazy var useExtractSeek: Preference.SeekOption = Preference.enum(for: .useExactSeek)
  internal lazy var relativeSeekAmount: Int = Preference.integer(for: .relativeSeekAmount)
  internal lazy var volumeScrollAmount: Int = Preference.integer(for: .volumeScrollAmount)
  internal lazy var singleClickAction: Preference.MouseClickAction = Preference.enum(for: .singleClickAction)
  internal lazy var doubleClickAction: Preference.MouseClickAction = Preference.enum(for: .doubleClickAction)
  internal lazy var horizontalScrollAction: Preference.ScrollAction = Preference.enum(for: .horizontalScrollAction)
  internal lazy var verticalScrollAction: Preference.ScrollAction = Preference.enum(for: .verticalScrollAction)
  
  internal var observedPrefKeys: [Preference.Key] = [
    .themeMaterial,
    .showRemainingTime,
    .alwaysFloatOnTop,
    .maxVolume,
    .useExactSeek,
    .relativeSeekAmount,
    .volumeScrollAmount,
    .singleClickAction,
    .doubleClickAction,
    .horizontalScrollAction,
    .verticalScrollAction,
    .playlistShowMetadata,
    .playlistShowMetadataInMusicMode,
  ]
  
  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath, let change = change else { return }
    
    switch keyPath {
    case PK.themeMaterial.rawValue:
      if let newValue = change[.newKey] as? Int {
        setMaterial(Preference.Theme(rawValue: newValue))
      }
    case PK.showRemainingTime.rawValue:
      if let newValue = change[.newKey] as? Bool {
        rightLabel.mode = newValue ? .remaining : .duration
      }
    case PK.alwaysFloatOnTop.rawValue:
      if let newValue = change[.newKey] as? Bool {
        if player.info.isPlaying {
          setWindowFloatingOnTop(newValue)
        }
      }
    case PK.maxVolume.rawValue:
      if let newValue = change[.newKey] as? Int {
        volumeSlider.maxValue = Double(newValue)
        if player.mpv.getDouble(MPVOption.Audio.volume) > Double(newValue) {
          player.mpv.setDouble(MPVOption.Audio.volume, Double(newValue))
        }
      }
    case PK.useExactSeek.rawValue:
      if let newValue = change[.newKey] as? Int {
        useExtractSeek = Preference.SeekOption(rawValue: newValue)!
      }
    case PK.relativeSeekAmount.rawValue:
      if let newValue = change[.newKey] as? Int {
        relativeSeekAmount = newValue.clamped(to: 1...5)
      }
    case PK.volumeScrollAmount.rawValue:
      if let newValue = change[.newKey] as? Int {
        volumeScrollAmount = newValue.clamped(to: 1...4)
      }
    case PK.singleClickAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        singleClickAction = Preference.MouseClickAction(rawValue: newValue)!
      }
    case PK.doubleClickAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        doubleClickAction = Preference.MouseClickAction(rawValue: newValue)!
      }
    case PK.playlistShowMetadata.rawValue, PK.playlistShowMetadataInMusicMode.rawValue:
      if player.isPlaylistVisible {
        player.mainWindow.playlistView.playlistTableView.reloadData()
      }
    default:
      return
    }
  }

  @IBOutlet weak var volumeSlider: NSSlider!
  @IBOutlet weak var muteButton: NSButton!
  @IBOutlet weak var playButton: NSButton!
  @IBOutlet weak var playSlider: NSSlider!
  @IBOutlet weak var rightLabel: DurationDisplayTextField!
  @IBOutlet weak var leftLabel: DurationDisplayTextField!

  /** Differentiate between single clicks and double clicks. */
  internal var singleClickTimer: Timer?
  internal var mouseExitEnterCount = 0

  // Scroll direction

  /** The direction of current scrolling event. */
  enum ScrollDirection {
    case horizontal
    case vertical
  }

  internal var scrollDirection: ScrollDirection?

  /** We need to pause the video when a user starts seeking by scrolling.
   This property records whether the video is paused initially so we can
   recover the status when scrolling finished. */
  private var wasPlayingBeforeSeeking = false
  
  /** Subclasses should set these value to true if the mouse is in some
   special views (e.g. volume slider, play slider) before calling
   `super.scrollWheel()` and set them back to false after calling
   `super.scrollWheel()`.*/
  internal var seekOverride = false
  internal var volumeOverride = false

  internal var mouseActionDisabledViews: [NSView?] {[]}

  // MARK: - Initiaization

  override func windowDidLoad() {
    super.windowDidLoad()
    loaded = true
    
    guard let window = window else { return }
    
    // Insert `menuActionHandler` into the responder chain
    menuActionHandler = MainMenuActionHandler(playerCore: player)
    let responder = window.nextResponder
    window.nextResponder = menuActionHandler
    menuActionHandler.nextResponder = responder
    
    window.initialFirstResponder = nil
    window.titlebarAppearsTransparent = true
    
    setMaterial(Preference.enum(for: .themeMaterial))
    
    addObserver(to: .default, forName: .iinaMediaTitleChanged, object: player) { [unowned self] _ in
        self.updateTitle()
    }

    leftLabel.mode = .current
    rightLabel.mode = Preference.bool(for: .showRemainingTime) ? .remaining : .duration

    updateVolume()

    observedPrefKeys.forEach { key in
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }

    addObserver(to: .default, forName: .iinaFileLoaded, object: player) { [unowned self] _ in
      self.updateTitle()
    }

    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil, using: { [unowned self] _ in
      if Preference.bool(for: .pauseWhenGoesToSleep) {
        self.player.pause()
      }
    })
  }

  deinit {
    ObjcUtils.silenced {
      for key in self.observedPrefKeys {
        UserDefaults.standard.removeObserver(self, forKeyPath: key.rawValue)
      }
    }
  }

  internal func addObserver(to notificationCenter: NotificationCenter, forName name: Notification.Name, object: Any? = nil, using block: @escaping (Notification) -> Void) {
    notificationCenter.addObserver(forName: name, object: object, queue: .main, using: block)
  }

  internal func setMaterial(_ theme: Preference.Theme?) {
    guard let window = window, let theme = theme else { return }

    if #available(macOS 10.14, *) {
      window.appearance = NSAppearance(iinaTheme: theme)
    }
    // See overridden functions for 10.14-
  }

  // MARK: - Mouse / Trackpad events


  @discardableResult
  func handleKeyBinding(_ keyBinding: KeyMapping) -> Bool {
    if keyBinding.isIINACommand {
      // - IINA command
      if let iinaCommand = IINACommand(rawValue: keyBinding.rawAction) {
        handleIINACommand(iinaCommand)
        return true
      } else {
        Logger.log("Unknown iina command \(keyBinding.rawAction)", level: .error)
        return false
      }
    } else {
      // - mpv command
      let returnValue: Int32
      // execute the command
      switch keyBinding.action.first! {
      case MPVCommand.abLoop.rawValue:
        player.abLoop()
        returnValue = 0
      default:
        returnValue = player.mpv.command(rawString: keyBinding.rawAction)
      }
      if returnValue == 0 {
        return true
      } else {
        Logger.log("Return value \(returnValue) when executing key command \(keyBinding.rawAction)", level: .error)
        return false
      }
    }
  }

  override func keyDown(with event: NSEvent) {
    let keyCode = KeyCodeHelper.mpvKeyCode(from: event)
    if let kb = PlayerCore.keyBindings[keyCode] {
      handleKeyBinding(kb)
    } else {
      super.keyDown(with: event)
    }
  }

  override func mouseUp(with event: NSEvent) {
    guard !isMouseEvent(event, inAnyOf: mouseActionDisabledViews) else { return }
    if event.clickCount == 1 {
      if doubleClickAction == .none {
        performMouseAction(singleClickAction)
      } else {
        singleClickTimer = Timer.scheduledTimer(timeInterval: NSEvent.doubleClickInterval, target: self, selector: #selector(performMouseActionLater), userInfo: singleClickAction, repeats: false)
        mouseExitEnterCount = 0
      }
    } else if event.clickCount == 2 {
      if let timer = singleClickTimer {
        timer.invalidate()
        singleClickTimer = nil
      }
      performMouseAction(doubleClickAction)
    }
  }

  override func rightMouseUp(with event: NSEvent) {
    guard !isMouseEvent(event, inAnyOf: mouseActionDisabledViews) else { return }
    performMouseAction(Preference.enum(for: .rightClickAction))
  }

  override func otherMouseUp(with event: NSEvent) {
    guard !isMouseEvent(event, inAnyOf: mouseActionDisabledViews) else { return }
    if event.type == .otherMouseUp {
      performMouseAction(Preference.enum(for: .middleClickAction))
    } else {
      super.otherMouseUp(with: event)
    }
  }

  internal func performMouseAction(_ action: Preference.MouseClickAction) {
    switch action {
    case .pause:
      player.togglePause()
    default:
      break
    }
  }
  
  override func scrollWheel(with event: NSEvent) {
    let isMouse = event.phase.isEmpty
    let isTrackpadBegan = event.phase.contains(.began)
    let isTrackpadEnd = event.phase.contains(.ended)

    // determine direction

    if isMouse || isTrackpadBegan {
      if event.scrollingDeltaX != 0 {
        scrollDirection = .horizontal
      } else if event.scrollingDeltaY != 0 {
        scrollDirection = .vertical
      }
    } else if isTrackpadEnd {
      scrollDirection = nil
    }

    let scrollAction: Preference.ScrollAction
    if seekOverride {
      scrollAction = .seek
    } else if volumeOverride {
      scrollAction = .volume
    } else {
      scrollAction = scrollDirection == .horizontal ? horizontalScrollAction : verticalScrollAction
      // show volume popover when volume seek begins and hide on end
      if let miniPlayer = self as? MiniPlayerWindowController, scrollAction == .volume {
        miniPlayer.handleVolumePopover(isTrackpadBegan, isTrackpadEnd, isMouse)
      }
    }

    // pause video when seek begins

    if scrollAction == .seek && isTrackpadBegan {
      // record pause status
      if player.info.isPlaying {
        player.pause()
        wasPlayingBeforeSeeking = true
      }
    }

    if isTrackpadEnd && wasPlayingBeforeSeeking {
      // only resume playback when it was playing before seeking
      if wasPlayingBeforeSeeking {
        player.resume()
      }
      wasPlayingBeforeSeeking = false
    }

    // handle the delta value

    let isPrecise = event.hasPreciseScrollingDeltas
    let isNatural = event.isDirectionInvertedFromDevice

    var deltaX = isPrecise ? Double(event.scrollingDeltaX) : event.scrollingDeltaX.unifiedDouble
    var deltaY = isPrecise ? Double(event.scrollingDeltaY) : event.scrollingDeltaY.unifiedDouble * 2

    if isNatural {
      deltaY = -deltaY
    } else {
      deltaX = -deltaX
    }

    let delta = scrollDirection == .horizontal ? deltaX : deltaY

    // perform action
    
    switch scrollAction {
    case .seek:
      let seekAmount = (isMouse ? AppData.seekAmountMapMouse : AppData.seekAmountMap)[relativeSeekAmount] * delta
      player.seek(relativeSecond: seekAmount, option: useExtractSeek)
    case .volume:
      // don't use precised delta for mouse
      let newVolume = player.info.volume + (isMouse ? delta : AppData.volumeMap[volumeScrollAmount] * delta)
      player.setVolume(newVolume)
      volumeSlider.doubleValue = newVolume
    default:
      break
    }
  }

  /**
   Being called to perform single click action after timeout.

   - SeeAlso:
   mouseUp(with:)
   */
  @objc internal func performMouseActionLater(_ timer: Timer) {
    guard let action = timer.userInfo as? Preference.MouseClickAction else { return }
    if mouseExitEnterCount >= 2 && action == .hideOSC {
      // the counter being greater than or equal to 2 means that the mouse re-entered the window
      // `showUI()` must be called due to the movement in the window, thus `hideOSC` action should be cancelled
      return
    }
    performMouseAction(action)
  }
  
  // MARK: - Window delegate: Open / Close
  
  func windowDidOpen() {
    if Preference.bool(for: .alwaysFloatOnTop) {
      setWindowFloatingOnTop(true)
    }
    videoView.startDisplayLink()
  }
  
  // MARK: - Window delegate: Activeness status

  func windowDidBecomeMain(_ notification: Notification) {
    PlayerCore.lastActive = player
    if #available(macOS 10.13, *), RemoteCommandController.useSystemMediaControl {
      NowPlayingInfoManager.updateInfo(withTitle: true)
    }
    NotificationCenter.default.post(name: .iinaMainWindowChanged, object: nil)
  }
  
  func windowDidResignMain(_ notification: Notification) {
    NotificationCenter.default.post(name: .iinaMainWindowChanged, object: nil)
  }

  func windowDidChangeScreen(_ notification: Notification) {
    videoView.updateDisplayLink()
  }

  // MARK: - UI

  @objc
  func updateTitle() {
    fatalError("Must implement in the subclass")
  }
  
  func updateVolume() {
    volumeSlider.doubleValue = player.info.volume
    muteButton.state = player.info.isMuted ? .on : .off
  }
  
  func updatePlayTime(withDuration: Bool, andProgressBar: Bool) {
    guard loaded else { return }
    guard let duration = player.info.videoDuration, let pos = player.info.videoPosition else {
      Logger.fatal("video info not available")
    }
    [leftLabel, rightLabel].forEach { $0.updateText(with: duration, given: pos) }
    if #available(macOS 10.12.2, *) {
      player.touchBarSupport.touchBarPosLabels.forEach { $0.updateText(with: duration, given: pos) }
    }
    if andProgressBar {
      let percentage = (pos.second / duration.second) * 100
      playSlider.doubleValue = percentage
      if #available(macOS 10.12.2, *) {
        player.touchBarSupport.touchBarPlaySlider?.setDoubleValueSafely(percentage)
      }
    }
  }
  
  func updatePlayButtonState(_ state: NSControl.StateValue) {
    guard loaded else { return }
    playButton.state = state
  }

  /** This method will not set `isOntop`! */
  func setWindowFloatingOnTop(_ onTop: Bool, updateOnTopStatus: Bool = true) {
    guard let window = window else { return }
    window.level = onTop ? .iinaFloating : .normal
    if (updateOnTopStatus) {
      self.isOntop = onTop
    }
  }

  // MARK: - IBActions

  @IBAction func volumeSliderChanges(_ sender: NSSlider) {
    let value = sender.doubleValue
    if Preference.double(for: .maxVolume) > 100, value > 100 && value < 101 {
      NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }
    player.setVolume(value)
  }

  @IBAction func playButtonAction(_ sender: NSButton) {
    player.info.isPaused ? player.resume() : player.pause()
  }

  @IBAction func muteButtonAction(_ sender: NSButton) {
    player.toggleMute()
  }

  @IBAction func playSliderChanges(_ sender: NSSlider) {
    guard !player.info.fileLoading else { return }
    let percentage = 100 * sender.doubleValue / sender.maxValue
    player.seek(percent: percentage, forceExact: !followGlobalSeekTypeWhenAdjustSlider)
  }

  internal func handleIINACommand(_ cmd: IINACommand) {
    let appDelegate = (NSApp.delegate! as! AppDelegate)
    switch cmd {
    case .openFile:
      appDelegate.openFile(self)
    case .openURL:
      appDelegate.openURL(self)
    case .flip:
      menuActionHandler.menuToggleFlip(.dummy)
    case .mirror:
      menuActionHandler.menuToggleMirror(.dummy)
    case .saveCurrentPlaylist:
      menuActionHandler.menuSavePlaylist(.dummy)
    case .deleteCurrentFile:
      menuActionHandler.menuDeleteCurrentFile(.dummy)
    case .findOnlineSubs:
      menuActionHandler.menuFindOnlineSub(.dummy)
    case .saveDownloadedSub:
      menuActionHandler.saveDownloadedSub(.dummy)
    default:
      break
    }
  }

  internal func isMouseEvent(_ event: NSEvent, inAnyOf views: [NSView?]) -> Bool {
    return views.filter { $0 != nil }.reduce(false, { (result, view) in
      return result || view!.isMousePoint(view!.convert(event.locationInWindow, from: nil), in: view!.bounds)
    })
  }

}
