//
//  PlayerWindowController.swift
//  iina
//
//  Created by Yuze Jiang on 2/15/20.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa

class PlayerWindowController: NSWindowController {
  
  internal typealias PK = Preference.Key

  unowned var player: PlayerCore

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
  
  internal var observedPrefKeys: [PK] = [
    .themeMaterial,
    .showRemainingTime,
    .alwaysFloatOnTop,
    .maxVolume,
    .useExactSeek,
    .relativeSeekAmount,
    .volumeScrollAmount,
    .singleClickAction,
    .doubleClickAction,
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
          self.isOntop = newValue
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

    default:
      return
    }
  }
  
  /** Observers added to `UserDefauts.standard`. */
  internal var notificationObservers: [NotificationCenter: [NSObjectProtocol]] = [:]
  
  @IBOutlet weak var volumeSlider: NSSlider!
  @IBOutlet weak var muteButton: NSButton!
  @IBOutlet weak var playButton: NSButton!
  @IBOutlet weak var playSlider: NSSlider!
  @IBOutlet weak var rightLabel: DurationDisplayTextField!
  @IBOutlet weak var leftLabel: NSTextField!
  
  /** Differentiate between single clicks and double clicks. */
  internal var singleClickTimer: Timer?
  internal var mouseExitEnterCount = 0

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
    
    notificationCenter(.default, addObserverForName: .iinaMediaTitleChanged, object: player) { [unowned self] _ in
        self.updateTitle()
    }
    
    rightLabel.mode = Preference.bool(for: .showRemainingTime) ? .remaining : .duration
    
    updateVolume()
    
    observedPrefKeys.forEach { key in
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }
    
    notificationCenter(.default, addObserverForName: .iinaFileLoaded, object: player) { [unowned self] _ in
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
      for (center, observers) in self.notificationObservers {
        for observer in observers {
          center.removeObserver(observer)
        }
      }
    }
  }
  
  internal func notificationCenter(_ center: NotificationCenter, addObserverForName name: Notification.Name, object: Any? = nil, using block: @escaping (Notification) -> Void) {
    let observer = center.addObserver(forName: name, object: object, queue: .main, using: block)
    notificationObservers[center, default: []].append(observer)
  }
  
  // MARK: - Mouse / Trackpad event
  
  override func keyDown(with event: NSEvent) {
    let keyCode = KeyCodeHelper.mpvKeyCode(from: event)
    if let kb = PlayerCore.keyBindings[keyCode] {
      handleKeyBinding(kb)
    } else {
      super.keyDown(with: event)
    }
  }

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
      switch keyBinding.action[0] {
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
  
  override func mouseUp(with event: NSEvent) {
    if event.clickCount == 1 {
      if doubleClickAction == .none {
        performMouseAction(singleClickAction)
      } else {
        singleClickTimer = Timer.scheduledTimer(timeInterval: NSEvent.doubleClickInterval, target: self, selector: #selector(self.performMouseActionLater(_:)), userInfo: singleClickAction, repeats: false)
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
    performMouseAction(Preference.enum(for: .rightClickAction))
  }
  
  override func otherMouseUp(with event: NSEvent) {
    if event.buttonNumber == 2 {
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

  internal func setMaterial(_ theme: Preference.Theme?) {
    guard let window = window, let theme = theme else { return }

    if #available(macOS 10.14, *) {
      window.appearance = NSAppearance(iinaTheme: theme)
    }
    // See overridden functions for 10.14-
  }
  
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
    let percentage = (pos.second / duration.second) * 100
    leftLabel.stringValue = pos.stringRepresentation
    rightLabel.updateText(with: duration, given: pos)
    if andProgressBar {
      playSlider.doubleValue = percentage
      if #available(macOS 10.12.2, *) {
        player.touchBarSupport.touchBarPlaySlider?.setDoubleValueSafely(percentage)
        player.touchBarSupport.touchBarPosLabels.forEach { $0.updateText(with: duration, given: pos) }
      }
    }
  }
  
  func updatePlayButtonState(_ state: NSControl.StateValue) {
    guard loaded else { return }
    playButton.state = state
  }
  
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
  
  /** This method will not set `isOntop`! */
  func setWindowFloatingOnTop(_ onTop: Bool) {
    guard let window = window else { return }
    window.level = onTop ? .iinaFloating : .normal
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
