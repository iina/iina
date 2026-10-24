var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message)
  checks += 1
}
func strings(_ path: String) -> [String: String] {
  let data = try! Data(contentsOf: URL(fileURLWithPath: path))
  return try! PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: String]
}

if let index = CommandLine.arguments.firstIndex(of: "--expected-language") {
  let expected = CommandLine.arguments[index + 1]
  check(Bundle.main.preferredLocalizations.first == expected, "actual main bundle selects \(expected)")
}
let english = strings(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: "en.lproj")!)
let prefixes = ["settings.screenshotPlaySound.", "settings.keepOSCHidden.", "settings.oscDefaultPosition.", "settings.controlBarDefaultPosition", "settings.windowGeometry.",
                "settings.oscPosition.", "settings.previewContext.", "settings.oscArrowSeekSeconds.", "settings.oscRightClickAction.", "settings.oscDoubleClickAction."]
let settings = UIHelper(scope: "settings")
for (key, developmentValue) in english where prefixes.contains(where: { key.hasPrefix($0) }) {
  let selectedValue = Bundle.main.localizedString(forKey: key, value: nil, table: "Localizable")
  let expected = selectedValue == key ? developmentValue : selectedValue
  check(settings.localized(String(key.dropFirst("settings.".count))) == expected,
        "selected-language value or English fallback for \(key)")
}
check(settings.localized("missing.localization.audit") == "settings.missing.localization.audit",
      "an unknown key remains identifiable")
check(settings.localized("screenShotFormat.items.0") == "PNG (.png)", "VerbatimStrings fallback remains available")
let verbatim = UIHelper(table: "VerbatimStrings", scope: "settings")
check(verbatim.localized("screenShotFormat.items.0") == "PNG (.png)", "explicit table selection is retained")
if Bundle.main.preferredLocalizations.first == "ru" {
  check(settings.localized("themeMaterial.label") == "Внешний вид", "existing Russian translation is retained")
  check(settings.localized("oscPosition.points") == "pt", "missing Russian unit falls back to English")
}
print("Completed \(checks) production UIHelper resource checks; language \(Bundle.main.preferredLocalizations.first ?? "default"). No UI or preference writes.")
