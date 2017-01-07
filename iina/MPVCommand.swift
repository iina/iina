import Foundation

struct MPVCommand: RawRepresentable {

  typealias RawValue = String

  var rawValue: RawValue

  init(_ string: String) { self.rawValue = string }

  init?(rawValue: RawValue) { self.rawValue = rawValue }

  /** ignore */
  static let ignore = MPVCommand("ignore")
  /** seek <seconds> [relative|absolute|absolute-percent|relative-percent|exact|keyframes] */
  static let seek = MPVCommand("seek")
  /** revert-seek [mode] */
  static let revertSeek = MPVCommand("revert-seek")
  /** frame-step */
  static let frameStep = MPVCommand("frame-step")
  /** frame-back-step */
  static let frameBackStep = MPVCommand("frame-back-step")
  /** set <property> "<value>" */
  static let set = MPVCommand("set")
  /** add <property> [<value>] */
  static let add = MPVCommand("add")
  /** cycle <property> [up|down] */
  static let cycle = MPVCommand("cycle")
  /** multiply <property> <factor> */
  static let multiply = MPVCommand("multiply")
  /** screenshot [subtitles|video|window|- [single|each-frame]] */
  static let screenshot = MPVCommand("screenshot")
  /** screenshot-to-file "<filename>" [subtitles|video|window] */
  static let screenshotToFile = MPVCommand("screenshot-to-file")
  /** playlist-next [weak|force] */
  static let playlistNext = MPVCommand("playlist-next")
  /** playlist-prev [weak|force] */
  static let playlistPrev = MPVCommand("playlist-prev")
  /** loadfile "<file>" [replace|append|append-play [options]] */
  static let loadfile = MPVCommand("loadfile")
  /** loadlist "<playlist>" [replace|append] */
  static let loadlist = MPVCommand("loadlist")
  /** playlist-clear */
  static let playlistClear = MPVCommand("playlist-clear")
  /** playlist-remove current|<index> */
  static let playlistRemove = MPVCommand("playlist-remove")
  /** playlist-move <index1> <index2> */
  static let playlistMove = MPVCommand("playlist-move")
  /** playlist-shuffle */
  static let playlistShuffle = MPVCommand("playlist-shuffle")
  /** run "command" "arg1" "arg2" ... */
  static let run = MPVCommand("run")
  /** quit [<code>] */
  static let quit = MPVCommand("quit")
  /** quit-watch-later [<code>] */
  static let quitWatchLater = MPVCommand("quit-watch-later")
  /** sub-add "<file>" [<flags> [<title> [<lang>]]] */
  static let subAdd = MPVCommand("sub-add")
  /** sub-remove [<id>] */
  static let subRemove = MPVCommand("sub-remove")
  /** sub-reload [<id>] */
  static let subReload = MPVCommand("sub-reload")
  /** sub-step <skip> */
  static let subStep = MPVCommand("sub-step")
  /** sub-seek <skip> */
  static let subSeek = MPVCommand("sub-seek")
  /** osd [<level>] */
  static let osd = MPVCommand("osd")
  /** print-text "<string>" */
  static let printText = MPVCommand("print-text")
  /** show-text "<string>" [<duration>|- [<level>]] */
  static let showText = MPVCommand("show-text")
  /** show-progress */
  static let showProgress = MPVCommand("show-progress")
  /** write-watch-later-config */
  static let writeWatchLaterConfig = MPVCommand("write-watch-later-config")
  /** stop */
  static let stop = MPVCommand("stop")
  /** mouse <x> <y> [<button> [single|double]] */
  static let mouse = MPVCommand("mouse")
  /** keypress <key_name> */
  static let keypress = MPVCommand("keypress")
  /** keydown <key_name> */
  static let keydown = MPVCommand("keydown")
  /** keyup [<key_name>] */
  static let keyup = MPVCommand("keyup")
  /** audio-add "<file>" [<flags> [<title> [<lang>]]] */
  static let audioAdd = MPVCommand("audio-add")
  /** audio-remove [<id>] */
  static let audioRemove = MPVCommand("audio-remove")
  /** audio-reload [<id>] */
  static let audioReload = MPVCommand("audio-reload")
  /** rescan-external-files [<mode>] */
  static let rescanExternalFiles = MPVCommand("rescan-external-files")
  /** af set|add|toggle|del|clr "filter1=params,filter2,..." */
  static let af = MPVCommand("af")
  /** vf set|add|toggle|del|clr "filter1=params,filter2,..." */
  static let vf = MPVCommand("vf")
  /** cycle-values ["!reverse"] <property> "<value1>" "<value2>" ... */
  static let cycleValues = MPVCommand("cycle-values")
  /** enable-section "<section>" [flags] */
  static let enableSection = MPVCommand("enable-section")
  /** disable-section "<section>" */
  static let disableSection = MPVCommand("disable-section")
  /** define-section "<section>" "<contents>" [default|force] */
  static let defineSection = MPVCommand("define-section")
  /** overlay-add <id> <x> <y> "<file>" <offset> "<fmt>" <w> <h> <stride> */
  static let overlayAdd = MPVCommand("overlay-add")
  /** overlay-remove <id> */
  static let overlayRemove = MPVCommand("overlay-remove")
  /** script-message "<arg1>" "<arg2>" ... */
  static let scriptMessage = MPVCommand("script-message")
  /** script-message-to "<target>" "<arg1>" "<arg2>" ... */
  static let scriptMessageTo = MPVCommand("script-message-to")
  /** script-binding "<name>" */
  static let scriptBinding = MPVCommand("script-binding")
  /** ab-loop */
  static let abLoop = MPVCommand("ab-loop")
  /** drop-buffers */
  static let dropBuffers = MPVCommand("drop-buffers")
  /** screenshot-raw [subtitles|video|window] */
  static let screenshotRaw = MPVCommand("screenshot-raw")
  /** vf-command "<label>" "<cmd>" "<args>" */
  static let vfCommand = MPVCommand("vf-command")
  /** af-command "<label>" "<cmd>" "<args>" */
  static let afCommand = MPVCommand("af-command")
  /** apply-profile "<name>" */
  static let applyProfile = MPVCommand("apply-profile")
  /** load-script "<path>" */
  static let loadScript = MPVCommand("load-script")
}
