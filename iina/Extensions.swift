//
//  Extensions.swift
//  iina
//
//  Created by lhc on 12/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import CryptoKit

extension NSSlider {
  /**
   Returns the position of the knob's center point along the slider's track.

   This method calculates the horizontal position of the center of the slider's knob based on the slider's current value (`doubleValue`), the minimum and maximum values, and the slider's dimensions. It can be useful for custom drawing, animations, or hit detection related to the knob's position.

   - Returns: A `CGFloat` representing the x-coordinate of the knob's center along the slider's width.

   - Important: Ensure that the slider's `maxValue` is greater than `minValue`. An assertion is used to validate this.

   Example usage:
   ```swift
   let slider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
   let knobPosition = slider.knobPointPosition()
   print("The knob is positioned at x-coordinate: \(knobPosition)")
   ```
   */
  func knobPointPosition() -> CGFloat {
    let sliderOrigin = frame.origin.x + knobThickness / 2
    let sliderWidth = frame.width - knobThickness
    assert(maxValue > minValue)
    let knobPos = sliderOrigin + sliderWidth * CGFloat((doubleValue - minValue) / (maxValue - minValue))
    return knobPos
  }
}

extension CGPoint {
  /**
   Uses the Pythagorean theorem to calculate the distance between two points.

   This method calculates the straight-line distance (Euclidean distance) between the current point and another `CGPoint`. It is useful for measuring distances in a two-dimensional coordinate system, such as when working with points on a canvas or in a graphics context.

   - Parameter to: The target `CGPoint` to which the distance will be calculated.
   - Returns: A `CGFloat` representing the distance between the two points.

   Example usage:
   ```swift
   let pointA = CGPoint(x: 0, y: 0)
   let pointB = CGPoint(x: 3, y: 4)
   let distance = pointA.distance(to: pointB)
   print("Distance between pointA and pointB is \(distance)")  // Output: 5.0
   ```
   */
  func distance(to: CGPoint) -> CGFloat {
    return sqrt(pow(self.x - to.x, 2) + pow(self.y - to.y, 2))
  }
}

extension NSSize {

  /**
   Returns the aspect ratio (width divided by height) of the size.

   This property asserts that neither width nor height is zero, and then calculates the aspect ratio.

   - Returns: The aspect ratio of the size as a `CGFloat`.
   */
  var aspect: CGFloat {
    get {
      assert(width != 0 && height != 0)
      return width / height
    }
  }

  /**
   Resizes the current size to be no smaller than a given minimum size while maintaining the same aspect ratio.

   This method checks if the current size is already larger than the given minimum size, and if not, it resizes the current size to the minimum size, preserving the aspect ratio.

   - Parameter minSize: The minimum size that the current size should satisfy.
   - Returns: The resized `NSSize` that satisfies the minimum size requirement while keeping the same aspect ratio.
   */
  func satisfyMinSizeWithSameAspectRatio(_ minSize: NSSize) -> NSSize {
    if width >= minSize.width && height >= minSize.height {
      return self
    } else {
      return grow(toSize: minSize)
    }
  }

  /**
   Resizes the current size to be no larger than a given maximum size while maintaining the same aspect ratio.

   This method checks if the current size is already smaller than the given maximum size, and if not, it resizes the current size to the maximum size, preserving the aspect ratio.

   - Parameter maxSize: The maximum size that the current size should satisfy.
   - Returns: The resized `NSSize` that satisfies the maximum size requirement while keeping the same aspect ratio.
   */
  func satisfyMaxSizeWithSameAspectRatio(_ maxSize: NSSize) -> NSSize {
    if width <= maxSize.width && height <= maxSize.height {
      return self
    } else {
      return shrink(toSize: maxSize)
    }
  }

  /**
   Crops the current size to fit within a target aspect ratio, reducing either the width or height to match the aspect ratio of the target rectangle.

   - Parameter aspectRect: A rectangle or size structure that contains the desired aspect ratio.
   - Returns: The cropped `NSSize` that fits within the given aspect ratio.
   */
  func crop(withAspect aspectRect: Aspect) -> NSSize {
    let targetAspect = aspectRect.value
    if aspect > targetAspect {
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
  /**
   Returns a `NSRect` that represents the size centered within the given `NSRect`.

   This method calculates a new rectangle (`NSRect`) where the current size (`NSSize`) is centered inside the provided rectangle (`rect`). It is useful when you need to center one view or size within another, maintaining its dimensions.

   - Parameter rect: The rectangle within which to center the current size.
   - Returns: A `NSRect` where the current size is centered inside the given rectangle.

   Example usage:
   ```swift
   let size = NSSize(width: 100, height: 50)
   let containerRect = NSRect(x: 0, y: 0, width: 300, height: 200)
   let centeredRect = size.centeredRect(in: containerRect)
   print(centeredRect)  // Output: NSRect(x: 100.0, y: 75.0, width: 100.0, height: 50.0)
   ```
   */
  func centeredRect(in rect: NSRect) -> NSRect {
    return NSRect(x: rect.origin.x + (rect.width - width) / 2,
                  y: rect.origin.y + (rect.height - height) / 2,
                  width: width,
                  height: height)
  }
  /**
   Multiplies both the width and height of the current size by a given multiplier.

   This method returns a new `NSSize` where both the width and height are scaled by the given multiplier. It is useful for proportionally resizing an object.

   - Parameter multiplier: The multiplier used to scale both width and height.
   - Returns: A new `NSSize` with the dimensions scaled by the multiplier.

   Example usage:
   ```swift
   let size = NSSize(width: 100, height: 50)
   let scaledSize = size.multiply(2.0)
   print(scaledSize)  // Output: NSSize(width: 200.0, height: 100.0)
   ```
   */
  func multiply(_ multiplier: CGFloat) -> NSSize {
    return NSSize(width: width * multiplier, height: height * multiplier)
  }
  /**
   Adds a given value to both the width and height of the current size.

   This method returns a new `NSSize` where the provided value is added to both the width and height. It is useful for increasing the size by a fixed amount.

   - Parameter value: The value to be added to both the width and height.
   - Returns: A new `NSSize` with the increased dimensions.

   Example usage:
   ```swift
   let size = NSSize(width: 100, height: 50)
   let newSize = size.add(10)
   print(newSize)  // Output: NSSize(width: 110.0, height: 60.0)
   ```
   */
  func add(_ value: CGFloat) -> NSSize {
    return NSSize(width: width + value, height: height + value)
  }

}


extension NSRect {

  init(vertexPoint pt1: NSPoint, and pt2: NSPoint) {
    self.init(x: min(pt1.x, pt2.x),
              y: min(pt1.y, pt2.y),
              width: abs(pt1.x - pt2.x),
              height: abs(pt1.y - pt2.y))
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

  func roundedTo2Decimals() -> Double {
    let scaledUp = self * 1e2
    let scaledUpRounded = scaledUp.rounded(.up)
    let finalVal = scaledUpRounded / 1e2
    return finalVal
  }
  
  /// Formats this number as a decimal string, using the default locale.
  ///
  /// This should be used in most places where decimal numbers need to be printed. Do not rely on string interpolation alone
  /// because the number will not be localized.
  ///
  /// For example, if the user's locale formats numbers like `1.234.567,89` (in particular, using
  /// a comma to signify the decimal):
  /// ```
  /// let num: Double = 12.34
  /// let badStr = "Value is \(num)"          // badStr will *always* be "Value is 12.34"
  /// let goodStr = "Value is \(num.string)"  // goodStr will be "Value is 12,34"
  /// ```
  ///
  /// Currently the output string is limited to 15 digits after the decimal. This should be more than
  /// enough for any imaginable use right now, but the limit can and should be increased in the future if
  /// needed. (It's not clear what the maximum allowed value for `NumberFormatter.maximumFractionDigits`
  /// actually is. An attempt to set it equal to `NSIntegerMax` seemed to result in it being silently set to
  /// `6` instead.)
  var string: String {
    return fmtDecimalMaxFractionDigits15.string(from: self as NSNumber) ?? "NaN"
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

// Formats a number to max 2 digits after the decimal, rounded, but will omit trailing zeroes, and no commas or other formatting for large numbers
fileprivate let fmtDecimalMaxFractionDigits2: NumberFormatter = {
  let fmt = NumberFormatter()
  fmt.numberStyle = .decimal
  fmt.usesGroupingSeparator = false
  fmt.maximumFractionDigits = 2
  return fmt
}()

fileprivate let fmtDecimalMaxFractionDigits15: NumberFormatter = {
  let fmt = NumberFormatter()
  fmt.numberStyle = .decimal
  fmt.usesGroupingSeparator = true
  fmt.maximumSignificantDigits = 25
  fmt.minimumFractionDigits = 0
  fmt.maximumFractionDigits = 15
  fmt.usesSignificantDigits = false
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
  var stringWithMaxFractionDigits2: String {
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

extension Data {
  var md5: String { Insecure.MD5.hash(data: self).map { String(format: "%02x", $0) }.joined() }

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

  /// Try to find a SF Symbol. This function will iterate through the provided list of SF Symbol name list to and return the
  /// first available SF Symbol at runtime.
  ///
  /// Even though SF Symbol is available from macOS 11, we require at macOS 14 to use SF Symbol for the sake of consistency. On
  /// older systems (macOS 13 and below), because SF Symbols are not complete enough for our usage, we don't use them at all.
  /// If a better symbol is found in a later release of SF Symbol, place it at the first of the name list, so that IINA running
  /// on the latest version of macOS can make use of it; IINA running on a older version of macOS will fallback to a symbol
  /// in a previous release of SF Symbol. But the list of name must contain a symbol which is available in macOS 14 (SF Symbol 5).
  ///
  /// - Parameters:
  ///   - names: A list name of the SF Symbol. The name requires higher SF Symbol version must be at front, with fallback SF Symbol
  ///   names at later indexes. The last one must be available in macOS 14 (SF Symbol 5), otherwise a fatal error will occur.
  ///   - configuration: The symbol configuration for the SF symbol. Optional.
  @available(macOS 14.0, *)
  static func findSFSymbol(_ names: [String], withConfiguration configuration: NSImage.SymbolConfiguration? = nil) -> NSImage {
    for name in names {
      if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
        if let configuration, let configured = symbol.withSymbolConfiguration(configuration) {
          return configured
        }
        return symbol
      }
    }
    fatalError("Could not find SF Symbol: \(names)")
  }

}


extension NSVisualEffectView {
  func roundCorners(withRadius cornerRadius: CGFloat) {
    maskImage = .maskImage(cornerRadius: cornerRadius)
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
  static let key = NSUserInterfaceItemIdentifier("Key")
  static let value = NSUserInterfaceItemIdentifier("Value")
}

extension NSAppearance {
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
    return name == .darkAqua || name == .vibrantDark || name == .accessibilityHighContrastDarkAqua || name == .accessibilityHighContrastVibrantDark
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
  static func log(_ label: String, _ screen: NSScreen?, subsystem: Logger.Subsystem = .general) {
    guard let screen = screen else {
      Logger.log("\(label): nil", level: .warning, subsystem: subsystem)
      return
    }
    // Unfortunately localizedName is not available until macOS Catalina.
    let maxPossibleEDR = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
    let canEnableEDR = maxPossibleEDR > 1.0
    Logger.log("\(label): \"\(screen.localizedName)\" visible frame \(screen.visibleFrame) EDR: {supports=\(canEnableEDR) maxPotential=\(maxPossibleEDR) maxCurrent=\(screen.maximumExtendedDynamicRangeColorComponentValue)}", subsystem: subsystem)
  }
}

extension NSWindow {

  /// Return the screen to use by default for this window.
  ///
  /// This method searches for a screen to use in this order:
  /// - `window!.screen` The screen where most of the window is on; it is `nil` when the window is offscreen.
  /// - `NSScreen.main` The screen containing the window that is currently receiving keyboard events.
  /// - `NSScreen.screens[0]` The primary screen of the user’s system.
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
    process.executableURL = URL(fileURLWithPath: cmd[0])
    process.currentDirectoryURL = currentDir
    process.arguments = [String](cmd.dropFirst())
    process.standardOutput = stdout
    process.standardError = stderr
    process.launch()
    process.waitUntilExit()

    return (process, stdout, stderr)
  }
}
