let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message); checks += 1; print("PASS: \(message)")
}
func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
let accessiblePlayer = PlayerCore()
check(NSApp.currentEvent == nil, "accessibility regression starts without a mouse event")
for primary in [true, false] {
  let accessible = SubDelayView(player: accessiblePlayer)
  accessible.isPrimary = primary
  accessible.slider.doubleValue = 0
  _ = accessible.slider.accessibilityPerformIncrement()
  let option = primary ? "sub-delay" : "secondary-sub-delay"
  check(accessible.slider.doubleValue > 0 && accessiblePlayer.mpv.getDouble(option) == accessible.slider.doubleValue,
        "standard accessibility increment commits subtitle delay for Primary = \(primary)")
  _ = accessible.slider.accessibilityPerformDecrement()
  check(accessiblePlayer.mpv.getDouble(option) == accessible.slider.doubleValue,
        "standard accessibility decrement commits subtitle delay without an NSEvent")
}
private let accessibleAudio = AudioDelayView(player: accessiblePlayer)
accessibleAudio.slider.doubleValue = 0
_ = accessibleAudio.slider.accessibilityPerformIncrement()
check(accessibleAudio.slider.doubleValue > 0 && accessiblePlayer.scopedAudioDelay() == accessibleAudio.slider.doubleValue,
      "standard accessibility increment commits audio delay without crashing")
_ = accessibleAudio.slider.accessibilityPerformDecrement()
check(accessiblePlayer.scopedAudioDelay() == accessibleAudio.slider.doubleValue, "accessibility decrement commits audio delay")
let player = PlayerCore()
private let controls = SubPositionDelayView(player: player)
let views = descendants(controls)
let popup = SubtitleRoleSelector()
popup.onChange = { primary in controls.setPrimary(primary) }
private let delay = views.compactMap { $0 as? SubDelayView }.first!
let position = views.compactMap { $0 as? NSSlider }.first { $0 !== delay.slider }!
check(delay.input.doubleValue == 0.5 && position.intValue == 90, "Role selector starts with Primary delay and position")
let initial = player.mpv.values
func select(_ tag: Int) {
  popup.selectedSegment = tag
  _ = popup.sendAction(popup.action!, to: popup.target)
}
select(1)
check(!delay.isPrimary && delay.input.doubleValue == -0.7 && position.intValue == 10, "Secondary refreshes both controls from its own engine properties")
check(player.mpv.values == initial, "changing the role selector does not alter playback or processing")
delay.input.doubleValue = -1.2; delay.customEditFinishedAction()
check(player.mpv.values["secondary-sub-delay"] == -1.2 && player.mpv.values["sub-delay"] == 0.5, "editing Secondary delay preserves Primary")
position.intValue = 25; _ = position.sendAction(position.action!, to: position.target)
check(player.mpv.values["secondary-sub-pos"] == 25 && player.mpv.values["sub-pos"] == 90, "editing Secondary position preserves Primary")
delay.resetButtonAction()
check(player.mpv.values["secondary-sub-delay"] == 0 && player.mpv.values["sub-delay"] == 0.5 && player.mpv.values["audio-delay"] == 0.25, "Secondary Reset resets only subtitle delay and preserves audio delay")
select(0)
check(delay.isPrimary && delay.input.doubleValue == 0.5 && position.intValue == 90, "returning to Primary restores its independent values")
delay.resetButtonAction()
check(player.mpv.values["sub-delay"] == 0 && player.mpv.values["audio-delay"] == 0.25, "Primary Reset also leaves audio untouched")
let groups = views.compactMap { $0 as? TrackSettingsGroupView }
check(groups.count == 1 && groups.allSatisfy { $0.menuAnchor is SidebarResetButton }, "Adjustments has one external heading and Reset action")
let containers = views.compactMap { $0 as? SidebarScrollView.Container }
check(!containers.contains { descendants($0).contains { $0 === popup } }, "role selector is outside the combined Adjustments card")
let layoutHost = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 600))
layoutHost.addSubview(controls)
controls.leadingAnchor.constraint(equalTo: layoutHost.leadingAnchor).isActive = true
controls.topAnchor.constraint(equalTo: layoutHost.topAnchor).isActive = true
controls.widthAnchor.constraint(equalToConstant: 360).isActive = true
layoutHost.layoutSubtreeIfNeeded()
let positionCard = containers.first { descendants($0).contains { $0 === position } }!
check(positionCard.frame.height >= 40 && position.frame.width > 200, "Position keeps a visible card and full-width slider after layout")
let reset = groups.first!.menuAnchor as! SidebarResetButton
player.mpv.values["sub-delay"] = 0.8
select(1)
player.mpv.values["secondary-sub-delay"] = -1.2
position.intValue = 40; _ = position.sendAction(position.action!, to: position.target)
reset.performClick(nil)
check(player.mpv.values["secondary-sub-pos"] == 0 && player.mpv.values["secondary-sub-delay"] == 0 && player.mpv.values["sub-pos"] == 90 && player.mpv.values["sub-delay"] == 0.8, "Adjustments Reset restores both Secondary parameters and preserves Primary")
select(0)
reset.performClick(nil)
check(player.mpv.values["sub-pos"] == 100 && player.mpv.values["sub-delay"] == 0, "Adjustments Reset restores both Primary parameters to their defaults")
check(player.mpv.values["audio-delay"] == 0.25, "combined Adjustments Reset leaves audio unchanged")
player.mpv.values["sub-delay"] = 0.6
player.mpv.values["sub-pos"] = 80
player.mpv.values["secondary-sub-delay"] = -0.8
player.mpv.values["secondary-sub-pos"] = 20
let contextValues = player.mpv.values
let roleResetMenu = reset.resetContextMenu!()
check(roleResetMenu.items.count == 1 && player.mpv.values == contextValues, "subtitle Adjustments context has one role action and never resets on opening")
let primaryReset = roleResetMenu.items[0]
_ = NSApp.sendAction(primaryReset.action!, to: primaryReset.target, from: primaryReset)
check(player.mpv.values["sub-delay"] == 0 && player.mpv.values["sub-pos"] == 100 && player.mpv.values["secondary-sub-delay"] == -0.8 && player.mpv.values["secondary-sub-pos"] == 20 && player.mpv.values["audio-delay"] == 0.25, "Primary context reset preserves Secondary and audio")
player.mpv.values["sub-delay"] = 0.4
select(1)
let secondaryResetMenu = reset.resetContextMenu!()
check(secondaryResetMenu.items.count == 1, "Secondary also has no all-tracks action")
let secondaryReset = secondaryResetMenu.items[0]
_ = NSApp.sendAction(secondaryReset.action!, to: secondaryReset.target, from: secondaryReset)
check(player.mpv.values["sub-delay"] == 0.4 && player.mpv.values["secondary-sub-delay"] == 0 && player.mpv.values["secondary-sub-pos"] == 0, "Secondary context reset preserves Primary")
let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 100))
let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 500))
scroll.documentView = content
let offscreenReset = SidebarResetButton(target: nil, action: nil)
content.addSubview(offscreenReset)
offscreenReset.translatesAutoresizingMaskIntoConstraints = true
offscreenReset.frame = NSRect(x: 20, y: 300, width: 50, height: 24)
offscreenReset.resetCursorRects()
check(offscreenReset.bounds.intersection(offscreenReset.visibleRect).isEmpty, "offscreen Reset safely skips an empty cursor rectangle")
player.mpv.values["sub-scale"] = 2
player.mpv.values["sub-font-size"] = 25
player.mpv.values["sub-outline-size"] = 2
player.mpv.strings = ["sub-font": "Changed font", "sub-color": "1/0/0/1", "sub-outline-color": "0/1/0/1", "sub-back-color": "0/0/1/1", "vf": "unrelated"]
let beforeStyleReset = player.mpv.values
player.resetSubtitleStyle()
check(player.mpv.values["sub-scale"] == 1 && player.mpv.values["sub-font-size"] == 48 && player.mpv.values["sub-outline-size"] == 1.75 && player.mpv.strings["sub-font"] == "HelveticaNeue", "Style Reset restores configured font, arbitrary size and border instead of factory defaults")
check(player.mpv.strings["sub-color"] == "0.9/0.8/0.7/1" && player.mpv.strings["sub-outline-color"] == "0.2/0.3/0.4/1" && player.mpv.strings["sub-back-color"] == "0.1/0.1/0.1/0.5", "Style Reset restores all three configured colors")
check(beforeStyleReset.filter { !["sub-scale", "sub-font-size", "sub-outline-size"].contains($0.key) } == player.mpv.values.filter { !["sub-scale", "sub-font-size", "sub-outline-size"].contains($0.key) } && player.mpv.strings["vf"] == "unrelated", "Style Reset preserves both roles' adjustments, audio and video processing")
let untouchedPlayer = PlayerCore()
untouchedPlayer.mpv.values.merge(["sub-scale": 1, "sub-font-size": 48, "sub-outline-size": 1.75]) { _, value in value }
untouchedPlayer.mpv.strings = ["sub-font": "HelveticaNeue", "sub-color": "0.9/0.8/0.7/1", "sub-outline-color": "0.2/0.3/0.4/1", "sub-back-color": "0.1/0.1/0.1/0.5"]
let untouchedStyle = untouchedPlayer.mpv.values
let untouchedColors = untouchedPlayer.mpv.strings
untouchedPlayer.resetSubtitleStyle()
check(untouchedPlayer.mpv.values == untouchedStyle && untouchedPlayer.mpv.strings == untouchedColors, "first Reset on untouched configured Style is a no-op")
let sizePicker = NSPopUpButton()
sizePicker.addItems(withTitles: stride(from: 25, through: 75, by: 5).map(String.init))
selectSubtitleStyleValue(48, in: sizePicker)
check(sizePicker.titleOfSelectedItem == "48" && sizePicker.numberOfItems == 12, "non-preset startup size 48 is visible")
selectSubtitleStyleValue(48, in: sizePicker)
check(sizePicker.numberOfItems == 12, "refreshing a custom size does not duplicate it")
selectSubtitleStyleValue(22.5, in: sizePicker)
check(sizePicker.titleOfSelectedItem == "22.5" && sizePicker.numberOfItems == 12 && !sizePicker.itemTitles.contains("48"), "fractional size outside the presets is preserved and replaces the previous custom entry")
selectSubtitleStyleValue(55, in: sizePicker)
check(sizePicker.titleOfSelectedItem == "55" && sizePicker.numberOfItems == 11, "standard values reuse the existing preset")
let borderPicker = NSPopUpButton()
borderPicker.addItems(withTitles: ["0", "0.25", "0.5", "1", "1.5", "2", "2.5", "3", "4", "5"])
selectSubtitleStyleValue(1.75, in: borderPicker)
check(borderPicker.titleOfSelectedItem == "1.75", "non-preset border width is visible without rounding")
Preference.configured = [:]
player.resetSubtitleStyle()
check(player.mpv.values["sub-font-size"] == 50 && player.mpv.strings["sub-font"] == "Factory font", "unconfigured users still reset to the registered defaults")
// A standalone function keeps its icon in the external heading, while a group
// keeps function icons inside the shared card.
let headingIcon = NSImage(systemSymbolName: "forward.fill", accessibilityDescription: nil)!
let standaloneContent = NSView()
standaloneContent.translatesAutoresizingMaskIntoConstraints = false
standaloneContent.heightAnchor.constraint(equalToConstant: 50).isActive = true
let standaloneReset = SidebarResetButton(target: nil, action: nil)
let standalone = TrackSettingsGroupView(titleKey: "Speed", content: standaloneContent,
                                        titleImage: headingIcon, action: standaloneReset)
let standaloneViews = descendants(standalone)
let standaloneCard = standaloneViews.compactMap { $0 as? SidebarScrollView.Container }.first!
check(!descendants(standaloneCard).contains { $0 is NSImageView || $0 === standaloneReset }, "standalone function icon and single Reset are outside its card")
check(standaloneViews.compactMap { $0 as? NSImageView }.count == 1 && standaloneViews.compactMap { $0 as? SidebarResetButton }.count == 1, "standalone function has one icon and one external Reset")
let framedHost = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
framedHost.addSubview(standalone)
standalone.leadingAnchor.constraint(equalTo: framedHost.leadingAnchor).isActive = true
standalone.topAnchor.constraint(equalTo: framedHost.topAnchor).isActive = true
let frameWidth = standalone.widthAnchor.constraint(equalToConstant: 320)
frameWidth.isActive = true
for width in [320.0, 400.0] {
  frameWidth.constant = width
  framedHost.layoutSubtreeIfNeeded()
  check(abs(standaloneCard.frame.width - width) < 0.1 && standaloneReset.frame.width > 0,
        "shared frame and external Reset fit sidebar width \(width)")
}
check(descendants(controls).allSatisfy { !($0 is CircularActionButton) }, "subtitle Adjustments contains no per-setting reset circles")

Preference.configured = [.subTextFont: "HelveticaNeue", .subTextSize: Float(50), .subBorderSize: Float(2)]
let rolePlayer = PlayerCore()
rolePlayer.resetSubtitleStyle()
rolePlayer.resetSubtitleStyle(forPrimary: false)
private let roleStyle = SubStyleView(player: rolePlayer)
let styleViews = descendants(roleStyle)
let styleSliders = styleViews.compactMap { $0 as? NSSlider }
let stylePickers = styleViews.compactMap { $0 as? NSPopUpButton }
let fontSize = stylePickers.first { $0.itemTitles.contains("50") }!
let outlineSize = stylePickers.first { $0.itemTitles.contains("0.25") }!
let wells = styleViews.compactMap { $0 as? NSColorWell }
let roleNumbers = rolePlayer.mpv.values, roleStrings = rolePlayer.mpv.strings
roleStyle.setPrimary(false)
check(rolePlayer.mpv.values == roleNumbers && rolePlayer.mpv.strings == roleStrings, "switching Style roles never writes engine values")
fontSize.selectItem(withTitle: "30"); _ = fontSize.sendAction(fontSize.action!, to: fontSize.target)
outlineSize.selectItem(withTitle: "4"); _ = outlineSize.sendAction(outlineSize.action!, to: outlineSize.target)
styleSliders[0].doubleValue = 1; _ = styleSliders[0].sendAction(styleSliders[0].action!, to: styleSliders[0].target)
for well in wells {
  well.color = well.tag == 1 ? .green : .red
  _ = well.sendAction(well.action!, to: well.target)
}
rolePlayer.chooseSubFont(forPrimary: false)
roleStyle.setPrimary(true)
Utility.pendingFont?("Georgia")
check(rolePlayer.mpv.values["secondary-sub-font-size"] == 30 && rolePlayer.mpv.values["secondary-sub-outline-size"] == 4 && rolePlayer.mpv.values["secondary-sub-scale"] == 2, "Secondary Style controls update independent size, outline and scale")
check(rolePlayer.mpv.strings["secondary-sub-font"] == "Georgia" && rolePlayer.mpv.strings["sub-font"] == "HelveticaNeue", "font chooser captures the role even if the selector changes before completion")
check(rolePlayer.mpv.values["sub-font-size"] == 50 && rolePlayer.mpv.values["sub-scale"] == 1 && rolePlayer.mpv.values["sub-outline-size"] == 2, "Secondary Style edits preserve every Primary numeric value")
check(["sub-color", "sub-outline-color", "sub-back-color"].allSatisfy { rolePlayer.mpv.strings[$0] == roleStrings[$0] }, "Secondary color wells preserve all Primary colors")
check(fontSize.titleOfSelectedItem == "50" && outlineSize.titleOfSelectedItem == "2" && styleSliders[0].doubleValue == 0, "switching back to Primary refreshes all displayed numeric controls")
roleStyle.setPrimary(false)
check(fontSize.titleOfSelectedItem == "30" && outlineSize.titleOfSelectedItem == "4" && styleSliders[0].doubleValue == 1, "returning to Secondary restores its displayed values")
let primaryBefore = rolePlayer.mpv.values.filter { !$0.key.hasPrefix("secondary-") }
let primaryStringsBefore = rolePlayer.mpv.strings.filter { !$0.key.hasPrefix("secondary-") }
roleStyle.resetStyle()
check(rolePlayer.mpv.values["secondary-sub-font-size"] == 50 && rolePlayer.mpv.values["secondary-sub-outline-size"] == 2 && rolePlayer.mpv.values["secondary-sub-scale"] == 1 && rolePlayer.mpv.strings["secondary-sub-font"] == "HelveticaNeue", "selected Secondary Style Reset restores its startup defaults")
check(rolePlayer.mpv.values.filter { !$0.key.hasPrefix("secondary-") } == primaryBefore && rolePlayer.mpv.strings.filter { !$0.key.hasPrefix("secondary-") } == primaryStringsBefore, "Secondary Style Reset leaves Primary, audio and adjustments intact")
check(popup.segmentCount == 2 && popup.segmentDistribution == .fillEqually && popup.label(forSegment: 0) == "sidebar.primary" && popup.label(forSegment: 1) == "sidebar.secondary", "role selector has two persistent equally sized segments")
check(styleViews.allSatisfy { !($0 is CircularActionButton) }, "Style has no per-setting reset circles")
print("Completed \(checks) production subtitle settings checks.")

let stockPlayer = PlayerCore()
stockPlayer.mpv.supportsIndependentSecondarySubtitleStyle = false
stockPlayer.resetSubtitleStyle()
let stockValues = stockPlayer.mpv.values
let stockStrings = stockPlayer.mpv.strings
stockPlayer.resetSubtitleStyle(forPrimary: false)
stockPlayer.setSubTextSize(70, forPrimary: false)
stockPlayer.setSubScale(2, forPrimary: false)
stockPlayer.setSubFont("Unsupported write", forPrimary: false)
stockPlayer.setSubTextColor("1/0/0/1", forPrimary: false)
check(stockPlayer.mpv.values == stockValues && stockPlayer.mpv.strings == stockStrings,
      "stock engine ignores unsupported independent Secondary style writes and resets")
private let stockStyle = SubStyleView(player: stockPlayer)
stockStyle.setPrimary(false)
stockStyle.resetStyle()
check(stockPlayer.mpv.values == stockValues && stockPlayer.mpv.strings == stockStrings,
      "switching to unsupported Secondary Style cannot mutate Primary or engine properties")
