import Cocoa

typealias AccentSegmentedControl = NSSegmentedControl
final class Info {
  var state: PlayerState = .paused
  var currentURL: URL? = URL(fileURLWithPath: "/fixture/one.mkv")
  var trackSelectionGeneration = 7
}
final class MainWindow {
  func showSubChooseMenu(forView: NSView) {}
}
final class PlayerCore {
  let info = Info()
  let mainWindow = MainWindow()
  var currentWindow: NSWindow? { nil }
  var attachments: [String] = []
  func loadExternalAudioFile(_ url: URL) { attachments.append("audio") }
  func loadExternalVideoFile(_ url: URL) { attachments.append("video") }
  func loadExternalSubFile(_ url: URL, delay: Bool = false) { attachments.append("sub") }
}
enum Utility {
  static var panels: [(URL) -> Void] = []
  static let playableFileExt: [String] = []
  static let containsSubExt: [String] = []
  static let supportedFileExt: [String: [String]] = ["video": []]
  static func quickOpenPanel(title: String, chooseDir: Bool, dir: URL?,
                            sheetWindow: NSWindow?, allowedFileTypes: [String]?,
                            completion: @escaping (URL) -> Void) { panels.append(completion) }
}
extension String { static let video = "video" }
final class UI {
  func localized(_ value: String) -> String { value }
}
let ui = UI()
final class Actions: NSObject {
  let player: PlayerCore
  init(_ player: PlayerCore) { self.player = player }
  // PRODUCTION_ACTION_0
  // PRODUCTION_ACTION_1
  // PRODUCTION_ACTION_2
  // PRODUCTION_ACTION_3
  // PRODUCTION_ACTION_4
  func invoke(_ index: Int) {
    switch index {
    case 0: loadExternalAudioAction(NSButton())
    case 1: loadExternalVideoAction(NSButton())
    case 2:
      let control = AccentSegmentedControl()
      control.segmentCount = 2; control.selectedSegment = 0
      loadExternalSubAction(control)
    case 3: menuLoadExternalAudio(NSMenuItem())
    default: menuLoadExternalSub(NSMenuItem())
    }
  }
}
var checks = 0
func check(_ condition: Bool, _ message: String) {
  guard condition else { print("FAIL: " + message); exit(1) }
  checks += 1
}
let attachment = URL(fileURLWithPath: "/fixture/external.file")
for index in 0..<5 {
  for state in [PlayerState.loaded, .playing, .paused] {
    let player = PlayerCore(); player.info.state = state
    let actions = Actions(player)
    Utility.panels = []; actions.invoke(index)
    check(Utility.panels.count == 1, "loaded player presents chooser \(index)")
    Utility.panels.removeFirst()(attachment)
    check(player.attachments.count == 1, "unchanged file receives attachment \(index)")
  }
  for state in [PlayerState.loading, .starting, .stopping, .idle, .shuttingDown, .shutDown] {
    let player = PlayerCore(); player.info.state = state
    let actions = Actions(player)
    Utility.panels = []; actions.invoke(index)
    check(Utility.panels.isEmpty && player.attachments.isEmpty, "unavailable state rejects chooser \(index) \(state)")
  }
  for state in [PlayerState.loading, .starting, .stopping, .idle, .shuttingDown, .shutDown] {
    let player = PlayerCore(); let actions = Actions(player)
    Utility.panels = []; actions.invoke(index)
    player.info.state = state
    Utility.panels.removeFirst()(attachment)
    check(player.attachments.isEmpty, "late result cannot attach to unavailable player \(index) \(state)")
  }
  let player = PlayerCore(); let actions = Actions(player)
  Utility.panels = []; actions.invoke(index)
  player.info.trackSelectionGeneration += 1
  player.info.currentURL = URL(fileURLWithPath: "/fixture/two.mkv")
  Utility.panels.removeFirst()(attachment)
  check(player.attachments.isEmpty, "old chooser cannot attach to replacement file \(index)")
  weak var released: PlayerCore?
  do {
    let owned = PlayerCore(); released = owned
    Utility.panels = []; Actions(owned).invoke(index)
  }
  check(released == nil, "chooser does not retain closed player \(index)")
  Utility.panels.removeFirst()(attachment)
}
print("Passed \(checks) attachment chooser lifecycle and generation checks")
