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

var userArgs = Array(processInfo.arguments.dropFirst())

guard isStdin || (userArgs.count > 0 && userArgs.contains(where: { arg in !arg.hasPrefix("-") })) else {
  print(
    """
    No file/URL specified.

    Usage:
    iina-cli [--mpv-*] FILE

    --mpv-*: All mpv options are supported here, except those starting with "--no-".
             Example: --mpv-volume=20 --mpv-resume-playback=no

    You may also pipe to stdin directly.
    """)
  exit(0)
}

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
