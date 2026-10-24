import Foundation

fileprivate let IINA_PREFIX_IN_FILE = "#@iina"
enum Logger {
  enum Level { case warning }
  static func log(_ message: String, level: Level) {}
}
final class KeyMapping {
  let rawKey: String
  let rawAction: String
  let isIINACommand: Bool
  let comment: String?
  init(rawKey: String, rawAction: String, isIINACommand: Bool, comment: String?) {
    self.rawKey = rawKey; self.rawAction = rawAction
    self.isIINACommand = isIINACommand; self.comment = comment
  }
  // PRODUCTION_PARSER
}
var checks = 0
func check(_ value: Bool, _ message: String) {
  guard value else { print("FAIL: " + message); exit(1) }
  checks += 1
}
let path = CommandLine.arguments[1]
defer { try? FileManager.default.removeItem(atPath: path) }
let malformed = ["#@iina#comment", "#@iina", "#@iina ", "#@iina\t#comment",
                 "#@iina #comment", "F1", "F1 ", "F1 \u{2000}", "", "   ", "# comment"]
for text in malformed {
  try text.write(toFile: path, atomically: true, encoding: .utf8)
  check(KeyMapping.parseInputConf(at: path)?.isEmpty == true,
        "malformed/empty/comment line is skipped: \(text.debugDescription)")
}
for ending in ["", "\n", "\r\n"] {
  let text = "F1 show-text okay#comment" + ending
  try text.write(toFile: path, atomically: true, encoding: .utf8)
  let mapping = KeyMapping.parseInputConf(at: path)!
  check(mapping.count == 1, "inline comment retains its binding")
  check(mapping[0].rawAction == "show-text okay", "comment boundary retains final action character")
  check(mapping[0].comment?.trimmingCharacters(in: .whitespacesAndNewlines) == "comment", "comment text preserved")
}
try "#@iina Alt+Meta+m toggle-music-mode\nSPACE cycle pause\n".write(toFile: path, atomically: true, encoding: .utf8)
let normal = KeyMapping.parseInputConf(at: path)!
check(normal.count == 2, "normal application and mpv bindings both parse")
check(normal[0].isIINACommand && normal[0].rawAction == "toggle-music-mode", "IINA syntax preserved")
check(!normal[1].isIINACommand && normal[1].rawAction == "cycle pause", "mpv syntax preserved")
check(KeyMapping.parseInputConf(at: path + ".missing") == nil, "unreadable config remains nil")
print("Passed \(checks) production keybinding parser checks")
