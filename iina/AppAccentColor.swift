//
//  AppAccentColor.swift
//  iina
//

import Cocoa

/// Establish the native accent policy before AppKit creates its appearance caches.
/// Keep this launch's UI consistent even when the preference changes in Settings.
enum AppAccentColor {
  enum Source: Int, CaseIterable {
    case defaultBlue = 0
    case systemAccent = 1
    case textHighlight = 2
    case custom = 3

    var identifier: String {
      switch self {
      case .defaultBlue: return "defaultBlue"
      case .systemAccent: return "systemAccent"
      case .textHighlight: return "textHighlight"
      case .custom: return "custom"
      }
    }
  }

  static let sourcePreferenceKey = "accentColorSource"
  static let customColorPreferenceKey = "customAccentColor"
  static let defaultCustomColor = "#007AFF"

  private(set) static var source: Source = .textHighlight
  static var usesSystemAccent: Bool { source != .defaultBlue }
  private static var appearanceDefaults = UserDefaults.standard
  private static var customColor = NSColor(srgbRed: 0, green: 122.0 / 255, blue: 1, alpha: 1)
  private static var blueOverride: (defaults: UserDefaults, original: [String: Any])?
  private static let appearanceKeys = ["AppleAccentColor", "AppleAquaColorVariant", "AppleHighlightColor"]

  /// Run before registering the new defaults, so a saved legacy off value is
  /// migrated to blue rather than obscured by the new highlight default.
  static func configure(defaults: UserDefaults = .standard) {
    let selected = savedSource(defaults: defaults)
    if storedSource(defaults: defaults) == nil {
      defaults.set(selected.rawValue, forKey: sourcePreferenceKey)
    }
    configure(source: selected, customColor: savedCustomColor(defaults: defaults), defaults: defaults)
  }

  static func savedSource(defaults: UserDefaults = .standard) -> Source {
    if let stored = storedSource(defaults: defaults) { return stored }
    if defaults.object(forKey: "useSystemAccentColor") != nil,
       !defaults.bool(forKey: "useSystemAccentColor") { return .defaultBlue }
    return .textHighlight
  }

  private static func storedSource(defaults: UserDefaults) -> Source? {
    let value = defaults.object(forKey: sourcePreferenceKey)
    if let number = value as? NSNumber {
      guard CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue == Double(number.intValue) else { return nil }
      return Source(rawValue: number.intValue)
    }
    if let string = value as? String, let integer = Int(string) {
      return Source(rawValue: integer)
    }
    return nil
  }

  /// Compatibility for the original binary preference and its native probes.
  static func configure(useSystemAccent: Bool, defaults: UserDefaults = .standard) {
    configure(source: useSystemAccent ? .textHighlight : .defaultBlue, defaults: defaults)
  }

  /// Establish one launch's policy. Saved UI choices are applied next launch.
  static func configure(source: Source, customColor: NSColor? = nil, defaults: UserDefaults = .standard) {
    if let previous = blueOverride {
      var arguments = previous.defaults.volatileDomain(forName: UserDefaults.argumentDomain)
      for key in appearanceKeys { arguments[key] = previous.original[key] }
      previous.defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
      blueOverride = nil
    }
    self.source = source
    appearanceDefaults = defaults
    self.customColor = (customColor ?? savedCustomColor(defaults: defaults))
      .usingColorSpace(.sRGB)?.withAlphaComponent(1) ?? savedCustomColor(defaults: defaults)
    guard source == .defaultBlue else { return }

    // AppKit has no application-wide tint setter (NSSwitch has no tint setter at
    // all). Scope its standard appearance preferences to this process. Never
    // write these keys to the app's persistent domain or the global domain.
    // This policy is applied only at startup; changing it requires a restart.
    var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
    blueOverride = (defaults, arguments.filter { appearanceKeys.contains($0.key) })
    arguments["AppleAccentColor"] = 4
    arguments["AppleAquaColorVariant"] = 1
    arguments["AppleHighlightColor"] = "0.698039 0.843137 1.000000 Blue"
    defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
  }

  /// Resolve system sources when drawn; custom RGB and the selected source stay
  /// fixed for this launch even while the settings contain a pending choice.
  static let color = NSColor(name: "IINAAccent") { appearance in
    switch source {
    case .custom:
      return customColor
    case .textHighlight:
      // AppKit's selectedTextBackgroundColor transforms this by light/dark mode.
      // Keep the actual chosen color, including the user's Other RGB value.
      if let highlight = highlightColor(from: appearanceDefaults.string(forKey: "AppleHighlightColor")) {
        return highlight
      }
    case .systemAccent, .defaultBlue:
      break
    }
    // An absent/invalid highlight denotes the automatic policy. Keep AppKit's
    // accent in that case; disabled mode has already overlaid standard blue.
    var nativeAccent = NSColor.controlAccentColor
    appearance.performAsCurrentDrawingAppearance {
      nativeAccent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
    }
    return nativeAccent
  }

  /// The picker and plugin contract use opaque, canonical sRGB hex colors.
  static func normalizedHexColor(_ string: String?) -> String? {
    guard let string else { return nil }
    let value = string.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard value.count == 7, value.first == "#",
          value.dropFirst().allSatisfy({ $0.isASCII && ("0"..."9" ~= $0 || "A"..."F" ~= $0) }) else { return nil }
    return value
  }

  static func savedCustomColor(defaults: UserDefaults = .standard) -> NSColor {
    let hex = normalizedHexColor(defaults.string(forKey: customColorPreferenceKey)) ?? defaultCustomColor
    let rgb = UInt32(hex.dropFirst(), radix: 16)!
    return NSColor(srgbRed: Double((rgb >> 16) & 255) / 255,
                   green: Double((rgb >> 8) & 255) / 255,
                   blue: Double(rgb & 255) / 255, alpha: 1)
  }

  static func hexString(for color: NSColor, appearance: NSAppearance? = nil) -> String? {
    var rgb: NSColor?
    let resolve = { rgb = color.usingColorSpace(.sRGB) }
    if let appearance { appearance.performAsCurrentDrawingAppearance(resolve) } else { resolve() }
    guard let rgb else { return nil }
    let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
    guard channels.allSatisfy({ $0.isFinite }) else { return nil }
    let bytes = channels.map { Int((min(1, max(0, $0)) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
  }

  /// Versioned read-only plugin tokens. Never expose pending preferences here.
  static func snapshot(appearance: NSAppearance? = nil) -> [String: Any] {
    let resolvedAppearance = appearance ?? NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
    return ["version": 1, "source": source.identifier,
            "accentColor": hexString(for: color, appearance: resolvedAppearance) ?? defaultCustomColor,
            "accentTextColor": hexString(for: textColor, appearance: resolvedAppearance) ?? "#FFFFFF"]
  }

  static func highlightColor(from preference: String?) -> NSColor? {
    guard let preference else { return nil }
    let components = preference.split(whereSeparator: \.isWhitespace).prefix(3).compactMap { Double($0) }
    guard components.count == 3,
          components.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
    return NSColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: 1)
  }

  /// Custom accent buttons need a contrasting title even for light system colors.
  static let textColor = NSColor(name: "IINAAccentText") { appearance in
    guard usesSystemAccent else { return .white }
    var foreground = NSColor.white
    appearance.performAsCurrentDrawingAppearance {
      guard let rgb = color.usingColorSpace(.sRGB) else { return }
      func linear(_ component: CGFloat) -> CGFloat {
        component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
      }
      let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) +
        0.0722 * linear(rgb.blueComponent)
      foreground = luminance > 0.179 ? .black : .white
    }
    return foreground
  }

  /// OSC fills retain their original neutral styling when system accents are off.
  static func playbackFill(fallback: NSColor) -> NSColor {
    usesSystemAccent ? color : fallback
  }
}
