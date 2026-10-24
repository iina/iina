let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
setbuf(stdout, nil)
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  precondition(value(), message)
  checks += 1
  print("PASS \(message)")
}

final class CursorRecorder: NSButton {
  var registrations: [(NSRect, NSCursor)] = []
  override func addCursorRect(_ rect: NSRect, cursor: NSCursor) { registrations.append((rect, cursor)) }
  func register() { registrations = []; CircularActionButtonStyle.addCursorRect(to: self) }
}

let parent = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
parent.clipsToBounds = true
let cursor = CursorRecorder(frame: NSRect(x: 20, y: 20, width: 22, height: 25))
parent.addSubview(cursor)
cursor.register()
check(cursor.registrations.count == 1 && cursor.registrations[0].1 === NSCursor.pointingHand,
      "enabled visible action advertises the pointing-hand cursor")
check(cursor.registrations[0].0 == NSRect(x: 0, y: 0, width: 22, height: 25), "cursor covers the complete hit region")
cursor.isEnabled = false; cursor.register()
check(cursor.registrations.isEmpty, "disabled buttons do not advertise a clickable cursor")
cursor.isEnabled = true; cursor.isHidden = true; cursor.register()
check(cursor.registrations.isEmpty, "hidden buttons do not register a cursor")
cursor.isHidden = false; parent.isHidden = true; cursor.register()
check(cursor.registrations.isEmpty, "hidden ancestors suppress the cursor")
parent.isHidden = false; cursor.alphaValue = 0; cursor.register()
check(cursor.registrations.isEmpty, "fully faded track-removal buttons do not register a cursor")
cursor.alphaValue = 1
parent.alphaValue = 0; cursor.register()
check(cursor.registrations.isEmpty, "fully faded mini-player controls do not register a cursor")
parent.alphaValue = 1
cursor.frame.origin.x = -8; cursor.register()
check(cursor.registrations.count == 1 && cursor.registrations[0].0 == NSRect(x: 8, y: 0, width: 14, height: 25),
      "a clipped button registers only the visible part of its hit region")

func layout(_ button: NSButton) -> NSRect {
  button.translatesAutoresizingMaskIntoConstraints = false
  let host = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
  host.addSubview(button)
  NSLayoutConstraint.activate([
    button.centerXAnchor.constraint(equalTo: host.centerXAnchor),
    button.centerYAnchor.constraint(equalTo: host.centerYAnchor),
    button.widthAnchor.constraint(equalToConstant: 22),
    button.heightAnchor.constraint(equalToConstant: 22)
  ])
  host.layoutSubtreeIfNeeded()
  return button.frame
}
private let reference = TrackRemoveButton()
reference.isBordered = false
reference.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
reference.imagePosition = .imageOnly
reference.symbolConfiguration = .init(pointSize: 10, weight: .medium)
let referenceFrame = layout(reference)
check(referenceFrame == NSRect(x: 89, y: 37.5, width: 22, height: 25), "reference removal frame matches its pre-change native layout")
check(reference.circleFrame.size == NSSize(width: 14, height: 14), "reference visible circle remains 14pt")
for symbol in ["arrow.counterclockwise", "xmark", "arrow.uturn.backward"] {
  let button = CircularActionButton(symbolName: symbol, target: nil, action: nil)
  check(layout(button) == referenceFrame, "\(symbol) matches the reference hit frame and alignment")
  check(CircularActionButtonStyle.circleFrame(in: button.bounds) == reference.circleFrame,
        "\(symbol) matches the reference visible-circle geometry")
  check(button.intrinsicContentSize == NSSize(width: 22, height: 22), "\(symbol) requests the reference control size")
}

final class CursorInvalidationWindow: NSWindow {
  var invalidations: [NSView] = []
  override func invalidateCursorRects(for view: NSView) { invalidations.append(view) }
}
let window = CursorInvalidationWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
let buttons: [NSButton] = [CircularActionButton(symbolName: "arrow.counterclockwise", target: nil, action: nil), TrackRemoveButton()]
for button in buttons {
  window.contentView!.addSubview(button)
  for change in [{ button.isEnabled = false }, { button.isEnabled = true }, { button.isHidden = true }, { button.isHidden = false }, { button.alphaValue = 0 }, { button.alphaValue = 1 }] {
    window.invalidations = []
    change()
    check(window.invalidations.contains(where: { $0 === button }), "button visibility/availability invalidates native cursor regions")
  }
}
window.close()
print("Circular button checks passed: \(checks).")
