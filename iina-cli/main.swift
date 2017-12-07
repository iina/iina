//
//  main.swift
//  iina-cli
//
//  Created by Collider LI on 6/12/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

guard let execURL = Bundle.main.executableURL else {
  print("Cannot get executable path.")
  exit(1)
}

let processInfo = ProcessInfo.processInfo

let iinaPath = execURL.deletingLastPathComponent().appendingPathComponent("IINA").path

guard FileManager.default.fileExists(atPath: iinaPath) else {
  print("Cannot find IINA binary. This command line tool only works in IINA.app bundle.")
  exit(1)
}

let task = Process()
task.launchPath = iinaPath

guard let stdin = InputStream(fileAtPath: "/dev/stdin") else {
  print("Cannot open stdin.")
  exit(1)
}
stdin.open()

let isStdin = stdin.hasBytesAvailable

// Check arguments

var userArgs = Array(processInfo.arguments.dropFirst())

if userArgs.contains("--help") || userArgs.contains("-h") {
  print(
    """
    Usage: iina-cli [arguments] [FILE] [-- mpv_option [...]]

    Arguments:
    --mpv-*:     All mpv options are supported here, except those starting with "--no-".
                 Example: --mpv-volume=20 --mpv-resume-playback=no
    --help | -h: Print this message.

    MPV Option:
    Raw mpv options without --mpv- prefix.
    Example: --volume=20

    You may also pipe to stdin directly.
    """)
  exit(0)
}

if let dashIndex = userArgs.index(of: "--") {
  userArgs.remove(at: dashIndex)
  for i in dashIndex..<userArgs.count {
    let arg = userArgs[i]
    if arg.hasPrefix("--") {
      userArgs[i] = "--mpv-\(arg.dropFirst(2))"
    }
  }
}

// Handle stdin

if isStdin {
  task.standardInput = FileHandle.standardInput
  task.standardOutput = FileHandle.standardOutput
  userArgs.insert("--stdin", at: 0)
} else {
  task.standardOutput = nil
}

task.arguments = userArgs

func terminateTaskIfRunning() {
  if task.isRunning {
    task.terminate()
  }
}

[SIGTERM, SIGINT].forEach { sig in
  signal(sig) { _ in
    terminateTaskIfRunning()
    exit(1)
  }
}

atexit {
  if isStdin {
    terminateTaskIfRunning()
  }
}

task.launch()

if isStdin {
  task.waitUntilExit()
}
