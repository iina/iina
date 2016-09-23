import Foundation

struct MPVCommand {
  /** ignore */
  static let ignore = "ignore"
  /** seek <seconds> [relative|absolute|absolute-percent|relative-percent|exact|keyframes] */
  static let seek = "seek"
  /** revert-seek [mode] */
  static let revertSeek = "revert-seek"
  /** frame-step */
  static let frameStep = "frame-step"
  /** frame-back-step */
  static let frameBackStep = "frame-back-step"
  /** set <property> "<value>" */
  static let set = "set"
  /** add <property> [<value>] */
  static let add = "add"
  /** cycle <property> [up|down] */
  static let cycle = "cycle"
  /** multiply <property> <factor> */
  static let multiply = "multiply"
  /** screenshot [subtitles|video|window|- [single|each-frame]] */
  static let screenshot = "screenshot"
  /** screenshot-to-file "<filename>" [subtitles|video|window] */
  static let screenshotToFile = "screenshot-to-file"
  /** playlist-next [weak|force] */
  static let playlistNext = "playlist-next"
  /** playlist-prev [weak|force] */
  static let playlistPrev = "playlist-prev"
  /** loadfile "<file>" [replace|append|append-play [options]] */
  static let loadfile = "loadfile"
  /** loadlist "<playlist>" [replace|append] */
  static let loadlist = "loadlist"
  /** playlist-clear */
  static let playlistClear = "playlist-clear"
  /** playlist-remove current|<index> */
  static let playlistRemove = "playlist-remove"
  /** playlist-move <index1> <index2> */
  static let playlistMove = "playlist-move"
  /** playlist-shuffle */
  static let playlistShuffle = "playlist-shuffle"
  /** run "command" "arg1" "arg2" ... */
  static let run = "run"
  /** quit [<code>] */
  static let quit = "quit"
  /** quit-watch-later [<code>] */
  static let quitWatchLater = "quit-watch-later"
  /** sub-add "<file>" [<flags> [<title> [<lang>]]] */
  static let subAdd = "sub-add"
  /** sub-remove [<id>] */
  static let subRemove = "sub-remove"
  /** sub-reload [<id>] */
  static let subReload = "sub-reload"
  /** sub-step <skip> */
  static let subStep = "sub-step"
  /** sub-seek <skip> */
  static let subSeek = "sub-seek"
  /** osd [<level>] */
  static let osd = "osd"
  /** print-text "<string>" */
  static let printText = "print-text"
  /** show-text "<string>" [<duration>|- [<level>]] */
  static let showText = "show-text"
  /** show-progress */
  static let showProgress = "show-progress"
  /** write-watch-later-config */
  static let writeWatchLaterConfig = "write-watch-later-config"
  /** stop */
  static let stop = "stop"
  /** mouse <x> <y> [<button> [single|double]] */
  static let mouse = "mouse"
  /** keypress <key_name> */
  static let keypress = "keypress"
  /** keydown <key_name> */
  static let keydown = "keydown"
  /** keyup [<key_name>] */
  static let keyup = "keyup"
  /** audio-add "<file>" [<flags> [<title> [<lang>]]] */
  static let audioAdd = "audio-add"
  /** audio-remove [<id>] */
  static let audioRemove = "audio-remove"
  /** audio-reload [<id>] */
  static let audioReload = "audio-reload"
  /** rescan-external-files [<mode>] */
  static let rescanExternalFiles = "rescan-external-files"
  /** af set|add|toggle|del|clr "filter1=params,filter2,..." */
  static let af = "af"
  /** vf set|add|toggle|del|clr "filter1=params,filter2,..." */
  static let vf = "vf"
  /** cycle-values ["!reverse"] <property> "<value1>" "<value2>" ... */
  static let cycleValues = "cycle-values"
  /** enable-section "<section>" [flags] */
  static let enableSection = "enable-section"
  /** disable-section "<section>" */
  static let disableSection = "disable-section"
  /** define-section "<section>" "<contents>" [default|force] */
  static let defineSection = "define-section"
  /** overlay-add <id> <x> <y> "<file>" <offset> "<fmt>" <w> <h> <stride> */
  static let overlayAdd = "overlay-add"
  /** overlay-remove <id> */
  static let overlayRemove = "overlay-remove"
  /** script-message "<arg1>" "<arg2>" ... */
  static let scriptMessage = "script-message"
  /** script-message-to "<target>" "<arg1>" "<arg2>" ... */
  static let scriptMessageTo = "script-message-to"
  /** script-binding "<name>" */
  static let scriptBinding = "script-binding"
  /** ab-loop */
  static let abLoop = "ab-loop"
  /** drop-buffers */
  static let dropBuffers = "drop-buffers"
  /** screenshot-raw [subtitles|video|window] */
  static let screenshotRaw = "screenshot-raw"
  /** vf-command "<label>" "<cmd>" "<args>" */
  static let vfCommand = "vf-command"
  /** af-command "<label>" "<cmd>" "<args>" */
  static let afCommand = "af-command"
  /** apply-profile "<name>" */
  static let applyProfile = "apply-profile"
  /** load-script "<path>" */
  static let loadScript = "load-script"
}
