let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var checks = 0
func check(_ condition: Bool, _ message: String) {
  precondition(condition, message)
  checks += 1
  print("PASS: \(message)")
}
let model = ValueModel()
let item = SettingsItem.SwitchWithInput().step(1).range(0...4, allowsFloats: true)
  .trailingLabel(.seconds)
  .bindInputToCustom { $0.bind(.value, to: model, withKeyPath: "value") }
let views = item.getValueViews()
let stack = views[0] as! NSStackView
let field = stack.arrangedSubviews[0] as! NSTextField
let stepper = stack.arrangedSubviews[1] as! NSStepper
let toggle = views[2] as! AccentSwitch
item.initBinding()
item.switchChanged(toggle)
check(!field.isEnabled && !stepper.isEnabled, "off disables both input and stepper")
stepper.isEnabled = true
check(!stepper.isEnabled, "parent enabling cannot bypass the off switch")
toggle.state = .on
item.switchChanged(toggle)
check(field.isEnabled && stepper.isEnabled, "on enables both input and stepper")
check(stepper.increment == 1, "increment is one second")
func step(_ delta: Double) {
  stepper.doubleValue += delta
  app.sendAction(stepper.action!, to: stepper.target, from: stepper)
}
step(1)
check(field.doubleValue == 3.5 && model.value == 3.5, "up preserves fractional part and updates bound preference")
step(1)
check(field.doubleValue == 4 && model.value == 4, "upper bound clamps the saved value")
step(-1)
check(field.doubleValue == 3 && model.value == 3, "down works immediately after a clamped increment")
field.doubleValue = 0
step(-1)
check(field.doubleValue == 0 && model.value == 0, "lower bound clamps at zero")
field.doubleValue = 1.25
step(1)
check(field.doubleValue == 2.25 && model.value == 2.25, "step starts from the latest typed value")
toggle.state = .off
item.switchChanged(toggle)
check(!field.isEnabled && !stepper.isEnabled, "switching off again disables both")
let plain = SettingsItem.SwitchWithInput().getValueViews()
check(plain.count == 2 && plain[0] is NSTextField, "existing switch inputs keep their layout without opting in")
field.unbind(.value)
print("Completed \(checks) native binding and stepper checks; surrounding settings services are stubs.")
