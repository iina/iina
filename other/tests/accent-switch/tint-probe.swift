import Cocoa
import SwiftUI

struct Probe: View {
  var body: some View {
    HStack(spacing: 30) {
      Toggle("Tint", isOn: .constant(true)).toggleStyle(.switch).tint(Color(red: 0.88, green: 0.27, blue: 0.09))
      Toggle("Style", isOn: .constant(true)).toggleStyle(SwitchToggleStyle(tint: Color(red: 0.88, green: 0.27, blue: 0.09)))
      Toggle("Default", isOn: .constant(true)).toggleStyle(.switch)
    }.padding(20)
  }
}
let previousApplication = NSWorkspace.shared.frontmostApplication
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let view = NSHostingView(rootView: Probe())
let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 450, height: 90), styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = view
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { _ in
  view.layoutSubtreeIfNeeded()
  view.display()
  print("active \(app.isActive) key \(window.isKeyWindow) bounds \(view.bounds) accent \(NSColor.controlAccentColor.usingColorSpace(.sRGB)!)")
  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
  view.cacheDisplay(in: view.bounds, to: bitmap)
  try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
  print("wrote \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
  window.orderOut(nil)
  previousApplication?.activate(options: [])
  exit(0)
}
app.run()
