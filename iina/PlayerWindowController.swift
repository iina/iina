//
//  PlayerWindowController.swift
//  iina
//
//  Created by Yuze Jiang on 2/15/20.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa

class PlayerWindowController: NSWindowController {

  unowned var player: PlayerCore

  /** The playlist and chapter sidebar. */
  lazy var playlistView: PlaylistViewController = {
    let playlistView = PlaylistViewController()
    playlistView.mainWindow = self
    return playlistView
  }()

  var menuActionHandler: MainMenuActionHandler!
  
  var loaded = false
  
  init(playerCore: PlayerCore) {
    self.player = playerCore
    super.init(window: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  internal lazy var followGlobalSeekTypeWhenAdjustSlider: Bool = Preference.bool(for: .followGlobalSeekTypeWhenAdjustSlider)
  
  /** Observers added to `UserDefauts.standard`. */
  internal var notificationObservers: [NotificationCenter: [NSObjectProtocol]] = [:]
  
  @IBOutlet weak var volumeSlider: NSSlider!
  @IBOutlet weak var muteButton: NSButton!
  @IBOutlet weak var playButton: NSButton!
  @IBOutlet weak var playSlider: NSSlider!
  @IBOutlet weak var rightLabel: DurationDisplayTextField!
  @IBOutlet weak var leftLabel: NSTextField!
  
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
    
    updateVolume()
  }
  
  internal func notificationCenter(_ center: NotificationCenter, addObserverForName name: Notification.Name, object: Any? = nil, using block: @escaping (Notification) -> Void) {
    let observer = center.addObserver(forName: name, object: object, queue: .main, using: block)
    notificationObservers[center, default: []].append(observer)
  }

  
  internal func setMaterial(_ theme: Preference.Theme?) {
    guard let window = window, let theme = theme else { return }

    if #available(macOS 10.14, *) {
      window.appearance = NSAppearance(iinaTheme: theme)
    }
    // See override functions for 10.14-
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

}
