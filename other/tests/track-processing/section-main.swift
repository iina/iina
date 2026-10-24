let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  precondition(value(), message); checks += 1; print("PASS \(message)")
}
let window = NSWindow(contentRect: NSRect(x: -9000, y: -9000, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
let scroll = NSScrollView(frame: window.contentView!.bounds)
scroll.autoresizingMask = [.width, .height]
let document = FlippedView(frame: NSRect(x: 0, y: 0, width: 400, height: 1100))
scroll.documentView = document
window.contentView!.addSubview(scroll)
let cards = [140, 250].map { height -> NSView in
  let view = NSView(); view.translatesAutoresizingMaskIntoConstraints = false
  view.heightAnchor.constraint(equalToConstant: CGFloat(height)).isActive = true
  return view
}
let section = TrackProcessingSection(player: PlayerCore(), group: .videoGeometry, cards: cards)
document.addSubview(section)
section.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 16).isActive = true
section.topAnchor.constraint(equalTo: document.topAnchor, constant: 100).isActive = true
let width = section.widthAnchor.constraint(equalToConstant: 368); width.isActive = true
window.orderFrontRegardless()
func pump() {
  window.contentView!.layoutSubtreeIfNeeded()
  RunLoop.main.run(until: Date().addingTimeInterval(0.02))
  window.contentView!.layoutSubtreeIfNeeded()
}
pump()
let stack = section.subviews.first as! NSStackView
let header = stack.arrangedSubviews.first!
func headerFrame() -> NSRect { section.convert(header.bounds, from: header) }
func near(_ left: CGFloat, _ right: CGFloat) -> Bool { abs(left - right) < 0.1 }
check(near(section.frame.height, 442), "processing section height includes header, cards and spacing")
check(near(headerFrame().minY, 0) && near(header.frame.height, 28) && near(header.frame.width, 368),
      "header starts at its section top with the full section width")
func scrollTo(_ y: CGFloat) {
  scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
  scroll.reflectScrolledClipView(scroll.contentView); pump()
}
scrollTo(180)
check(near(headerFrame().minY, 0) && near(document.convert(header.bounds, from: header).minY, 100)
      && header.visibleRect.intersection(header.bounds).isEmpty,
      "header scrolls out of view without following the viewport")
check(stack.arrangedSubviews.first === header && stack.layer?.mask == nil,
      "header participates in normal layout without an overlay or content mask")
scrollTo(500)
check(near(document.convert(header.bounds, from: header).minY, 100), "header remains at its original document position while cards scroll")
scrollTo(620)
check(near(headerFrame().maxY, 28)
      && document.convert(header.bounds, from: header).maxY <= scroll.contentView.bounds.minY,
      "header exits with processing and cannot cover Playback below it")
scrollTo(50)
check(near(headerFrame().minY, 0) && near(document.convert(header.bounds, from: header).minY, 100)
      && !header.visibleRect.intersection(header.bounds).isEmpty,
      "scrolling back restores the header and never overlays the track list")
width.constant = 290; pump()
check(near(header.frame.width, 290) && cards.allSatisfy { near($0.frame.width, 290) },
      "header and all cards follow a resized sidebar width")
window.close()
print("Processing section layout: \(checks) checks passed.")
