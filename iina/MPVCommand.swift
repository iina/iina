import Foundation

struct MPVCommand: RawRepresentable {

  typealias RawValue = String

  var rawValue: RawValue

  init(_ string: String) { self.rawValue = string }

  init?(rawValue: RawValue) { self.rawValue = rawValue }

  /** seek <target> [<flags>] */
  static let seek = MPVCommand("seek")
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
  /** screenshot <flags> */
  static let screenshot = MPVCommand("screenshot")
  /** playlist-next <flags> */
  static let playlistNext = MPVCommand("playlist-next")
  /** playlist-prev <flags> */
  static let playlistPrev = MPVCommand("playlist-prev")
  /** loadfile <url> [<flags> [<options>]] */
  static let loadfile = MPVCommand("loadfile")
  /** playlist-clear */
  static let playlistClear = MPVCommand("playlist-clear")
  /** playlist-remove <index> */
  static let playlistRemove = MPVCommand("playlist-remove")
  /** playlist-move <index1> <index2> */
  static let playlistMove = MPVCommand("playlist-move")
  /** playlist-shuffle */
  static let playlistShuffle = MPVCommand("playlist-shuffle")
  /** quit [<code>] */
  static let quit = MPVCommand("quit")
  /** sub-add <url> [<flags> [<title> [<lang>]]] */
  static let subAdd = MPVCommand("sub-add")
  /** sub-reload [<id>] */
  static let subReload = MPVCommand("sub-reload")
  /** write-watch-later-config */
  static let writeWatchLaterConfig = MPVCommand("write-watch-later-config")
  /** stop [<flags>] */
  static let stop = MPVCommand("stop")
  /** keypress <name> */
  static let keypress = MPVCommand("keypress")
  /** audio-add <url> [<flags> [<title> [<lang>]]] */
  static let audioAdd = MPVCommand("audio-add")
  /** video-add <url> [<flags> [<title> [<lang> [<albumart>]]]] */
  static let videoAdd = MPVCommand("video-add")
  /** af <operation> <value> */
  static let af = MPVCommand("af")
  /** vf <operation> <value> */
  static let vf = MPVCommand("vf")
  /** ab-loop */
  static let abLoop = MPVCommand("ab-loop")
}
