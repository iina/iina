import AppKit
import Darwin
setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message); checks += 1; print("PASS:", message)
}
let original = MPVFilter(rawString: "crop=800:400")!, replacement = MPVFilter(rawString: "crop=700:300")!
func fixture(_ type: String = MPVProperty.vf) -> (MainWindowController, FilterWindowController) {
  let main = MainWindowController(), filter = FilterWindowController(type)
  PlayerCore.lastActive = main.player
  main.player.mpv.lists[type] = [original]
  filter.reloadTable()
  return (main, filter)
}
func dispose(_ main: MainWindowController, _ filter: FilterWindowController) { filter.window?.close(); main.window?.close() }

let blocked: [(String, (MainWindowController) -> Void)] = [
  ("Crop/Delogo", { $0.interactiveMode.isActive = true }),
  ("geometry transition", { $0.isCropTransitionInProgress = true }),
  ("loading", { $0.player.info.state = .loading }),
  ("stopping", { $0.player.info.state = .stopping }),
  ("idle", { $0.player.info.state = .idle }),
  ("shutdown", { $0.player.info.state = .shuttingDown }),
  ("missing handle", { $0.player.mpv.mpv = nil })
]
for (name, configure) in blocked {
  let (main, filter) = fixture()
  configure(main)
  filter.setFilters()
  check(main.player.mpv.mutations.isEmpty, "setFilters refuses \(name)")
  check(!filter.addFilter(replacement) && filter.filters == [original], "addFilter refuses \(name) before local changes")
  filter.removeFilterAction(NSButton())
  check(main.player.mpv.mutations.isEmpty, "remove action refuses \(name)")
  let toggle = NSButton(); toggle.state = .on
  filter.toggleSavedFilterAction(toggle)
  toggle.state = .off; filter.toggleSavedFilterAction(toggle)
  check(main.player.mpv.mutations.isEmpty, "both saved-filter toggle paths refuse \(name)")
  filter.tableView(filter.currentFiltersTableView, setObjectValue: replacement.stringFormat,
                   for: NSTableColumn(identifier: .value), row: 0)
  check(main.player.mpv.mutations.isEmpty && filter.filters == [original], "table edit refuses \(name) before replacing its model")
  filter.addFilterAction(NSButton())
  check((filter.window as! TestWindow).sheetStarts == 0, "new-filter sheet cannot start during \(name)")
  filter.updateButtons()
  check(!filter.removeButton.isEnabled, "remove button matches \(name) eligibility")
  dispose(main, filter)
}

for type in [MPVProperty.vf, MPVProperty.af] {
  for operation in ["set", "add", "remove", "toggle-on", "toggle-off", "edit"] {
    let (main, filter) = fixture(type)
    if type == MPVProperty.af { main.interactiveMode.isActive = true }
    switch operation {
    case "set": filter.setFilters()
    case "add": check(filter.addFilter(replacement), "normal \(type) add succeeds")
    case "remove": filter.removeFilterAction(NSButton())
    case "toggle-on": let button = NSButton(); button.state = .on; filter.toggleSavedFilterAction(button)
    case "toggle-off": let button = NSButton(); button.state = .off; filter.toggleSavedFilterAction(button)
    default: filter.tableView(filter.currentFiltersTableView, setObjectValue: replacement.stringFormat,
                               for: NSTableColumn(identifier: .value), row: 0)
    }
    check(main.player.mpv.mutations.count == 1, "valid \(type) \(operation) reaches exactly one engine mutation")
    dispose(main, filter)
  }
}
for row in [-1, 500] {
  let (main, filter) = fixture()
  filter.currentFiltersTableView.fixtureRow = row; filter.savedFiltersTableView.fixtureRow = row
  filter.removeFilterAction(NSButton()); filter.toggleSavedFilterAction(NSButton())
  filter.tableView(filter.currentFiltersTableView, setObjectValue: replacement.stringFormat,
                   for: NSTableColumn(identifier: .value), row: row)
  filter.updateButtons()
  check(main.player.mpv.mutations.isEmpty && filter.filters == [original] && !filter.removeButton.isEnabled,
        "stale row \(row) is harmless for every touched table mutation")
  dispose(main, filter)
}

for attack in ["editor", "transition", "generation", "player", "stopped", "handle", "cancel"] {
  let (main, filter) = fixture(), sheet = NewFilterSheetViewController(filter)
  filter.addFilterAction(NSButton())
  check((filter.window as! TestWindow).sheetStarts == 1, "deferred attack \(attack) starts from an eligible sheet")
  var other: MainWindowController?
  switch attack {
  case "editor": main.interactiveMode.isActive = true
  case "transition": main.isCropTransitionInProgress = true
  case "generation": main.player.info.trackSelectionGeneration += 1
  case "player": other = MainWindowController(); PlayerCore.lastActive = other!.player
  case "stopped": main.player.info.state = .idle
  case "handle": main.player.mpv.mpv = nil
  default: sheet.sheetCancelBtnAction(NSButton())
  }
  sheet.sheetAddBtnAction(NSButton())
  check(main.player.mpv.mutations.isEmpty && (other?.player.mpv.mutations.isEmpty ?? true) && main.player.osds == 0,
        "actual deferred Add callback rejects changed \(attack) ownership")
  check(!filter.addFilterFromSheet(replacement, name: "Late"), "deferred \(attack) attempt clears its captured target")
  other?.window?.close(); dispose(main, filter)
}
for type in [MPVProperty.vf, MPVProperty.af] {
  let (main, filter) = fixture(type), sheet = NewFilterSheetViewController(filter)
  filter.addFilterAction(NSButton())
  if type == MPVProperty.af { main.interactiveMode.isActive = true }
  sheet.sheetAddBtnAction(NSButton())
  check(main.player.mpv.mutations == ["add:" + type] && main.player.osds == 1,
        "valid deferred \(type) apply mutates and reports on its captured player")
  dispose(main, filter)
}

do {
  let (main, filter) = fixture(), handler = MainMenuActionHandler(main.player)
  main.interactiveMode.isActive = true
  for type in [MPVTrack.TrackType.video, .audio, .sub, .secondSub] {
    for tuple in [false, true] {
      let item = NSMenuItem(title: "Track", action: #selector(handler.menuChangeTrack(_:)), keyEquivalent: "")
      let track = MPVTrack(id: tuple ? 1 : 0, type: type)
      item.representedObject = tuple ? (track, type) as Any : track as Any
      item.target = handler
      let menu = NSMenu(); menu.addItem(item); menu.update()
      check(item.isEnabled == (type != .video), "native menu validates \(type) \(tuple ? "track tuple" : "None track") during editor")
    }
  }
  let music = NSMenuItem(title: "Music", action: #selector(main.menuSwitchToMiniPlayer(_:)), keyEquivalent: "")
  let delogo = NSMenuItem(title: "Delogo", action: #selector(main.menuSetDelogo(_:)), keyEquivalent: "")
  music.target = main; delogo.target = main
  let menu = NSMenu(); menu.addItem(music); menu.addItem(delogo); menu.update()
  check(!music.isEnabled && !delogo.isEnabled, "native target validation disables Music and Delogo during editor")
  main.player.info.delogoFilter = original; delogo.state = .on
  main.menuSetDelogo(delogo)
  check(main.player.mpv.mutations.isEmpty && main.player.info.delogoFilter == original,
        "direct Delogo removal cannot bypass editor ownership")
  main.interactiveMode.isActive = false
  menu.update()
  check(music.isEnabled && delogo.isEnabled, "native Music/Delogo menu restores regular actions after editor")
  main.menuSetDelogo(delogo)
  check(main.player.mpv.mutations == ["remove:vf"] && main.player.info.delogoFilter == nil, "regular Delogo removal remains available")
  main.isCropTransitionInProgress = true; menu.update()
  check(!music.isEnabled && !delogo.isEnabled, "native Music/Delogo menu respects geometry transition")
  main.isCropTransitionInProgress = false; main.pipStatus = .inPIP; menu.update()
  check(!music.isEnabled && !delogo.isEnabled, "native Music/Delogo entry respects PiP video ownership")
  main.pipStatus = .notInPIP; main.player.info.state = .idle; menu.update()
  check(!music.isEnabled && !delogo.isEnabled, "native Music/Delogo entry refuses idle playback")
  dispose(main, filter)
}
print("Completed \(checks) filter-window and native menu ownership checks.")
