import Cocoa

private final class ProbeApplication: NSApplication {
  override var isActive: Bool { true }
}

private final class ProbeWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var isKeyWindow: Bool { true }
  override var isMainWindow: Bool { true }
}

private final class ProbeTarget: NSObject {
  var clicks = 0
  @objc dynamic var checked = true
  @objc func click(_ sender: NSButton) { clicks += 1 }
}

private final class FullWidthProbeRow: AccentTableRowView {
  override var accentSelectionInset: NSSize { .zero }
  override var accentSelectionRadius: CGFloat { 0 }
}

private final class TableSource: NSObject, NSTableViewDelegate, NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int { 2 }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = NSTableCellView()
    let label = NSTextField(labelWithString: row == 0 ? "Interface" : "General")
    label.font = .boldSystemFont(ofSize: 13)
    label.frame = NSRect(x: 32, y: 7, width: 170, height: 22)
    let image = NSImageView(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)!)
    image.frame = NSRect(x: 8, y: 8, width: 20, height: 20)
    image.contentTintColor = .labelColor
    cell.addSubview(label)
    cell.addSubview(image)
    cell.textField = label
    cell.imageView = image
    return cell
  }
  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    AccentTableRowView()
  }
}

@main
enum AdapterProbe {
  static func main() throws {
    setbuf(stdout, nil)
    let output = CommandLine.arguments[1]
    let light = CommandLine.arguments.contains("light")
    let disabled = CommandLine.arguments.contains("disabled")
    let yellow = CommandLine.arguments.contains("yellow")
    // NSArgumentDomain is process-local; this probe never writes preferences.
    UserDefaults.standard.setVolatileDomain([
      "AppleHighlightColor": yellow ? "0.98 0.90 0.20 Probe" : "0.52 0.13 0.31 Probe"
    ], forName: UserDefaults.argumentDomain)
    AppAccentColor.configure(useSystemAccent: !disabled)

    let app = ProbeApplication.shared
    app.setActivationPolicy(.accessory)
    let window = ProbeWindow(contentRect: NSRect(x: -2000, y: -2000, width: 680, height: 430),
                             styleMask: .borderless, backing: .buffered, defer: false)
    let root = window.contentView!
    root.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
    root.wantsLayer = true
    root.appearance?.performAsCurrentDrawingAppearance {
      root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    let target = ProbeTarget()
    let slider = AccentSlider(value: 74, minValue: -100, maxValue: 100, target: nil, action: nil)
    slider.frame = NSRect(x: 24, y: 350, width: 360, height: 24)
    if #available(macOS 26, *) { slider.neutralValue = 0 }
    root.addSubview(slider)
    let ticks = AccentSlider(value: 6, minValue: -12, maxValue: 12, target: nil, action: nil)
    ticks.frame = NSRect(x: 24, y: 300, width: 360, height: 32)
    ticks.numberOfTickMarks = 5
    if #available(macOS 26, *) { ticks.neutralValue = 0 }
    root.addSubview(ticks)
    let segments = AccentSegmentedControl(labels: ["Default", "4:3", "16:9"],
      trackingMode: .selectOne, target: nil, action: nil)
    segments.frame = NSRect(x: 24, y: 230, width: 360, height: 32)
    segments.selectedSegment = 0
    root.addSubview(segments)
    let radio = AccentButton(radioButtonWithTitle: "Do not resize", target: target, action: #selector(ProbeTarget.click))
    radio.frame = NSRect(x: 24, y: 170, width: 360, height: 32)
    radio.state = .on
    root.addSubview(radio)
    let check = AccentButton(checkboxWithTitle: "Use physical resolution", target: target, action: #selector(ProbeTarget.click))
    check.frame = NSRect(x: 24, y: 110, width: 360, height: 32)
    check.bind(.value, to: target, withKeyPath: "checked")
    root.addSubview(check)
    let disabledRadio = AccentButton(radioButtonWithTitle: "Disabled selection", target: nil, action: nil)
    disabledRadio.frame = NSRect(x: 24, y: 50, width: 360, height: 32)
    disabledRadio.state = .on
    disabledRadio.isEnabled = false
    root.addSubview(disabledRadio)

    let tableSource = TableSource()
    let scroll = NSScrollView(frame: NSRect(x: 420, y: 190, width: 230, height: 170))
    let table = NSTableView(frame: scroll.bounds)
    table.style = .sourceList
    table.headerView = nil
    table.rowHeight = 36
    table.addTableColumn(NSTableColumn(identifier: .init("main")))
    table.delegate = tableSource
    table.dataSource = tableSource
    scroll.documentView = table
    root.addSubview(scroll)
    table.reloadData()
    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

    let fullWidthRow = FullWidthProbeRow(frame: NSRect(x: 420, y: 95, width: 230, height: 55))
    let prefixButton = NSButton(title: "…", target: nil, action: nil)
    prefixButton.isBordered = false
    prefixButton.frame = NSRect(x: 12, y: 12, width: 24, height: 24)
    fullWidthRow.addSubview(prefixButton)
    fullWidthRow.isSelected = true
    root.addSubview(fullWidthRow)

    let legacy = NSView()
    let legacySlider = NSSlider()
    let legacySegments = NSSegmentedControl(labels: ["One", "Two"], trackingMode: .selectOne, target: nil, action: nil)
    let legacyRadio = NSButton(radioButtonWithTitle: "Legacy", target: nil, action: nil)
    let legacyDefault = NSButton(title: "Continue", target: nil, action: nil)
    legacyDefault.keyEquivalent = "\r"
    [legacySlider, legacySegments, legacyRadio, legacyDefault].forEach { legacy.addSubview($0) }
    AccentControls.apply(to: legacy)
    precondition(legacySlider.trackFillColor != nil && legacySegments.selectedSegmentBezelColor != nil)
    precondition(legacyRadio.bezelColor != nil && legacyDefault.bezelColor != nil)

    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
    root.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
    root.cacheDisplay(in: root.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))

    precondition(slider.trackFillColor != nil && ticks.trackFillColor != nil)
    precondition(segments.selectedSegmentBezelColor != nil)
    precondition(radio.bezelColor != nil && check.bezelColor != nil)
    let highlight = UserDefaults.standard.string(forKey: "AppleHighlightColor") ?? "nil"
    print("active=\(app.isActive), key=\(window.isKeyWindow), highlight=\(highlight)")
    print("color=\(AppAccentColor.color.usingColorSpace(.sRGB)!), radio=\(String(describing: radio.accessibilityRole())), cell=\(String(describing: radio.cell?.accessibilityRole()))")
    precondition(radio.accessibilityRole() == NSButton(radioButtonWithTitle: "", target: nil, action: nil).accessibilityRole())
    precondition(check.accessibilityRole() == NSButton(checkboxWithTitle: "", target: nil, action: nil).accessibilityRole())
    precondition(slider.accessibilityRole() == NSSlider().accessibilityRole())
    precondition(radio.cell?.accessibilityRole() == .radioButton && check.cell?.accessibilityRole() == .checkBox)
    var expected = AppAccentColor.color.usingColorSpace(.sRGB)!
    root.effectiveAppearance.performAsCurrentDrawingAppearance {
      expected = AppAccentColor.color.usingColorSpace(.sRGB)!
      for input in [slider.trackFillColor, ticks.trackFillColor,
                    segments.selectedSegmentBezelColor, radio.bezelColor, check.bezelColor] {
        let actual = input!.usingColorSpace(.sRGB)!
        precondition(abs(actual.redComponent - expected.redComponent) < 0.0001 &&
                     abs(actual.greenComponent - expected.greenComponent) < 0.0001 &&
                     abs(actual.blueComponent - expected.blueComponent) < 0.0001)
      }
    }
    // cacheDisplay uses the display's ICC profile. Convert CGImage pixels to
    // sRGB before comparison; NSBitmapImageRep.colorAt labels raw data Generic RGB.
    let pixelsWide = bitmap.pixelsWide
    let pixelsHigh = bitmap.pixelsHigh
    var rgba = [UInt8](repeating: 0, count: pixelsWide * pixelsHigh * 4)
    rgba.withUnsafeMutableBytes { bytes in
      let context = CGContext(data: bytes.baseAddress, width: pixelsWide, height: pixelsHigh,
        bitsPerComponent: 8, bytesPerRow: pixelsWide * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.draw(bitmap.cgImage!, in: CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
    }
    func tintPixels(in rect: NSRect) -> Int {
      let scale = CGFloat(bitmap.pixelsWide) / root.bounds.width
      let pixels = NSRect(x: rect.minX * scale, y: (root.bounds.height - rect.maxY) * scale,
                          width: rect.width * scale, height: rect.height * scale).integral
      var count = 0
      for y in max(0, Int(pixels.minY))..<min(bitmap.pixelsHigh, Int(pixels.maxY)) {
        for x in max(0, Int(pixels.minX))..<min(bitmap.pixelsWide, Int(pixels.maxX)) {
          let index = (y * pixelsWide + x) * 4
          // Native AppKit retains its appearance-specific lighting and disabled
          // effects. Verify the chosen hue without requiring a flat raster fill.
          let tolerance: CGFloat = disabled ? 0.10 : 0.06
          if abs(CGFloat(rgba[index]) / 255 - expected.redComponent) < tolerance &&
             abs(CGFloat(rgba[index + 1]) / 255 - expected.greenComponent) < tolerance &&
             abs(CGFloat(rgba[index + 2]) / 255 - expected.blueComponent) < tolerance { count += 1 }
        }
      }
      return count
    }
    for control in [slider, ticks, segments, radio, check] as [NSView] {
      let count = tintPixels(in: control.frame)
      print("\(type(of: control)): \(count) tinted pixels")
      precondition(count > 20, "Tint missing from \(type(of: control))")
    }
    check.performClick(nil)
    precondition(!target.checked && target.clicks == 1, "Native bindings and action must survive tinting")
    check.unbind(.value)
    let row = table.rowView(atRow: 0, makeIfNecessary: false)!
    precondition(row is AccentTableRowView && row.isSelected)
    precondition(tintPixels(in: row.convert(row.bounds, to: root)) > 100)
    let settingsEdge = row.convert(NSRect(x: 0, y: 0, width: 3, height: row.bounds.height), to: root)
    precondition(tintPixels(in: settingsEdge) == 0, "Settings selection must retain its inset")
    let fullWidthCorner = fullWidthRow.convert(NSRect(x: 0, y: 0, width: 3, height: 3), to: root)
    precondition(tintPixels(in: fullWidthCorner) >= 20, "Full-width selection must have a square filled corner")
    let selectedCell = table.view(atColumn: 0, row: 0, makeIfNecessary: false) as! NSTableCellView
    root.effectiveAppearance.performAsCurrentDrawingAppearance {
      let selectedTitle = selectedCell.textField!.textColor!.usingColorSpace(.sRGB)!
      let expectedTitle = AppAccentColor.textColor.usingColorSpace(.sRGB)!
      precondition(abs(selectedTitle.redComponent - expectedTitle.redComponent) < 0.001)
      let buttonTitle = prefixButton.contentTintColor!.usingColorSpace(.sRGB)!
      precondition(abs(buttonTitle.redComponent - expectedTitle.redComponent) < 0.001)
    }
    table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    precondition(!row.isSelected)
    precondition(selectedCell.textField!.textColor == .labelColor)
    precondition(selectedCell.imageView!.contentTintColor == .labelColor)
    fullWidthRow.isSelected = false
    precondition(prefixButton.contentTintColor == nil)
    print("PASS: native constructors, color properties, source-list selection, AX roles, binding and action; image \(output)")
    withExtendedLifetime((target, tableSource, window)) {}
  }
}
