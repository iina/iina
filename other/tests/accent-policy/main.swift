import Cocoa

struct PolicyFailure: Error, CustomStringConvertible {
  let description: String
}

var checkCount = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  checkCount += 1
  if !condition() { throw PolicyFailure(description: message) }
}

let appearances: [NSAppearance.Name] = [
  .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua
]

func components(_ color: NSColor, appearance: NSAppearance) throws -> [Double] {
  var resolved: NSColor?
  appearance.performAsCurrentDrawingAppearance { resolved = color.usingColorSpace(.sRGB) }
  guard let resolved else { throw PolicyFailure(description: "Cannot resolve sRGB color") }
  return [Double(resolved.redComponent), Double(resolved.greenComponent),
          Double(resolved.blueComponent), Double(resolved.alphaComponent)]
}

func same(_ lhs: [Double], _ rhs: [Double]) -> Bool {
  lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { abs($0 - $1) < 1e-12 }
}

func hex(_ rgb: [Double]) -> String {
  let bytes = rgb.prefix(3).map { Int((min(1, max(0, $0)) * 255).rounded()) }
  return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
}

func contrast(_ foreground: [Double], _ background: [Double]) -> Double {
  func luminance(_ color: [Double]) -> Double {
    let linear = color.prefix(3).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
  }
  let values = [luminance(foreground), luminance(background)].sorted()
  return (values[1] + 0.05) / (values[0] + 0.05)
}

func snapshots() -> [[String: Any]] {
  appearances.map {
    let appearance = NSAppearance(named: $0)!
    return AppAccentColor.snapshot(appearance: appearance)
  }
}

func run(_ specification: [String: Any]) throws -> [String: Any] {
  guard let bundleID = Bundle.main.bundleIdentifier,
        bundleID.hasPrefix("org.iina.tests.accentpolicy.") else {
    throw PolicyFailure(description: "Refusing to run outside the isolated test bundle")
  }
  let defaults = UserDefaults.standard
  defaults.removePersistentDomain(forName: bundleID)
  defer {
    defaults.removePersistentDomain(forName: bundleID)
    defaults.synchronize()
  }

  let beforeGlobal = defaults.persistentDomain(forName: UserDefaults.globalDomain) as NSDictionary?
  var seeded = specification["stored"] as? [String: Any] ?? [:]
  seeded["testPersistentSentinel"] = "preserve"
  // These deliberately differ from the volatile inputs. Blue must not rewrite
  // application-persistent appearance preferences, either.
  seeded["AppleAccentColor"] = 5
  seeded["AppleAquaColorVariant"] = 1
  seeded["AppleHighlightColor"] = "0.3 0.2 0.1 Other"
  defaults.setPersistentDomain(seeded, forName: bundleID)
  defaults.synchronize()

  var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
  arguments["testVolatileSentinel"] = "preserve"
  let nativeInput: [String: Any] = [
    "AppleAccentColor": -2, "AppleAquaColorVariant": 1,
    "AppleHighlightColor": "0.456984 0.081313 0.184124 Other"
  ]
  if specification["restoreAbsentArguments"] as? Bool != true {
    arguments.merge(nativeInput) { _, new in new }
  }
  defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)

  let expectedSource = specification["expectedSource"] as! Int
  let identifiers = ["defaultBlue", "systemAccent", "textHighlight", "custom"]
  let beforeConfigure = defaults.persistentDomain(forName: bundleID) as NSDictionary?
  try check(AppAccentColor.savedSource(defaults: defaults).rawValue == expectedSource,
            "savedSource did not honor migration/precedence")
  try check((defaults.persistentDomain(forName: bundleID) as NSDictionary?) == beforeConfigure,
            "savedSource unexpectedly persisted a choice")

  // Mirror production order: migrate before registering the new default.
  AppAccentColor.configure(defaults: defaults)
  defaults.register(defaults: [AppAccentColor.sourcePreferenceKey: 2,
                              AppAccentColor.customColorPreferenceKey: AppAccentColor.defaultCustomColor])
  try check(AppAccentColor.source.rawValue == expectedSource, "Applied source differs from saved policy")
  try check(AppAccentColor.usesSystemAccent == (expectedSource != 0), "Compatibility state changed")
  try check(defaults.object(forKey: AppAccentColor.sourcePreferenceKey) != nil, "Migration did not persist a source")
  let afterFirstConfigure = defaults.persistentDomain(forName: bundleID)!
  if let retained = specification["retainedSourceValue"] {
    try check((afterFirstConfigure[AppAccentColor.sourcePreferenceKey] as? NSObject) == (retained as? NSObject),
              "A valid new source was unnecessarily rewritten")
  } else {
    try check((afterFirstConfigure[AppAccentColor.sourcePreferenceKey] as? NSNumber)?.intValue == expectedSource,
              "Missing/malformed source was not sanitized to a valid integer")
  }

  // Once migrated, changing the obsolete key must not affect the new policy.
  defaults.set(expectedSource == 0, forKey: "useSystemAccentColor")
  try check(AppAccentColor.savedSource(defaults: defaults).rawValue == expectedSource,
            "Legacy key overrode an already migrated source")
  AppAccentColor.configure(defaults: defaults)
  try check(AppAccentColor.source.rawValue == expectedSource, "Second configuration changed sanitized policy")
  try check((defaults.persistentDomain(forName: bundleID)?[AppAccentColor.sourcePreferenceKey] as? NSObject) ==
            (afterFirstConfigure[AppAccentColor.sourcePreferenceKey] as? NSObject),
            "Second configuration changed the sanitized source")

  if specification["restorePolicy"] as? Bool == true {
    // Do this before touching AppKit's color caches, as production requires.
    AppAccentColor.configure(source: .defaultBlue, defaults: defaults)
    var duringBlue = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
    duringBlue["addedDuringBlue"] = "preserve"
    defaults.setVolatileDomain(duringBlue, forName: UserDefaults.argumentDomain)
    AppAccentColor.configure(source: .systemAccent, defaults: defaults)
    let restored = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
    for key in ["AppleAccentColor", "AppleAquaColorVariant", "AppleHighlightColor"] {
      try check((restored[key] as? NSObject) == (arguments[key] as? NSObject),
                "Blue override did not restore prior argument: \(key)")
    }
    try check(restored["addedDuringBlue"] as? String == "preserve", "Restore removed a later unrelated argument")
  }

  if let rgba = specification["explicitCustom"] as? [Double] {
    let custom = NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
    AppAccentColor.configure(source: .custom, customColor: custom, defaults: defaults)
  }

  let configuredArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
  try check(configuredArguments["testVolatileSentinel"] as? String == "preserve", "Lost unrelated argument")
  if expectedSource == 0 {
    try check(defaults.integer(forKey: "AppleAccentColor") == 4, "Blue did not overlay native accent")
    try check(defaults.string(forKey: "AppleHighlightColor") == "0.698039 0.843137 1.000000 Blue",
              "Blue did not overlay native highlight")
  } else if specification["restorePolicy"] as? Bool != true {
    for (key, value) in arguments {
      try check((configuredArguments[key] as? NSObject) == (value as? NSObject), "Non-blue mode rewrote arguments: \(key)")
    }
  }

  _ = NSApplication.shared
  NSApp.setActivationPolicy(.prohibited)
  let appliedSource = AppAccentColor.source
  let expectedColor = specification["expectedColor"] as? [Double]
  var colors: [[String: Any]] = []
  for appearanceName in appearances {
    let appearance = NSAppearance(named: appearanceName)!
    let applied = try components(AppAccentColor.color, appearance: appearance)
    let native = try components(NSColor.controlAccentColor, appearance: appearance)
    let text = try components(AppAccentColor.textColor, appearance: appearance)
    let snapshot = AppAccentColor.snapshot(appearance: appearance)
    try check(Set(snapshot.keys) == ["version", "source", "accentColor", "accentTextColor"], "Snapshot shape changed")
    try check(snapshot["version"] as? Int == 1, "Snapshot version changed")
    try check(snapshot["source"] as? String == identifiers[appliedSource.rawValue], "Unstable source identifier")
    try check(snapshot["accentColor"] as? String == hex(applied), "Snapshot differs from applied color")
    try check(snapshot["accentTextColor"] as? String == hex(text), "Snapshot differs from applied foreground")
    try check(applied[3] == 1 && text[3] == 1, "Policy exposed a translucent color")
    if let expectedColor {
      try check(same(applied, expectedColor), "Applied RGB differs from expected launch value: \(applied)")
    } else {
      try check(same(applied, native), "Native system mode differs from AppKit accent")
    }
    if appliedSource == .systemAccent && specification["restoreAbsentArguments"] as? Bool != true {
      try check(!same(applied, [0.456984, 0.081313, 0.184124, 1]), "Native accent incorrectly uses raw highlight")
      try check(snapshot["accentColor"] as? String == "#007AFF", "Multicolor fixture did not resolve native blue")
    }
    let ratio = contrast(text, applied)
    if appliedSource == .defaultBlue {
      // An explicit compatibility exception: original blue keeps white titles.
      try check(same(text, [1, 1, 1, 1]), "Default blue lost legacy white titles")
    } else {
      try check(ratio >= 4.5, "Applied foreground contrast is below 4.5: \(ratio)")
    }
    colors.append(["appearance": appearanceName.rawValue, "color": applied, "nativeAccent": native,
                   "text": text, "contrast": ratio, "snapshot": snapshot,
                   "legacyWhiteException": appliedSource == .defaultBlue])
  }

  let beforePending = snapshots() as NSArray
  defaults.set((appliedSource.rawValue + 1) % 4, forKey: AppAccentColor.sourcePreferenceKey)
  defaults.set("#010203", forKey: AppAccentColor.customColorPreferenceKey)
  try check(AppAccentColor.source == appliedSource, "Pending source edit changed the current launch")
  try check((snapshots() as NSArray) == beforePending, "Pending source/custom edits leaked into snapshots")

  var updatedArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
  updatedArguments["AppleHighlightColor"] = "0.12 0.34 0.56 Other"
  defaults.setVolatileDomain(updatedArguments, forName: UserDefaults.argumentDomain)
  for (index, appearanceName) in appearances.enumerated() {
    let appearance = NSAppearance(named: appearanceName)!
    let updated = try components(AppAccentColor.color, appearance: appearance)
    if appliedSource == .textHighlight {
      try check(same(updated, [0.12, 0.34, 0.56, 1]), "OS highlight did not update dynamically")
      try check(AppAccentColor.snapshot(appearance: appearance)["accentColor"] as? String == "#1F578F",
                "Dynamic highlight snapshot did not update")
    } else {
      try check(same(updated, colors[index]["color"] as! [Double]), "OS highlight altered a fixed/native policy")
    }
  }

  let validHex = [("#000000", "#000000"), ("  #aBcD09\n", "#ABCD09"), ("#FFFFFF", "#FFFFFF")]
  for (input, expected) in validHex {
    try check(AppAccentColor.normalizedHexColor(input) == expected, "Canonical hex failed: \(input)")
  }
  for invalid: String? in [nil, "", "007AFF", "#FFF", "#007AFF00", "#GG0000", "#１２３４５６", "#12 3456"] {
    try check(AppAccentColor.normalizedHexColor(invalid) == nil, "Invalid hex was accepted: \(invalid ?? "nil")")
  }
  for invalid: String? in [nil, "", "0.1 0.2", "NaN 0 0 Other", "inf 0 0 Other", "-0.1 0 0 Other", "0 0 1.1 Other"] {
    try check(AppAccentColor.highlightColor(from: invalid) == nil, "Invalid highlight was accepted")
  }
  let gray = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 0.1)
  try check(AppAccentColor.hexString(for: gray) == "#808080", "Hex conversion failed rounding/opacity")
  let translucentCustom = NSColor(srgbRed: 0.75, green: 0.25, blue: 0.5, alpha: 0.2)
  try check(AppAccentColor.hexString(for: translucentCustom) == "#BF4080", "Hex conversion leaked alpha")

  let persisted = defaults.persistentDomain(forName: bundleID)!
  for key in ["AppleAccentColor", "AppleAquaColorVariant", "AppleHighlightColor", "testPersistentSentinel"] {
    try check((persisted[key] as? NSObject) == (seeded[key] as? NSObject), "Policy changed persistent key: \(key)")
  }
  try check((defaults.persistentDomain(forName: UserDefaults.globalDomain) as NSDictionary?) == beforeGlobal,
            "Policy modified global preferences")
  return ["case": specification["name"]!, "status": "passed", "checks": checkCount,
          "appliedSource": appliedSource.identifier, "colors": colors,
          "persistentAppearancePreserved": true, "globalPreferencesPreserved": true]
}

do {
  guard let marker = CommandLine.arguments.firstIndex(of: "--case"),
        marker + 1 < CommandLine.arguments.count,
        let input = CommandLine.arguments[marker + 1].data(using: .utf8),
        let specification = try JSONSerialization.jsonObject(with: input) as? [String: Any] else {
    throw PolicyFailure(description: "Missing case specification")
  }
  let result = try run(specification)
  let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
  print(String(data: data, encoding: .utf8)!)
} catch {
  fputs("Accent policy check failed after \(checkCount) checks: \(error)\n", stderr)
  exit(EXIT_FAILURE)
}
