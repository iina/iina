import Cocoa
typealias AccentSwitch = NSButton
struct SettingsLocalization { enum Key { case seconds } }
struct Preference { enum Key: String { case testInput, testSwitch } }
struct TestUI { func localized(_ key: SettingsLocalization.Key) -> String { "s" } }
fileprivate let ui = TestUI()
class General: NSObject {
  var key: Preference.Key?
  var controlSize: NSControl.ControlSize = .regular
  var renderedDetailView: NSView?
  func setControlSize(_ field: NSTextField) {}
  func getValueViews() -> [NSView] { [] }
  func initBinding() {}
}
extension NSView {
  @discardableResult func size(width: CGFloat) -> Self {
    widthAnchor.constraint(equalToConstant: width).isActive = true
    return self
  }
}
extension Double {
  func clamped(to range: ClosedRange<Double>) -> Double { min(max(self, range.lowerBound), range.upperBound) }
}
class ValueModel: NSObject { @objc dynamic var value: Double = 2.5 }
