import Foundation

struct MPVCommand: RawRepresentable {

  typealias RawValue = String

  var rawValue: RawValue

  init(_ string: String) { self.rawValue = string }

  init?(rawValue: RawValue) { self.rawValue = rawValue }

  /** ignore */
  static let ignore = MPVCommand("ignore")
  /** seek <target> [<flags>] */
  static let seek = MPVCommand("seek")
  /** revert-seek [<flags>] */
  static let revertSeek = MPVCommand("revert-seek")
  /** frame-step */
  static let frameStep = MPVCommand("frame-step")
  /** frame-back-step */
  static let frameBackStep = MPVCommand("frame-back-step")
  /** set <name> <value> */
  static let set = MPVCommand("set")
  /** add <name> [<value>] */
  static let add = MPVCommand("add")
  /** cycle <name> [<value>] */
  static let cycle = MPVCommand("cycle")
  /** multiply <name> <value> */
  static let multiply = MPVCommand("multiply")
  /** screenshot <flags> */
  static let screenshot = MPVCommand("screenshot")
  /** screenshot-to-file <filename> <flags> */
  static let screenshotToFile = MPVCommand("screenshot-to-file")
  /** playlist-next <flags> */
  static let playlistNext = MPVCommand("playlist-next")
  /** playlist-prev <flags> */
  static let playlistPrev = MPVCommand("playlist-prev")
  /** loadfile <url> [<flags> [<options>]] */
  static let loadfile = MPVCommand("loadfile")
  /** loadlist <url> [<flags>] */
  static let loadlist = MPVCommand("loadlist")
  /** playlist-clear */
  static let playlistClear = MPVCommand("playlist-clear")
  /** playlist-remove <index> */
  static let playlistRemove = MPVCommand("playlist-remove")
  /** playlist-move <index1> <index2> */
  static let playlistMove = MPVCommand("playlist-move")
  /** playlist-shuffle */
  static let playlistShuffle = MPVCommand("playlist-shuffle")
  /** playlist-unshuffle */
  static let playlistUnshuffle = MPVCommand("playlist-unshuffle")
  /** run <command> [<arg1> [<arg2> [...]]] */
  static let run = MPVCommand("run")
  /** subprocess */
  static let subprocess = MPVCommand("subprocess")
  /** quit [<code>] */
  static let quit = MPVCommand("quit")
  /** quit-watch-later [<code>] */
  static let quitWatchLater = MPVCommand("quit-watch-later")
  /** sub-add <url> [<flags> [<title> [<lang>]]] */
  static let subAdd = MPVCommand("sub-add")
  /** sub-remove [<id>] */
  static let subRemove = MPVCommand("sub-remove")
  /** sub-reload [<id>] */
  static let subReload = MPVCommand("sub-reload")
  /** sub-step <skip> */
  static let subStep = MPVCommand("sub-step")
  /** sub-seek <skip> */
  static let subSeek = MPVCommand("sub-seek")
  /** print-text <text> */
  static let printText = MPVCommand("print-text")
  /** show-text <text> [<duration>|-1 [<level>]] */
  static let showText = MPVCommand("show-text")
  /** expand-text <string> */
  static let expandText = MPVCommand("expand-text")
  /** expand-path "<string>" */
  static let expandPath = MPVCommand("expand-path")
  /** show-progress */
  static let showProgress = MPVCommand("show-progress")
  /** write-watch-later-config */
  static let writeWatchLaterConfig = MPVCommand("write-watch-later-config")
  /** stop */
  static let stop = MPVCommand("stop")
  /** mouse <x> <y> [<button> [<mode>]] */
  static let mouse = MPVCommand("mouse")
  /** keypress <name> */
  static let keypress = MPVCommand("keypress")
  /** keydown <name> */
  static let keydown = MPVCommand("keydown")
  /** keyup [<name>] */
  static let keyup = MPVCommand("keyup")
  /** keybind <name> <command> */
  static let keybind = MPVCommand("keybind")
  /** audio-add <url> [<flags> [<title> [<lang>]]] */
  static let audioAdd = MPVCommand("audio-add")
  /** audio-remove [<id>] */
  static let audioRemove = MPVCommand("audio-remove")
  /** audio-reload [<id>] */
  static let audioReload = MPVCommand("audio-reload")
  /** video-add <url> [<flags> [<title> [<lang>]]] */
  static let videoAdd = MPVCommand("video-add")
  /** video-remove [<id>] */
  static let videoRemove = MPVCommand("video-remove")
  /** video-reload [<id>] */
  static let videoReload = MPVCommand("video-reload")
  /** rescan-external-files [<mode>] */
  static let rescanExternalFiles = MPVCommand("rescan-external-files")
  /** af <operation> <value> */
  static let af = MPVCommand("af")
  /** vf <operation> <value> */
  static let vf = MPVCommand("vf")
  /** cycle-values [<"!reverse">] <property> <value1> [<value2> [...]] */
  static let cycleValues = MPVCommand("cycle-values")
  /** enable-section <name> [<flags>] */
  static let enableSection = MPVCommand("enable-section")
  /** disable-section <name> */
  static let disableSection = MPVCommand("disable-section")
  /** define-section <name> <contents> [<flags>] */
  static let defineSection = MPVCommand("define-section")
  /** overlay-add <id> <x> <y> <file> <offset> <fmt> <w> <h> <stride> */
  static let overlayAdd = MPVCommand("overlay-add")
  /** overlay-remove <id> */
  static let overlayRemove = MPVCommand("overlay-remove")
  /** osd-overlay */
  static let osdOverlay = MPVCommand("osd-overlay")
  /** script-message [<arg1> [<arg2> [...]]] */
  static let scriptMessage = MPVCommand("script-message")
  /** script-message-to <target> [<arg1> [<arg2> [...]]] */
  static let scriptMessageTo = MPVCommand("script-message-to")
  /** script-binding <name> */
  static let scriptBinding = MPVCommand("script-binding")
  /** ab-loop */
  static let abLoop = MPVCommand("ab-loop")
  /** drop-buffers */
  static let dropBuffers = MPVCommand("drop-buffers")
  /** screenshot-raw [<flags>] */
  static let screenshotRaw = MPVCommand("screenshot-raw")
  /** vf-command <label> <command> <argument> */
  static let vfCommand = MPVCommand("vf-command")
  /** af-command <label> <command> <argument> */
  static let afCommand = MPVCommand("af-command")
  /** apply-profile <name> */
  static let applyProfile = MPVCommand("apply-profile")
  /** load-script <filename> */
  static let loadScript = MPVCommand("load-script")
  /** change-list <name> <operation> <value> */
  static let changeList = MPVCommand("change-list")
  /** dump-cache <start> <end> <filename> */
  static let dumpCache = MPVCommand("dump-cache")
  /** ab-loop-dump-cache <filename> */
  static let abLoopDumpCache = MPVCommand("ab-loop-dump-cache")
  /** ab-loop-align-cache */
  static let abLoopAlignCache = MPVCommand("ab-loop-align-cache")
}
