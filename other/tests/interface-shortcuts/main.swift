setbuf(stdout,nil)
let root=CommandLine.arguments[1], output=CommandLine.arguments[2]
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
app.finishLaunching()
var checks=0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  precondition(value(),message); checks += 1; print("PASS: \(message)")
}
let labels=NSDictionary(contentsOfFile:root+"/iina/en.lproj/KeyBinding.strings") as! [String:String]
func binding(_ action: String) -> KeyMapping { KeyMapping(rawKey:"ESC",rawAction:action,isIINACommand:true) }
let alpha=JavascriptPlugin("org.example.alpha","Alpha Tool","Alpha")
let beta=JavascriptPlugin("org.example.beta","Beta Tool","Beta")
JavascriptPlugin.plugins=[alpha,beta,JavascriptPlugin("disabled","Disabled","Disabled",enabled:false),JavascriptPlugin("no-panel","No panel",nil)]
let criteria=KeyBindingDataLoader.load().compactMap { $0 as? TextCriterion }
for command in [IINACommand.escape,.closeSidebars,.showPanel,.hidePanel,.togglePanel,.nextPlugin,.previousPlugin,.openPlugin,.showOSC,.hideOSC,.toggleOSC,.resetOSCPosition,.configureOSCPosition,.openCustomCrop] {
  check(criteria.contains { $0.name==command.rawValue && $0.isIINACommand },"editor exposes \(command.rawValue)")
  check(labels["iina."+command.rawValue] != nil,"English label exists for \(command.rawValue)")
}
let pluginCriterion=criteria.first { $0.name=="open-plugin" }!
check(pluginCriterion.children.map(\.mpvCommandValue)==[alpha.identifier,beta.identifier],"plugin choices use enabled sidebar plugins and stable identifiers")
check((pluginCriterion.children.first as! TextCriterion).localizedName=="Alpha Tool","plugin choice displays its human name")
check(KeyBindingTranslator.string(fromCriteria:[pluginCriterion,pluginCriterion.children[1]])=="@iina open-plugin org.example.beta","editor serializes the plugin identifier rather than its position or name")
let show=criteria.first { $0.name=="show-panel" }!
for panel in IINACommand.Panel.allCases {
  let child=show.children.first { $0.mpvCommandValue==panel.rawValue }!
  check(KeyBindingTranslator.string(fromCriteria:[show,child])=="@iina show-panel \(panel.rawValue)","editor serializes \(panel.rawValue) panel choice")
}
check(IINACommand.showPanel.acceptsArguments(["layout"]) && !IINACommand.showPanel.acceptsArguments([]) && !IINACommand.showPanel.acceptsArguments(["missing"]),"panel command rejects missing or unknown targets")
check(!IINACommand.openPlugin.acceptsArguments([]) && !IINACommand.openPlugin.acceptsArguments(["a","b"]),"plugin command rejects malformed arguments")
check(binding("escape").usesDefaultEscape,"new contextual Escape is recognized")
check(KeyMapping(rawKey:"ESC",rawAction:"set fullscreen no").usesDefaultEscape,"existing standard fullscreen Escape gains layered behavior")
check(!KeyMapping(rawKey:"ESC",rawAction:"ignore").usesDefaultEscape && !binding("show-osc").usesDefaultEscape,"custom Escape actions retain priority")
let config=KeyMapping.generateInputConf(from:[binding("escape"),binding("show-panel layout"),binding("open-plugin org.example.beta"),binding("configure-osc-position")])
let configPath=output+"/roundtrip.conf"
try config.write(toFile:configPath,atomically:true,encoding:.utf8)
let parsed=KeyMapping.parseInputConf(at:configPath)!
check(parsed.map(\.rawAction)==["escape","show-panel layout","open-plugin org.example.beta","configure-osc-position"] && parsed.allSatisfy(\.isIINACommand),"config save/reload preserves interface commands and arguments")
class EditorFixture: KeyRecordViewController {
  override func loadView() {
    let container=NSView(frame:NSRect(x:0,y:0,width:600,height:300))
    let key=KeyRecordView(), label=NSTextField(), action=NSTextField(), rule=NSRuleEditor()
    [key,label,action,rule].forEach { container.addSubview($0) }
    keyRecordView=key;keyLabel=label;actionTextField=action;ruleEditor=rule
    view=container
  }
}
var editors: [EditorFixture]=[]
for action in ["@iina open-plugin org.example.beta","@iina show-panel layout","@iina close-sidebars","@iina toggle-osc","@iina open-custom-crop"] {
  let editor=EditorFixture(nibName:nil,bundle:nil);editors.append(editor)
  editor.keyCode="Ctrl+Alt+9";editor.action=action;_ = editor.view
  let selected=editor.ruleEditor.criteria(forRow:0) as! [Criterion]
  check(KeyBindingTranslator.string(fromCriteria:selected)==action && editor.action==action,"editing restores graphical criteria for \(action)")
  check(editor.ready,"saved interface binding is ready to edit without re-recording the key")
}
let missingEditor=EditorFixture(nibName:nil,bundle:nil);editors.append(missingEditor)
missingEditor.keyCode="F1";missingEditor.action="@iina open-plugin removed.plugin";_ = missingEditor.view
check(missingEditor.action=="@iina open-plugin removed.plugin","editing a missing plugin preserves the stored raw identifier")
let window=MainWindow(contentRect:NSRect(x:0,y:0,width:500,height:350),styleMask:[.titled],backing:.buffered,defer:false)
window.isReleasedWhenClosed=false
let controller=MainWindowController(window:window)
window.windowController=controller
controller.player.mainWindow=controller
app.activate(ignoringOtherApps: true)
window.makeKeyAndOrderFront(nil)
let activationDeadline = Date().addingTimeInterval(0.3)
while let event = app.nextEvent(matching: .any, until: activationDeadline, inMode: .default, dequeue: true) {
  app.sendEvent(event)
}
check(NSApp.keyWindow===window,"native test window owns keyboard focus")
controller.player.plugins=[PluginInstance(plugin:alpha),PluginInstance(plugin:beta)]
func press(repeatKey: Bool=false, flags:NSEvent.ModifierFlags=[]) -> NSEvent {
  NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:repeatKey,keyCode:53)!
}
PlayerCore.keyBindings=["ESC":binding("escape")]
controller.sidebars.isAnyVisibleOrTransitioning=true
controller.fsState.isFullscreen=true
window.sendEvent(press())
check(controller.sidebars.hiddenCount==1 && controller.fullscreenExits==0,"first native Escape closes sidebar layer while staying fullscreen")
window.sendEvent(press(repeatKey:true))
check(controller.fullscreenExits==0,"held Escape never cascades into fullscreen exit")
window.sendEvent(press())
check(controller.fullscreenExits==1,"next native Escape exits fullscreen when panels are absent")
window.sendEvent(press())
check(controller.fullscreenExits==1,"Escape is harmless without panels or fullscreen")
controller.isCropTransitionInProgress = true
let panelsBeforeCropEscape = controller.sidebars.hiddenCount
window.sendEvent(press())
check(!controller.isCropTransitionInProgress && controller.cropCancellations == 1 && controller.cropGeometryRefreshes == 1,
      "default Escape removes a committed crop cover and restores live window geometry")
check(controller.sidebars.hiddenCount == panelsBeforeCropEscape && controller.fullscreenExits == 1,
      "cancelling crop motion cannot dismiss another UI layer with the same key")
controller.sidebars.isAnyVisibleOrTransitioning=true
controller.interactiveMode.isActive=true
check(!controller.handleDefaultEscape(with:press()),"Custom Crop owns Escape before sidebar dismissal")
check(!controller.handleKeyBinding(binding("close-sidebars")),"interface shortcuts do not bypass an active editor")
controller.interactiveMode.isActive=false
controller.isPluginMenuTracking=true
check(!controller.handleDefaultEscape(with:press()),"plugin popup keeps its local Escape priority")
controller.isPluginMenuTracking=false
controller.isShowingPersistentOSD=true;controller.osdView.consumes=true
let hiddenBefore=controller.sidebars.hiddenCount
window.sendEvent(press())
check(controller.sidebars.hiddenCount==hiddenBefore && controller.osdView.received==1,"persistent OSD consumes Escape before the sidebar layer")
controller.isShowingPersistentOSD=false;controller.osdView.consumes=false
check(!controller.handleDefaultEscape(with:press(flags:.shift)),"modified Escape is not intercepted")
PlayerCore.keyBindings=["ESC":KeyMapping(rawKey:"ESC",rawAction:"ignore")]
check(!controller.handleDefaultEscape(with:press()) && controller.sidebars.hiddenCount==hiddenBefore,"explicit ignore binding bypasses contextual default")
PlayerCore.keyBindings=["ESC":KeyMapping(rawKey:"ESC",rawAction:"set fullscreen no")]
check(controller.handleDefaultEscape(with:press()) && controller.sidebars.hiddenCount==hiddenBefore+1,"legacy standard Escape closes panels before fullscreen")
for panel in IINACommand.Panel.allCases {
  check(controller.handleKeyBinding(binding("show-panel \(panel.rawValue)")),"dispatcher accepts show \(panel.rawValue)")
  check(controller.sidebars.shown.last!.2==false,"show \(panel.rawValue) cannot toggle off")
  check(controller.handleKeyBinding(binding("toggle-panel \(panel.rawValue)")) && controller.sidebars.shown.last!.2,"toggle \(panel.rawValue) retains toggle intent")
  check(controller.handleKeyBinding(binding("hide-panel \(panel.rawValue)")),"dispatcher accepts hide \(panel.rawValue)")
}
check(controller.sidebars.shown.first!.0 == .settings,"settings target routes to settings group")
check(!controller.handleKeyBinding(binding("show-panel invalid")) && !controller.handleKeyBinding(binding("show-panel layout extra")),"dispatcher rejects malformed panel commands")
check(controller.handleKeyBinding(binding("open-plugin org.example.beta")) && controller.sidebars.shown.last!.1==beta.identifier && !controller.sidebars.shown.last!.2,"open-plugin selects stable identity and always shows it")
check(controller.sidebars.pluginView.selectedIdentifiers == [beta.identifier],
      "explicit plugin shortcut uses the selection route that persists the preference")
let shownCount=controller.sidebars.shown.count
check(!controller.handleKeyBinding(binding("open-plugin missing")) && controller.sidebars.shown.count==shownCount,"missing plugin does not open another plugin by accident")
check(controller.sidebars.pluginView.selectedIdentifiers == [beta.identifier],
      "missing plugin shortcut cannot replace the remembered choice")
check(controller.handleKeyBinding(binding("next-plugin")) && controller.handleKeyBinding(binding("previous-plugin")) && controller.sidebars.pluginView.directions==[1,-1],"plugin shortcuts share bidirectional selection route")
check(controller.handleKeyBinding(binding("hide-osc")) && controller.isUIHiddenByOSCClick,"hide OSC uses existing manual hide state")
check(controller.handleKeyBinding(binding("show-osc")) && !controller.isUIHiddenByOSCClick,"show OSC clears manual hide state")
_ = controller.handleKeyBinding(binding("toggle-osc"));check(controller.isUIHiddenByOSCClick,"toggle hides a shown OSC")
_ = controller.handleKeyBinding(binding("toggle-osc"));check(!controller.isUIHiddenByOSCClick,"toggle reveals a hidden OSC")
check(controller.handleKeyBinding(binding("reset-osc-position")) && controller.oscFloatingView.resets==1,"reset shortcut invokes existing floating OSC return")
check(controller.handleKeyBinding(binding("configure-osc-position")) && controller.oscPositionShortcutSheet.presentations==1,"configure opens the shared position editor")
controller.oscPosition = .bottom
check(!controller.handleKeyBinding(binding("reset-osc-position")) && !controller.handleKeyBinding(binding("configure-osc-position")),"floating geometry commands do not modify a docked OSC")
check(controller.handleKeyBinding(binding("open-file")) && controller.legacyCommands==[.openFile],"existing argument-free IINA commands retain dispatch")
check(!controller.handleKeyBinding(binding("open-file extra")),"existing commands do not accept unintended arguments")
controller.sidebars.isAnyVisibleOrTransitioning=true
let dismissalsBeforeCrop=controller.sidebars.hiddenCount
let panelsBeforeCrop=controller.sidebars.shown.count
check(controller.handleKeyBinding(binding("open-custom-crop")),"Custom Crop shortcut is dispatched directly")
check(controller.interactiveMode.entries==1 && controller.interactiveMode.selectedWholeVideo,"shortcut opens the crop editor with full-source selection")
check(controller.sidebars.hiddenCount==dismissalsBeforeCrop && controller.sidebars.isAnyVisibleOrTransitioning,"opening Custom Crop by bind preserves visible sidebars")
check(controller.sidebars.shown.count==panelsBeforeCrop,"crop action does not open settings or another panel")
check(!controller.handleKeyBinding(binding("open-custom-crop")) && controller.interactiveMode.entries==1,"shortcut does not restart an active editor")
controller.interactiveMode.isActive=false
controller.pipStatus = .inPIP
check(!controller.handleKeyBinding(binding("open-custom-crop")),"shortcut cannot enter Crop while video is in PiP")
controller.pipStatus = .notInPIP
check(!controller.handleKeyBinding(binding("open-custom-crop extra")),"Custom Crop action rejects unexpected arguments")
// The existing menu entry retains its own sidebar-dismissal behavior.
controller.sidebars.deferDismissal=true
controller.menuActionHandler.openCustomCrop()
check(controller.interactiveMode.entries==1 && controller.sidebars.hiddenCount==dismissalsBeforeCrop+1,"menu entry still waits for sidebar dismissal")
controller.menuActionHandler.openCustomCrop()
check(controller.sidebars.hiddenCount==dismissalsBeforeCrop+1,"repeated menu request does not duplicate a pending entry")
controller.sidebars.pendingDismissal?();controller.sidebars.pendingDismissal=nil
check(controller.interactiveMode.entries==2,"menu entry opens crop after sidebar dismissal")
controller.interactiveMode.isActive=false
controller.menuActionHandler.openCustomCrop()
controller.sidebars.pendingDismissal=nil
let beforeRetry=controller.sidebars.hiddenCount
controller.menuActionHandler.openCustomCrop()
check(controller.sidebars.hiddenCount==beforeRetry+1,"interrupted menu dismissal does not permanently block another request")
controller.sidebars.pendingDismissal?();controller.sidebars.pendingDismissal=nil
check(controller.interactiveMode.entries==3,"menu crop entry recovers after a cancelled sidebar transition")
window.close()
print("\(checks) interface shortcut checks passed")

final class ArrowTable: NSTableView, NSTableViewDataSource {
  var arrows: [UInt16] = []
  override init(frame: NSRect) {
    super.init(frame: frame)
    addTableColumn(NSTableColumn(identifier: .init("source")))
    dataSource = self
    reloadData()
  }
  required init?(coder: NSCoder) { fatalError() }
  func numberOfRows(in tableView: NSTableView) -> Int { 3 }
  override func keyDown(with event: NSEvent) { arrows.append(event.keyCode) }
}
let arrowWindow = MainWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                             styleMask: [.titled], backing: .buffered, defer: false)
arrowWindow.isReleasedWhenClosed = false
let arrowTable = ArrowTable(frame: arrowWindow.contentView!.bounds)
arrowWindow.contentView!.addSubview(arrowTable)
check(arrowWindow.makeFirstResponder(arrowTable) && arrowWindow.firstResponder === arrowTable,
      "track-table fixture accepts native keyboard focus")
for flags: NSEvent.ModifierFlags in [[], [.shift], [.command], [.option]] {
  for code: UInt16 in 123...126 {
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
      windowNumber: arrowWindow.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    let handled = arrowWindow.performKeyEquivalent(with: event)
    check(handled && arrowTable.arrows.last == code,
          "window routes focused-table arrow \(code) before player equivalents, modifiers \(flags.rawValue), focus \(String(describing: arrowWindow.firstResponder)), received \(arrowTable.arrows)")
  }
}
arrowWindow.close()
print("Focused table routing checks complete: \(checks) total checks.")

controller.interactiveMode.isActive = false
check(controller.handleKeyBinding(KeyMapping(rawKey:"RIGHT",rawAction:"seek 5",isIINACommand:false)) && controller.player.mpv.commands.last == "seek 5",
      "native seek binding forwards the command to the MPV routing boundary; intent is covered by osd-command-routing")
