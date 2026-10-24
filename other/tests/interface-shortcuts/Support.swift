import AppKit
import Carbon
import Darwin

extension Array { subscript(at index: Int) -> Element? { indices.contains(index) ? self[index] : nil } }
extension Double { func prettyFormat() -> String { String(self) } }
extension String { func equalsIgnoreCase(_ other: String) -> Bool { caseInsensitiveCompare(other) == .orderedSame } }
extension Notification.Name {
  static let iinaKeyBindingChanged = Self("keyBindingChanged")
  static let iinaKeyBindingInputChanged = Self("keyBindingInputChanged")
}
enum Preference {
  enum Key { case displayKeyBindingRawValues }
  static func bool(for key: Key) -> Bool { false }
}
enum Logger {
  enum Level { case warning, error }
  static func log(_ message: String, level: Level = .warning) {}
}
// Mustache renders unrelated mpv descriptions; interface labels do not use it.
struct Template {
  let string: String
  init(string: String) throws { self.string = string }
  func render(_ values: [String: String]) throws -> String { string }
}
class JavascriptPlugin {
  let identifier: String
  let name: String
  let sidebarTabName: String?
  var enabled: Bool
  init(_ id: String, _ name: String, _ sidebar: String?, enabled: Bool = true) {
    identifier=id; self.name=name; sidebarTabName=sidebar; self.enabled=enabled
  }
  static var plugins: [JavascriptPlugin] = []
}
struct PluginInstance { let plugin: JavascriptPlugin }
struct MPVCommand: RawRepresentable {
  let rawValue: String
  static let abLoop = Self(rawValue: "ab-loop")
  static let quit = Self(rawValue: "quit")
  static let screenshot = Self(rawValue: "screenshot")
}
enum MPVProperty { static let playlistPos = "playlist-pos" }
class MPVFixture {
  var commands: [String] = []
  func getInt(_ property: String) -> Int { 0 }
  func command(rawString: String) -> Int32 { commands.append(rawString); return 0 }
}
class PlayerCore {
  var userSeeks = 0
  func userInitiatedSeek() { userSeeks += 1 }
  static var keyBindings: [String: KeyMapping] = [:]
  var plugins: [PluginInstance] = []
  let mpv = MPVFixture()
  var disableUI = false
  weak var mainWindow: MainWindowController!
  func openScopedCustomCrop() { mainWindow.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true) }
  func screenshot(fromKeyBinding: KeyMapping) -> Bool { true }
}
class SidebarController {
  enum ViewType: Equatable { case settings, playlist, plugins }
  var isAnyVisibleOrTransitioning = false
  var hiddenCount = 0
  var shown: [(ViewType, String?, Bool)] = []
  var hidden: [ViewType] = []
  let pluginView = PluginViewFixture()
  var deferDismissal = false
  var pendingDismissal: (() -> Void)?
  struct Panel {
    enum AnimationState { case willHide }
    let animationState = AnimationState.willHide
  }
  var sideBars: [Panel] { pendingDismissal == nil ? [] : [Panel()] }
  func hideAllSideBars(after: @escaping () -> Void = {}) {
    hiddenCount += 1; isAnyVisibleOrTransitioning = false
    if deferDismissal { pendingDismissal = after } else { after() }
  }
  func hide(_ type: ViewType) { hidden.append(type) }
  func show(sidebar: ViewType, tab: String? = nil, hideIfAlreadyShown: Bool = true) {
    shown.append((sidebar,tab,hideIfAlreadyShown)); isAnyVisibleOrTransitioning = true
  }
  func handlePanelMouseEvent(_ event: NSEvent) -> Bool { false }
}
class PluginViewFixture {
  var directions: [Int] = []
  var selectedIdentifiers: [String] = []
  func switchPlugin(_ direction: Int) { directions.append(direction) }
  func selectPlugin(withIdentifier identifier: String) { selectedIdentifiers.append(identifier) }
}
class FloatingOSCFixture { var resets=0; func resetPosition() { resets += 1 } }
class ModeFixture {
  enum Mode { case crop }
  var isActive=false
  var entries=0
  var selectedWholeVideo=false
  func enter(mode: Mode, selectWholeVideoByDefault: Bool) {
    isActive=true;entries += 1;selectedWholeVideo=selectWholeVideoByDefault
  }
}
class MainMenuActionHandler {
  unowned let player: PlayerCore
  private var isOpeningCustomCrop=false
  init(player: PlayerCore) { self.player=player }
  // PRODUCTION_CROP_ENTRY
}
class OSCPositionSettingsSheetController {
  var presentations=0
  func present(on parent: NSWindow, players: [PlayerCore]) { presentations += 1 }
}
enum OSCPositionConfiguration {
  static func present(on parent: NSWindow, players: [PlayerCore], using controller: OSCPositionSettingsSheetController) {
    controller.present(on: parent, players: players)
  }
}
class OSDView: NSView {
  var consumes = false
  var received=0
  override func performKeyEquivalent(with event: NSEvent) -> Bool { received += 1; return consumes }
}
class TitlebarFixture { func handleBackgroundMouseEvent(_ event: NSEvent) -> Bool { false } }
class BaseController: NSWindowController {
  let player=PlayerCore()
  var legacyCommands: [IINACommand] = []
  func handleIINACommand(_ cmd: IINACommand) { legacyCommands.append(cmd) }
  func handleInterfaceCommand(_ cmd: IINACommand, arguments: [String]) -> Bool { false }
  func log(_ message: String, level: Logger.Level) {}
  func abLoop() {}
  // PRODUCTION_DISPATCH
}
class MainWindowController: BaseController {
  var isCropTransitionInProgress = false
  var cropCancellations = 0
  var cropGeometryRefreshes = 0
  func cancelCropExitTransition() { cropCancellations += 1; isCropTransitionInProgress = false }
  func handleVideoSizeChange(keepWindowSize: Bool) { cropGeometryRefreshes += 1 }
  func cancelWindowDrag() {}
  lazy var menuActionHandler = MainMenuActionHandler(player: player)
  enum PIPStatus { case notInPIP, inPIP }
  var pipStatus=PIPStatus.notInPIP
  let sidebars=SidebarController()
  let interactiveMode=ModeFixture()
  let osdView=OSDView()
  var isPluginMenuTracking=false
  var isShowingPersistentOSD=false
  var titleBarView: TitlebarFixture?
  struct FSState { var isFullscreen=false }
  var fsState=FSState()
  enum AnimationState { case hidden, shown, willHide }
  enum OSCPosition { case floating, bottom }
  var oscPosition=OSCPosition.floating
  var animationState=AnimationState.shown
  var isUIHiddenByOSCClick=false
  let oscFloatingView=FloatingOSCFixture()
  let oscPositionShortcutSheet=OSCPositionSettingsSheetController()
  var fullscreenExits=0
  var timerUpdates=0
  func toggleWindowFullScreen() { fullscreenExits += 1; fsState.isFullscreen.toggle() }
  func showUI() { isUIHiddenByOSCClick=false; animationState = .shown }
  func updateTimer() { timerUpdates += 1 }
  func hideUIFromOSC() { isUIHiddenByOSCClick=true; animationState = .hidden }
  override func keyDown(with event: NSEvent) {
    let key=KeyCodeHelper.normalizeMpv(KeyCodeHelper.mpvKeyCode(from:event))
    if let binding=PlayerCore.keyBindings[key] { _ = handleKeyBinding(binding) }
  }
  // PRODUCTION_ESCAPE
  // PRODUCTION_INTERFACE
}
class MainWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
  override func keyDown(with event: NSEvent) { windowController?.keyDown(with: event) }
  // PRODUCTION_WINDOW_EVENT
  // PRODUCTION_ARROW_KEYS
}

protocol KeyRecordViewDelegate { func keyRecordView(_ view: KeyRecordView, recordedKeyDownWith event: NSEvent) }
class KeyRecordView: NSView { var delegate: KeyRecordViewDelegate? }
