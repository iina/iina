import Cocoa

func argument(_ name: String) -> String? {
  guard let index = CommandLine.arguments.firstIndex(of: name) else { return nil }
  return CommandLine.arguments[index + 1]
}

let defaults = UserDefaults.standard
let nativeOnly = CommandLine.arguments.contains("--native")
let useSystem = CommandLine.arguments.contains("--system")
let appearanceKeys = ["AppleAccentColor", "AppleHighlightColor", "AppleAquaColorVariant"]

// Install test inputs only in this process. Setting the volatile domain directly
// also avoids Foundation interpreting negative palette codes as option names.
var inputArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
if let code = argument("--accent-code").flatMap(Int.init) {
  inputArguments["AppleAccentColor"] = code
  inputArguments["AppleAquaColorVariant"] = code == -1 ? 6 : 1
}
if let highlight = argument("--highlight") {
  inputArguments["AppleHighlightColor"] = highlight
}
inputArguments["accent-test-sentinel"] = "keep"
defaults.setVolatileDomain(inputArguments, forName: UserDefaults.argumentDomain)

let beforeGlobal = defaults.persistentDomain(forName: UserDefaults.globalDomain) as NSDictionary?
let bundleID = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
let beforePersistent = defaults.persistentDomain(forName: bundleID) as NSDictionary?
let sourceHighlight = defaults.string(forKey: "AppleHighlightColor")
if !nativeOnly {
  AppAccentColor.configure(useSystemAccent: useSystem)
  assert(AppAccentColor.usesSystemAccent == useSystem)
}
let configuredArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
for (key, value) in inputArguments where !appearanceKeys.contains(key) {
  assert((configuredArguments[key] as? NSObject) == (value as? NSObject), "Lost unrelated argument: \(key)")
}
if nativeOnly || useSystem {
  assert((configuredArguments as NSDictionary) == (inputArguments as NSDictionary))
} else {
  assert(defaults.integer(forKey: "AppleAccentColor") == 4)
  assert(defaults.integer(forKey: "AppleAquaColorVariant") == 1)
  assert(defaults.string(forKey: "AppleHighlightColor") == "0.698039 0.843137 1.000000 Blue")
}

_ = NSApplication.shared
var results: [[String: Any]] = []
for name in [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
  NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
    let nativeAccent = NSColor.controlAccentColor.usingColorSpace(.sRGB)!
    let color = nativeOnly ? nativeAccent : AppAccentColor.color.usingColorSpace(.sRGB)!
    let highlight = NSColor.selectedTextBackgroundColor.usingColorSpace(.sRGB)!
    func components(_ color: NSColor) -> [CGFloat] {
      [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
    }
    if !nativeOnly {
      if !useSystem {
        assert(color.blueComponent > 0.9 && color.redComponent < 0.2, "Blue fallback failed: \(color)")
      }
      let text = AppAccentColor.textColor.usingColorSpace(.sRGB)!
      if useSystem {
        func linear(_ c: CGFloat) -> CGFloat {
          c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) +
          0.0722 * linear(color.blueComponent)
        let contrast = text.redComponent < 0.5 ? (luminance + 0.05) / 0.05 : 1.05 / (luminance + 0.05)
        assert(contrast >= 4.5, "Custom title contrast failed: \(contrast)")
      } else {
        assert(text == NSColor.white.usingColorSpace(.sRGB)!)
      }
      let fallback = NSColor.white
      let fill = AppAccentColor.playbackFill(fallback: fallback).usingColorSpace(.sRGB)!
      assert(fill == (useSystem ? color : fallback.usingColorSpace(.sRGB)!))
    }
    results.append(["appearance": name.rawValue, "accent": components(color),
                    "nativeAccent": components(nativeAccent),
                    "textHighlight": components(highlight)])
  }
}

if !nativeOnly {
  // Simulate a settings edit without persisting a preference in any domain.
  var changedArguments = configuredArguments
  changedArguments["useSystemAccentColor"] = !useSystem
  defaults.setVolatileDomain(changedArguments, forName: UserDefaults.argumentDomain)
  assert(AppAccentColor.usesSystemAccent == useSystem)
  if useSystem {
    changedArguments["AppleHighlightColor"] = "0.123456 0.234567 0.345678 Other"
    defaults.setVolatileDomain(changedArguments, forName: UserDefaults.argumentDomain)
    let updated = AppAccentColor.color.usingColorSpace(.sRGB)!
    assert(abs(updated.redComponent - 0.123456) < 1e-12)
    assert(abs(updated.greenComponent - 0.234567) < 1e-12)
    assert(abs(updated.blueComponent - 0.345678) < 1e-12)
  }
}
assert((defaults.persistentDomain(forName: UserDefaults.globalDomain) as NSDictionary?) == beforeGlobal)
assert((defaults.persistentDomain(forName: bundleID) as NSDictionary?) == beforePersistent)

let data = try JSONSerialization.data(withJSONObject: [
  "mode": nativeOnly ? "native" : (useSystem ? "system" : "blue"),
  "checks": "passed", "sourceHighlight": sourceHighlight ?? "<absent>", "colors": results
], options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
