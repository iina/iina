//
//  main.swift
//  iina-cli
//
//  Created by Collider LI on 6/12/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

func printHelp() {
  print(
    """
    Usage: iina-cli [arguments] [files] [-- mpv_option [...]]

    Arguments:
    --mpv-*:
            All mpv options are supported here, except those starting with "--no-".
            Example: --mpv-volume=20 --mpv-resume-playback=no
    --separate-windows | -w:
            Open all files in separate windows.
    --stdin, --no-stdin:
            You may also pipe to stdin directly. Sometimes iina-cli can detect whether
            stdin has file, but sometimes not. Therefore it's recommended to always
            supply --stdin when piping to iina, and --no-stdin when you are not intend
            to use stdin.
    --keep-running:
            Normally iina-cli launches IINA and quits immediately. Supply this option
            if you would like to keep it running until the main application exits.
    --music-mode:
            Enter music mode after opening the media.
    --pip:
            Enter Picture-in-Picture after opening the media. Music mode does not
            support Picture-in-Picture.
    --help | -h:
            Print this message.

    mpv Option:
    Raw mpv options without --mpv- prefix. All mpv options are supported here.
    Example: --volume=20 --no-resume-playback
    """)
}

guard var execURL = Bundle.main.executableURL else {
  print("Cannot get executable path.")
  exit(1)
}

let currentDirURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

execURL.resolveSymlinksInPath()

let processInfo = ProcessInfo.processInfo

let iinaPath = execURL.deletingLastPathComponent().appendingPathComponent("IINA").path

guard FileManager.default.fileExists(atPath: iinaPath) else {
  print("Cannot find IINA binary. This command line tool only works in IINA.app bundle.")
  exit(1)
}

let task = Process()
task.launchPath = iinaPath

// Check arguments

let userArgs = Array(processInfo.arguments.dropFirst())

if userArgs.contains("--music-mode"), userArgs.contains("--pip") {
  // Music mode does not support Picture-in-Picture. Combining these options is not permitted.
  print("Cannot specify both --music-mode and --pip")
  // Command line usage error.
  exit(EX_USAGE)
}

var isStdin = false
var userSpecifiedStdin = false
var keepRunning = false
var taskArgs: [String] = []

/// Set variables and derive `taskArgs` from `userArgs`:
for arg in userArgs {
  switch arg {
  case "--help", "-h":
    printHelp()
    exit(0)
  case "--stdin":
    isStdin = true
    userSpecifiedStdin = true
    taskArgs.append(arg)
  case "--no-stdin":
    isStdin = false
    userSpecifiedStdin = true
    // do not include in taskArgs
  case "--keep-running":
    keepRunning = true
    // do not include in taskArgs
  case "-w":
    taskArgs.append("--separate-windows")
  default:
    if !Regex.url.matches(arg),
       let encodedFilePath = arg.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
       let fileURL = URL(string: encodedFilePath, relativeTo: currentDirURL),
       FileManager.default.fileExists(atPath: fileURL.path) {
      taskArgs.append(fileURL.path)
    } else {
      taskArgs.append(arg)
    }
  }
}

// Handle stdin

if !userSpecifiedStdin {
  guard let stdin = InputStream(fileAtPath: "/dev/stdin") else {
    print("Cannot open stdin.")
    exit(1)
  }
  stdin.open()
  isStdin = stdin.hasBytesAvailable
}

if isStdin {
  task.standardInput = FileHandle.standardInput
  task.standardOutput = FileHandle.standardOutput
  if !userSpecifiedStdin {
    taskArgs.insert("--stdin", at: 0)
  }
} else {
  task.standardOutput = nil
  task.standardError = nil
}

task.arguments = taskArgs

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
  if isStdin || keepRunning {
    terminateTaskIfRunning()
  }
}

task.launch()

if isStdin || keepRunning {
  task.waitUntilExit()
}
