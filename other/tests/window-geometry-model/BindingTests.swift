var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
  precondition(condition(), label)
  checks += 1
  print("PASS: \(label)")
}
Preference.raw = "640x480+20-30"
fileprivate let binding = GeometryBindings()
let sizeSwitch = SettingsItem.Switch()
let positionSwitch = SettingsItem.Switch()
binding.bindSizeSwitch(sizeSwitch)
binding.bindPositionSwitch(positionSwitch)
binding.updateControls()
check(sizeSwitch.nsSwitch.state == .on && positionSwitch.nsSwitch.state == .on, "bindings reflect independent stored switches without writing")
check(Preference.writes == 0, "programmatic switch synchronization does not fire callbacks")
sizeSwitch.userToggle(false)
check(Preference.raw == "+20-30" && positionSwitch.nsSwitch.state == .on, "external size off leaves position enabled")
var sheet = binding.configurationDraft()
check(!sheet.sizeEnabled && sheet.sizeValue == 640, "shared sheet receives disabled size draft instead of reparsing omissions")
sheet.xValue = 50
binding.save(sheet)
check(Preference.raw == "+50-30" && !binding.configurationDraft().sizeEnabled, "sheet position save keeps disabled size state")
sizeSwitch.userToggle(true)
check(Preference.raw == "640x480+50-30", "re-enabling size restores both original dimensions after position edit")
positionSwitch.userToggle(false)
sheet = binding.configurationDraft()
check(sheet.xValue == 50 && sheet.yValue == 30 && !sheet.positionEnabled, "shared sheet retains disabled position draft")
sheet.sizeValue = 800
binding.save(sheet)
check(Preference.raw == "800x480" && positionSwitch.nsSwitch.state == .off, "sheet size edit retains the other explicit dimension and leaves position disabled")
positionSwitch.userToggle(true)
check(Preference.raw == "800x480+50-30", "position restoration survives independent size editing")
sizeSwitch.userToggle(false)
positionSwitch.userToggle(false)
sheet = binding.configurationDraft()
check(Preference.raw == "" && sheet.sizeValue == 800 && sheet.xValue == 50, "both external switches off preserve cached draft fields")
binding.save(sheet)
sizeSwitch.userToggle(true)
positionSwitch.userToggle(true)
check(Preference.raw == "800x480+50-30", "no-op sheet save while both disabled does not lose either size axis")
Preference.set("x50%-10%+25%", for: .initialWindowSizePosition)
let external = binding.configurationDraft()
check(external.sizeDimension == .height && external.sizeValue == 50 && external.xAnchor == .right && external.yAnchor == .bottom,
      "external raw preference replacement refreshes shared state")
check(sizeSwitch.nsSwitch.state == .on && positionSwitch.nsSwitch.state == .on, "observer refresh synchronizes both displayed switches")
let writesBeforeNoOp = Preference.writes
binding.updateControls()
check(Preference.writes == writesBeforeNoOp, "observer update has no recursive preference writes")
Preference.set("unrecognized geometry", for: .initialWindowSizePosition)
binding.save(binding.configurationDraft())
check(Preference.raw == "unrecognized geometry", "shared no-op Save retains unsupported raw geometry")
check(sizeSwitch.nsSwitch.state == .off && positionSwitch.nsSwitch.state == .off, "unsupported raw geometry safely disables independent switches")
Preference.set("640+10-20", for: .initialWindowSizePosition)
sizeSwitch.userToggle(false)
positionSwitch.userToggle(false)
var disabled = binding.configurationDraft()
disabled.sizeValue = 900
disabled.xValue = 120
disabled.yValue = 80
binding.save(disabled)
fileprivate let reopened = GeometryBindings()
let reopenedSize = SettingsItem.Switch()
let reopenedPosition = SettingsItem.Switch()
reopened.bindSizeSwitch(reopenedSize)
reopened.bindPositionSwitch(reopenedPosition)
reopened.updateControls()
check(Preference.raw == "" && !reopened.configurationDraft().sizeEnabled && !reopened.configurationDraft().positionEnabled,
      "saving configured values does not enable either feature")
check(reopened.configurationDraft().sizeValue == 900 && reopened.configurationDraft().xValue == 120,
      "disabled configured values survive a new bindings instance")
reopenedSize.userToggle(true)
reopenedPosition.userToggle(true)
check(Preference.raw == "900+120-80", "re-enabling after reopening applies configured values")
var free = reopened.configurationDraft()
free.prepareIndependentSize(screenSize: NSSize(width: 1800, height: 1050), aspect: 16 / 9)
free.widthValue = 600
free.widthUnit = .points
free.heightValue = 70
free.heightUnit = .percent
reopened.save(free)
check(Preference.raw == "600x70%+120-80", "shared binding persists both independent dimensions and mixed units")
reopenedSize.userToggle(false)
fileprivate let freeReopened = GeometryBindings()
let freeSizeSwitch = SettingsItem.Switch()
freeReopened.bindSizeSwitch(freeSizeSwitch)
freeReopened.updateControls()
var restored = freeReopened.configurationDraft()
restored.prepareIndependentSize(screenSize: NSSize(width: 1800, height: 1050), aspect: 16 / 9)
check(restored.widthValue == 600 && restored.heightValue == 70 && restored.heightUnit == .percent,
      "independent dimensions survive disabling size and reopening the bindings")
freeSizeSwitch.userToggle(true)
check(Preference.raw == "600x70%+120-80", "re-enabling size restores the complete independent pair")
print("Completed \(checks) extracted production GeometryBindings integration checks with preference/switch doubles; no UI or production preferences accessed.")
