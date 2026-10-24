import Foundation

// PRODUCTION_ROUTING

var checks = 0, failures = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if value() { print("PASS:", message) }
  else { failures += 1; fputs("FAILED: \(message)\n", stderr) }
}
func seeks(_ text: String) -> Bool {
  OSDCommandRouting.commands(in: text).contains(where: OSDCommandRouting.explicitlySeeks)
}
func mutation(_ text: String) -> (String, OSDFeedbackValue?)? {
  OSDCommandRouting.commands(in: text).first.flatMap(OSDCommandRouting.propertyMutation)
}
func mutationIs(_ text: String, _ property: String, _ value: OSDFeedbackValue?) -> Bool {
  guard let result = mutation(text) else { return false }
  return result.0 == property && result.1 == value
}

let prefixes = ["no-osd", "osd-bar", "osd-msg", "osd-msg-bar", "osd-auto", "raw",
                "expand-properties", "repeatable", "nonrepeatable", "nonscalable", "async", "sync"]
for prefix in prefixes {
  check(seeks("\(prefix) seek 5"), "raw \(prefix) prefix retains explicit seeking")
  check(OSDCommandRouting.explicitlySeeks([prefix, "seek", "5"]),
        "array \(prefix) prefix retains explicit seeking")
}
check(seeks("no-osd raw async nonscalable seek -5 exact"), "multiple raw prefixes retain intent")
check(OSDCommandRouting.explicitlySeeks(["no-osd", "raw", "seek", "-5"]),
      "multiple array prefixes retain intent")

let explicit: [(String, Bool)] = [
  ("seek 5", true), ("seek -5 relative+exact", true), ("seek 50 absolute-percent", true),
  ("frame-back-step", true), ("frame_back_step", true), ("frame-step", false),
  ("frame-step 1", false), ("frame-step 2 play", false), ("frame-step 1 mute", false),
  ("frame-step 1 seek", true), ("frame-step -1", true), ("frame-step -2 mute", true),
  ("frame-step 0 seek", false),
  ("frame_step 1 seek", true), ("revert-seek", true), ("revert_seek", true),
  ("revert-seek mark", false), ("revert-seek mark-permanent", false),
  ("sub-seek 1", true), ("sub_seek -1 secondary", true),
  ("set time-pos 42", true), ("add time-pos 5", true), ("set percent-pos 50", true),
  ("set playback-time 42", true), ("add playback-time 5", true),
  ("set chapter 1", true), ("add chapter 1", true),
  ("af add @iina_aeq:lavfi=[equalizer=f=1000:g=3]", false),
  ("lavfi-complex-command iina_audio_eq_1_4 gain 3 yes", false),
  ("set lavfi-complex [aid1]anull[ao]", false),
  ("set video-aspect-override 4:3", false), ("set video-rotate 90", false),
  ("cycle pause", false), ("show-progress", false), ("show-text seek", false)
]
for (command, expected) in explicit {
  check(seeks(command) == expected, "classify \(command) as \(expected ? "deliberate seek" : "non-seek")")
}

check(OSDCommandRouting.commands(in: " ").isEmpty, "empty input has no mutation or seek")
check(OSDCommandRouting.commands(in: "no-osd raw").isEmpty, "prefix-only input has no command")
check(seeks("set speed 1.2; no-osd seek 10"), "a later semicolon command retains explicit intent")
check(OSDCommandRouting.commands(in: "set speed 1.2; seek 10").count == 2,
      "semicolon separates two commands")
check(!seeks("show-text hello;; seek 10"), "an empty trailing command prevents classification of ignored text")
check(!seeks("show-text \"literal; seek 10\""), "double-quoted semicolon cannot fabricate a seek")
check(!seeks("show-text 'literal; seek 10'"), "single-quoted semicolon cannot fabricate a seek")
check(!seeks("show-text `-literal; seek 10-`"), "custom-quoted semicolon cannot fabricate a seek")
check(!seeks("show-text hello # seek 10"), "trailing comment cannot fabricate a seek")
check(!seeks("show-text hello # comment\nseek 10"), "comment consumes the entire remaining flat command string")
check(seeks("show-text hello\\; seek 10"), "unquoted backslash does not escape mpv's command separator")
check(OSDCommandRouting.commands(in: "script-message foo \"\"") == [["script-message", "foo", ""]],
      "empty quoted argument retains its position")
check(OSDCommandRouting.commands(in: "script-message foo 'a\\b'") == [["script-message", "foo", "a\\b"]],
      "single quotes preserve literal backslashes")
check(OSDCommandRouting.commands(in: #"script-message foo "a\tb""#) == [["script-message", "foo", "a\tb"]],
      "double quotes decode mpv JSON-style escapes")
check(OSDCommandRouting.commands(in: #"set speed "\u0032""#) == [["set", "speed", "2"]],
      "double quotes decode Unicode escapes before matching property acknowledgements")
check(OSDCommandRouting.commands(in: #"script-message foo "\e\'\x41""#) == [["script-message", "foo", "\u{001B}'A"]],
      "double quotes retain mpv's C escape extensions")
check(OSDCommandRouting.commands(in: #"script-message foo "\uD83D\uDE00""#) == [["script-message", "foo", "😀"]],
      "paired Unicode escapes decode as the bundled parser does")
check(OSDCommandRouting.commands(in: "script-message foo\nbar") == [["script-message", "foo", "bar"]],
      "a newline is argument whitespace rather than a second command")
check(OSDCommandRouting.commands(in: "set volume 40; show-text \"broken; seek 10").isEmpty,
      "an unterminated quoted argument invalidates the entire command list")
check(OSDCommandRouting.commands(in: #"show-text "broken\q"; seek 10"#).isEmpty,
      "a rejected escape cannot fabricate pending seek intent")
check(mutationIs("set speed `-2-`", "speed", .number(2)),
      "literal custom quotes retain the concrete acknowledgement value")

for command in ["set", "set_property", "set-property"] {
  check(mutationIs("\(command) speed 1.25", "speed", .number(1.25)),
        "\(command) records its concrete property value")
}
check(mutationIs("set mute yes", "mute", .number(1)), "boolean yes matches a flag acknowledgement")
check(mutationIs("set mute no", "mute", .number(0)), "boolean no matches a flag acknowledgement")
check(mutationIs("set crop 4:3", "crop", .text("4:3")), "text values remain exact")
check(mutationIs("no-osd raw set volume 40", "volume", .number(40)), "raw prefixes do not hide a property mutation")
let prefixedArrayMutation = OSDCommandRouting.propertyMutation(["no-osd", "set", "volume", "40"])
check(prefixedArrayMutation?.0 == "volume" && prefixedArrayMutation?.1 == .number(40),
      "array prefixes do not hide a property mutation")
for command in ["add", "multiply", "cycle", "cycle-values", "cycle_values", "change-list"] {
  check(mutationIs("\(command) volume 2", "volume", nil),
        "\(command) supersedes old origin without inventing its final value")
}
check(mutationIs("cycle-values !reverse volume 40 60", "volume", nil),
      "cycle-values reverse mode attributes the actual property")
check(mutation("seek 5") == nil, "ordinary seeking does not mutate setting provenance")
check(mutation("af add lavfi=[equalizer=f=1000:g=3]") == nil,
      "audio graph refresh is not misidentified as a property seek command")

print("OSD command routing: \(checks - failures)/\(checks) extracted production syntax/classification checks passed; no native player opened.")
if failures > 0 { exit(1) }
