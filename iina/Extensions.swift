//
//  Extensions.swift
//  iina
//
//  Created by lhc on 12/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

extension NSSlider {
  /** Returns the position of knob center by point */
  func knobPointPosition() -> CGFloat {
    let sliderOrigin = frame.origin.x + knobThickness / 2
    let sliderWidth = frame.width - knobThickness
    assert(maxValue > minValue)
    let knobPos = sliderOrigin + sliderWidth * CGFloat((doubleValue - minValue) / (maxValue - minValue))
    return knobPos
  }
}

extension NSSegmentedControl {
  func selectSegment(withLabel label: String) {
    self.selectedSegment = -1
    for i in 0..<segmentCount {
      if self.label(forSegment: i) == label {
        self.selectedSegment = i
      }
    }
  }
}

func - (lhs: NSPoint, rhs: NSPoint) -> NSPoint {
  return NSMakePoint(lhs.x - rhs.x, lhs.y - rhs.y)
}

extension CGPoint {
  // Uses Pythagorean theorem to calculate the distance between two points
  func distance(to: CGPoint) -> CGFloat {
    return sqrt(pow(self.x - to.x, 2) + pow(self.y - to.y, 2))
  }
}

extension NSSize {

  var aspect: CGFloat {
    get {
      assert(width != 0 && height != 0)
      return width / height
    }
  }

  /** Resize to no smaller than a min size while keeping same aspect */
  func satisfyMinSizeWithSameAspectRatio(_ minSize: NSSize) -> NSSize {
    if width >= minSize.width && height >= minSize.height {  // no need to resize if larger
      return self
    } else {
      return grow(toSize: minSize)
    }
  }

  /** Resize to no larger than a max size while keeping same aspect */
  func satisfyMaxSizeWithSameAspectRatio(_ maxSize: NSSize) -> NSSize {
    if width <= maxSize.width && height <= maxSize.height {  // no need to resize if smaller
      return self
    } else {
      return shrink(toSize: maxSize)
    }
  }

  func crop(withAspect aspectRect: Aspect) -> NSSize {
    let targetAspect = aspectRect.value
    if aspect > targetAspect {  // self is wider, crop width, use same height
      return NSSize(width: height * targetAspect, height: height)
    } else {
      return NSSize(width: width, height: width / targetAspect)
    }
  }

  func expand(withAspect aspectRect: Aspect) -> NSSize {
    let targetAspect = aspectRect.value
    if aspect < targetAspect {  // self is taller, expand width, use same height
      return NSSize(width: height * targetAspect, height: height)
    } else {
      return NSSize(width: width, height: width / targetAspect)
    }
  }

  /**
   Given another size S, returns a size that:

   - maintains the same aspect ratio;
   - has same height or/and width as S;
   - always bigger than S.

   - parameter toSize: The given size S.

   ```
   +--+------+--+
   |  |      |  |
   |  |  S   |  |<-- The result size
   |  |      |  |
   +--+------+--+
   ```
   */
  func grow(toSize size: NSSize) -> NSSize {
    if width == 0 || height == 0 {
      return size
    }
    let sizeAspect = size.aspect
    if aspect > sizeAspect {  // self is wider, grow to meet height
      return NSSize(width: size.height * aspect, height: size.height)
    } else {
      return NSSize(width: size.width, height: size.width / aspect)
    }
  }

  /**
   Given another size S, returns a size that:

   - maintains the same aspect ratio;
   - has same height or/and width as S;
   - always smaller than S.

   - parameter toSize: The given size S.

   ```
   +--+------+--+
   |  |The   |  |
   |  |result|  |<-- S
   |  |size  |  |
   +--+------+--+
   ```
   */
  func shrink(toSize size: NSSize) -> NSSize {
    if width == 0 || height == 0 {
      return size
    }
    let sizeAspect = size.aspect
    if aspect < sizeAspect { // self is taller, shrink to meet height
      return NSSize(width: size.height * aspect, height: size.height)
    } else {
      return NSSize(width: size.width, height: size.width / aspect)
    }
  }

  func centeredRect(in rect: NSRect) -> NSRect {
    return NSRect(x: rect.origin.x + (rect.width - width) / 2,
                  y: rect.origin.y + (rect.height - height) / 2,
                  width: width,
                  height: height)
  }

  func multiply(_ multiplier: CGFloat) -> NSSize {
    return NSSize(width: width * multiplier, height: height * multiplier)
  }

  func add(_ multiplier: CGFloat) -> NSSize {
    return NSSize(width: width + multiplier, height: height + multiplier)
  }

}


extension NSRect {

  init(vertexPoint pt1: NSPoint, and pt2: NSPoint) {
    self.init(x: min(pt1.x, pt2.x),
              y: min(pt1.y, pt2.y),
              width: abs(pt1.x - pt2.x),
              height: abs(pt1.y - pt2.y))
  }

  func multiply(_ multiplier: CGFloat) -> NSRect {
    return NSRect(x: origin.x, y: origin.y, width: width * multiplier, height: height * multiplier)
  }

  func centeredResize(to newSize: NSSize) -> NSRect {
    return NSRect(x: origin.x - (newSize.width - size.width) / 2,
                  y: origin.y - (newSize.height - size.height) / 2,
                  width: newSize.width,
                  height: newSize.height)
  }

  func constrain(in biggerRect: NSRect) -> NSRect {
    // new size
    var newSize = size
    if newSize.width > biggerRect.width || newSize.height > biggerRect.height {
      newSize = size.shrink(toSize: biggerRect.size)
    }
    // new origin
    var newOrigin = origin
    if newOrigin.x < biggerRect.origin.x {
      newOrigin.x = biggerRect.origin.x
    }
    if newOrigin.y < biggerRect.origin.y {
      newOrigin.y = biggerRect.origin.y
    }
    if newOrigin.x + width > biggerRect.origin.x + biggerRect.width {
      newOrigin.x = biggerRect.origin.x + biggerRect.width - width
    }
    if newOrigin.y + height > biggerRect.origin.y + biggerRect.height {
      newOrigin.y = biggerRect.origin.y + biggerRect.height - height
    }
    return NSRect(origin: newOrigin, size: newSize)
  }
}

extension NSPoint {
  func constrained(to rect: NSRect) -> NSPoint {
    return NSMakePoint(x.clamped(to: rect.minX...rect.maxX), y.clamped(to: rect.minY...rect.maxY))
  }
}

extension Array {
  subscript(at index: Index) -> Element? {
    if indices.contains(index) {
      return self[index]
    } else {
      return nil
    }
  }
}

extension NSMenu {
  @discardableResult
  func addItem(withTitle string: String, action selector: Selector? = nil, target: AnyObject? = nil,
               tag: Int? = nil, obj: Any? = nil, stateOn: Bool = false, enabled: Bool = true) -> NSMenuItem {
    let menuItem = NSMenuItem(title: string, action: selector, keyEquivalent: "")
    menuItem.tag = tag ?? -1
    menuItem.representedObject = obj
    menuItem.target = target
    menuItem.state = stateOn ? .on : .off
    menuItem.isEnabled = enabled
    self.addItem(menuItem)
    return menuItem
  }
}

extension CGFloat {
  var unifiedDouble: Double {
    get {
      return Double(copysign(1, self))
    }
  }
}

extension Double {
  func prettyFormat() -> String {
    let rounded = (self * 1000).rounded() / 1000
    if rounded.truncatingRemainder(dividingBy: 1) == 0 {
      return "\(Int(rounded))"
    } else {
      return "\(rounded)"
    }
  }
}

extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    if self < range.lowerBound {
      return range.lowerBound
    } else if self > range.upperBound {
      return range.upperBound
    } else {
      return self
    }
  }
}

extension BinaryInteger {
  func clamped(to range: Range<Self>) -> Self {
    if self < range.lowerBound {
      return range.lowerBound
    } else if self >= range.upperBound {
      return range.upperBound.advanced(by: -1)
    } else {
      return self
    }
  }
}

// Formats a number to max 2 digits after the decimal, rounded, but will omit trailing zeroes, and no commas or other formatting for large numbers
fileprivate let fmtDecimalMaxFractionDigits2: NumberFormatter = {
  let fmt = NumberFormatter()
  fmt.numberStyle = .decimal
  fmt.usesGroupingSeparator = false
  fmt.maximumFractionDigits = 2
  return fmt
}()

extension FloatingPoint {
  func clamped(to range: Range<Self>) -> Self {
    if self < range.lowerBound {
      return range.lowerBound
    } else if self >= range.upperBound {
      return range.upperBound.nextDown
    } else {
      return self
    }
  }

  /// Formats as String, rounding the number to 2 digits after the decimal
  var stringMaxFrac2: String {
    return fmtDecimalMaxFractionDigits2.string(for: self)!
  }

}

extension NSColor {
  var mpvColorString: String {
    get {
      return "\(self.redComponent)/\(self.greenComponent)/\(self.blueComponent)/\(self.alphaComponent)"
    }
  }

  convenience init?(mpvColorString: String) {
    let splitted = mpvColorString.split(separator: "/").map { (seq) -> Double? in
      return Double(String(seq))
    }
    // check nil
    if (!splitted.contains {$0 == nil}) {
      if splitted.count == 3 {  // if doesn't have alpha value
        self.init(red: CGFloat(splitted[0]!), green: CGFloat(splitted[1]!), blue: CGFloat(splitted[2]!), alpha: CGFloat(1))
      } else if splitted.count == 4 {  // if has alpha value
        self.init(red: CGFloat(splitted[0]!), green: CGFloat(splitted[1]!), blue: CGFloat(splitted[2]!), alpha: CGFloat(splitted[3]!))
      } else {
        return nil
      }
    } else {
      return nil
    }
  }
}


extension NSMutableAttributedString {
  convenience init?(linkTo url: String, text: String, font: NSFont) {
    self.init(string: text)
    let range = NSRange(location: 0, length: self.length)
    let nsurl = NSURL(string: url)!
    self.beginEditing()
    self.addAttribute(.link, value: nsurl, range: range)
    self.addAttribute(.font, value: font, range: range)
    self.endEditing()
  }
}


extension UserDefaults {

  func mpvColor(forKey key: String) -> String? {
    guard let data = self.data(forKey: key) else { return nil }
    guard let color = NSUnarchiver.unarchiveObject(with: data) as? NSColor else { return nil }
    return color.usingColorSpace(.deviceRGB)?.mpvColorString
  }
}


extension NSData {
  func md5() -> NSString {
    let digestLength = Int(CC_MD5_DIGEST_LENGTH)
    let md5Buffer = UnsafeMutablePointer<CUnsignedChar>.allocate(capacity: digestLength)

    CC_MD5(bytes, CC_LONG(length), md5Buffer)

    let output = NSMutableString(capacity: Int(CC_MD5_DIGEST_LENGTH * 2))
    for i in 0..<digestLength {
      output.appendFormat("%02x", md5Buffer[i])
    }

    md5Buffer.deallocate()
    return NSString(format: output)
  }
}

extension Data {
  var md5: String {
    get {
      return (self as NSData).md5() as String
    }
  }

  var chksum64: UInt64 {
    return withUnsafeBytes {
      $0.bindMemory(to: UInt64.self).reduce(0, &+)
    }
  }

  init<T>(bytesOf thing: T) {
    var copyOfThing = thing // Hopefully CoW?
    self.init(bytes: &copyOfThing, count: MemoryLayout.size(ofValue: thing))
  }
  
  func saveToFolder(_ url: URL, filename: String) -> URL? {
    let fileUrl = url.appendingPathComponent(filename)
    do {
      try self.write(to: fileUrl)
    } catch {
      Utility.showAlert("error_saving_file", arguments: ["data", filename])
      return nil
    }
    return fileUrl
  }
}

extension FileHandle {
  func read<T>(type: T.Type /* To prevent unintended specializations */) -> T? {
    let size = MemoryLayout<T>.size
    let data = readData(ofLength: size)
    guard data.count == size else {
      return nil
    }
    return data.withUnsafeBytes {
      $0.bindMemory(to: T.self).first!
    }
  }
}

extension String {
  var md5: String {
    get {
      return self.data(using: .utf8)!.md5
    }
  }

  var isDirectoryAsPath: Bool {
    get {
      var re = ObjCBool(false)
      FileManager.default.fileExists(atPath: self, isDirectory: &re)
      return re.boolValue
    }
  }

  var lowercasedPathExtension: String {
    return (self as NSString).pathExtension.lowercased()
  }

  var mpvFixedLengthQuoted: String {
    return "%\(count)%\(self)"
  }

  func equalsIgnoreCase(_ other: String) -> Bool {
    return localizedCaseInsensitiveCompare(other) == .orderedSame
  }

  var quoted: String {
    return "\"\(self)\""
  }

  mutating func deleteLast(_ num: Int) {
    removeLast(Swift.min(num, count))
  }

  func countOccurrences(of str: String, in range: Range<Index>?) -> Int {
    if let firstRange = self.range(of: str, options: [], range: range, locale: nil) {
      let nextRange = firstRange.upperBound..<self.endIndex
      return 1 + countOccurrences(of: str, in: nextRange)
    } else {
      return 0
    }
  }
}


extension CharacterSet {
  static let urlAllowed: CharacterSet = {
    var set = CharacterSet.urlHostAllowed
      .union(.urlUserAllowed)
      .union(.urlPasswordAllowed)
      .union(.urlPathAllowed)
      .union(.urlQueryAllowed)
      .union(.urlFragmentAllowed)
    set.insert(charactersIn: "%")
    return set
  }()
}


extension NSMenuItem {
  static let dummy = NSMenuItem(title: "Dummy", action: nil, keyEquivalent: "")
}


extension URL {
  var creationDate: Date? {
    (try? resourceValues(forKeys: [.creationDateKey]))?.creationDate
  }

  var isExistingDirectory: Bool {
    return (try? self.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
  }
}


extension NSTextField {

  func setHTMLValue(_ html: String) {
    let font = self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let color = self.textColor ?? NSColor.labelColor
    if let data = html.data(using: .utf8), let str = NSMutableAttributedString(html: data,
                                                                               options: [.textEncodingName: "utf8"],
                                                                               documentAttributes: nil) {
      str.addAttributes([.font: font, .foregroundColor: color], range: NSMakeRange(0, str.length))
      self.attributedStringValue = str
    }
  }

}

extension NSImage {
  func tinted(_ tintColor: NSColor) -> NSImage {
    guard self.isTemplate else { return self }

    let image = self.copy() as! NSImage
    image.lockFocus()

    tintColor.set()
    NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)

    image.unlockFocus()
    image.isTemplate = false

    return image
  }

  func rounded() -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()

    let frame = NSRect(origin: .zero, size: size)
    NSBezierPath(ovalIn: frame).addClip()
    draw(at: .zero, from: frame, operation: .sourceOver, fraction: 1)

    image.unlockFocus()
    return image
  }

  static func maskImage(cornerRadius: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: cornerRadius * 2, height: cornerRadius * 2), flipped: false) { rectangle in
      let bezierPath = NSBezierPath(roundedRect: rectangle, xRadius: cornerRadius, yRadius: cornerRadius)
      NSColor.black.setFill()
      bezierPath.fill()
      return true
    }
    image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
    return image
  }

  func rotate(_ degree: Int) -> NSImage {
    var degree = ((degree % 360) + 360) % 360
    guard degree % 90 == 0 && degree != 0 else { return self }
    // mpv's rotation is clockwise, NSAffineTransform's rotation is counterclockwise
    degree = 360 - degree
    let newSize = (degree == 180 ? self.size : NSMakeSize(self.size.height, self.size.width))
    let rotation = NSAffineTransform.init()
    rotation.rotate(byDegrees: CGFloat(degree))
    rotation.append(.init(translationByX: newSize.width / 2, byY: newSize.height / 2))

    let newImage = NSImage(size: newSize)
    newImage.lockFocus()
    rotation.concat()
    let rect = NSMakeRect(0, 0, self.size.width, self.size.height)
    let corner = NSMakePoint(-self.size.width / 2, -self.size.height / 2)
    self.draw(at: corner, from: rect, operation: .copy, fraction: 1)
    newImage.unlockFocus()
    return newImage
  }
}


extension NSVisualEffectView {
  func roundCorners(withRadius cornerRadius: CGFloat) {
    if #available(macOS 10.14, *) {
      maskImage = .maskImage(cornerRadius: cornerRadius)
    } else {
      layer?.cornerRadius = cornerRadius
    }
  }
}


extension NSBox {
  static func horizontalLine() -> NSBox {
    let box = NSBox(frame: NSRect(origin: .zero, size: NSSize(width: 100, height: 1)))
    box.boxType = .separator
    return box
  }
}


extension NSPasteboard.PasteboardType {
  static let nsURL = NSPasteboard.PasteboardType("NSURL")
  static let nsFilenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
  static let iinaPlaylistItem = NSPasteboard.PasteboardType("IINAPlaylistItem")
}


extension NSWindow.Level {
  static let iinaFloating = NSWindow.Level(NSWindow.Level.floating.rawValue - 1)
  static let iinaBlackScreen = NSWindow.Level(NSWindow.Level.mainMenu.rawValue + 1)
}

extension NSUserInterfaceItemIdentifier {
  static let isChosen = NSUserInterfaceItemIdentifier("IsChosen")
  static let trackId = NSUserInterfaceItemIdentifier("TrackId")
  static let trackName = NSUserInterfaceItemIdentifier("TrackName")
  static let isPlayingCell = NSUserInterfaceItemIdentifier("IsPlayingCell")
  static let trackNameCell = NSUserInterfaceItemIdentifier("TrackNameCell")
  static let key = NSUserInterfaceItemIdentifier("Key")
  static let value = NSUserInterfaceItemIdentifier("Value")
  static let action = NSUserInterfaceItemIdentifier("Action")
}

extension NSAppearance {
  @available(macOS 10.14, *)
  convenience init?(iinaTheme theme: Preference.Theme) {
    switch theme {
    case .dark:
      self.init(named: .darkAqua)
    case .light:
      self.init(named: .aqua)
    default:
      return nil
    }
  }

  var isDark: Bool {
    if #available(macOS 10.14, *) {
      return name == .darkAqua || name == .vibrantDark || name == .accessibilityHighContrastDarkAqua || name == .accessibilityHighContrastVibrantDark
    } else {
      return name == .vibrantDark
    }
  }
}

extension NSScreen {

  /// Height of the camera housing on this screen if this screen has an embedded camera.
  var cameraHousingHeight: CGFloat? {
    if #available(macOS 12.0, *) {
      return safeAreaInsets.top == 0.0 ? nil : safeAreaInsets.top
    } else {
      return nil
    }
  }

  /// Log the given `NSScreen` object.
  ///
  /// Due to issues with multiple monitors and how the screen to use for a window is selected detailed logging has been added in this
  /// area in case additional problems are encountered in the future.
  /// - parameter label: Label to include in the log message.
  /// - parameter screen: The `NSScreen` object to log.
  static func log(_ label: String, _ screen: NSScreen?) {
    guard let screen = screen else {
      Logger.log("\(label): nil")
      return
    }
    // Unfortunately localizedName is not available until macOS Catalina.
    if #available(macOS 10.15, *) {
      let maxPossibleEDR = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
      let canEnableEDR = maxPossibleEDR > 1.0
      Logger.log("\(label): \"\(screen.localizedName)\" visible frame \(screen.visibleFrame) EDR: {supports=\(canEnableEDR) maxPotential=\(maxPossibleEDR) maxCurrent=\(screen.maximumExtendedDynamicRangeColorComponentValue)}")
    } else {
      Logger.log("\(label): visible frame \(screen.visibleFrame)")
    }
  }
}

extension NSWindow {

  /// Return the screen to use by default for this window.
  ///
  /// This method searches for a screen to use in this order:
  /// - `window!.screen` The screen where most of the window is on; it is `nil` when the window is offscreen.
  /// - `NSScreen.main` The screen containing the window that is currently receiving keyboard events.
  /// - `NSScreeen.screens[0]` The primary screen of the user’s system.
  ///
  /// `PlayerCore` caches players along with their windows. This window may have been previously used on an external monitor
  /// that is no longer attached. In that case the `screen` property of the window will be `nil`.  Apple documentation is silent
  /// concerning when `NSScreen.main` is `nil`.  If that is encountered the primary screen will be used.
  ///
  /// - returns: The default `NSScreen` for this window
  func selectDefaultScreen() -> NSScreen {
    if screen != nil {
      return screen!
    }
    if NSScreen.main != nil {
      return NSScreen.main!
    }
    return NSScreen.screens[0]
  }
}

extension Process {
  @discardableResult
  static func run(_ cmd: [String], at currentDir: URL? = nil) -> (process: Process, stdout: Pipe, stderr: Pipe) {
    guard cmd.count > 0 else {
      fatalError("Process.launch: the command should not be empty")
    }

    let (stdout, stderr) = (Pipe(), Pipe())
    let process = Process()
    if #available(macOS 10.13, *) {
      process.executableURL = URL(fileURLWithPath: cmd[0])
      process.currentDirectoryURL = currentDir
    } else {
      process.launchPath = cmd[0]
      if let path = currentDir?.path {
        process.currentDirectoryPath = path
      }
    }
    process.arguments = [String](cmd.dropFirst())
    process.standardOutput = stdout
    process.standardError = stderr
    process.launch()
    process.waitUntilExit()

    return (process, stdout, stderr)
  }
}
