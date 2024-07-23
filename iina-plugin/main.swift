//
//  main.swift
//  iina-plugin
//
//  Created by Hechen Li on 5/12/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation
import Mustache

func printPluginHelp() {
  print(
    """
    Usage: iina-plugin <command> [arguments]

    Commands:
        new <name> [--url=template_url]
            Create a new IINA plugin in the current directory with specified name.
    
            Options:
            --url=template_url:
                Use template_url as the plugin template. The default template is
                https://github.com/iina/iina-plugin-template/archive/refs/heads/master.zip.
    
        pack <dir>
            Compress a plugin folder into an .iinaplgz file.
    
        link <path>
            Create a symlink to the plugin folder at <path> so IINA can load it as
            a development package.
    
        unlink <path>
            Remove the plugin symlink from IINA's plugin folder.
    """)
}

let currentDirURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

let processInfo = ProcessInfo.processInfo

var userArgs = Array(processInfo.arguments.dropFirst())

if userArgs.contains(where: { $0 == "--help" || $0 == "-h" }) {
  printPluginHelp()
  exit(0)
}

if !handlePluginCommand(userArgs) {
  printPluginHelp()
}


func handlePluginCommand(_ args: [String]) -> Bool {
  guard args.count > 1 else { return false }
  
  switch args.first {
  case "new":
    return createPlugin(args.dropFirst())
  case "pack":
    return packPlugin(args.dropFirst())
  case "link":
    return linkPlugin(args.dropFirst())
  case "unlink":
    return unlinkPlugin(args.dropFirst())
  default:
    return false
  }
}

// MARK: - Commands

func createPlugin(_ args: ArraySlice<String>) -> Bool {
  var args = args
  var userTemplateURL: String?
  var idxToBeDropped: [Int] = []
  for (idx, arg) in args.enumerated() {
    if arg.hasPrefix("--url=") {
      userTemplateURL = String(arg[arg.index(arg.startIndex, offsetBy: 6)..<arg.endIndex])
      idxToBeDropped.append(idx)
    }
  }
  for idx in idxToBeDropped {
    args.remove(at: idx)
  }
  
  // plugin name
  let name: String
  if args.isEmpty {
    guard let name_ = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !name_.isEmpty else {
      print("Please enter a name.")
      exit(EXIT_FAILURE)
    }
    name = name_
  } else {
    name = args.first!
  }
  
  // plugin directory
  
  var pluginDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
#if MACOS_13_AVAILABLE
  if #available(macOS 13.0, *) {
    pluginDir.append(component: name)
  }
#else
  pluginDir.appendPathComponent(name)
#endif
  
  func printErrorAndExit(_ message: String) -> Never {
    print(message)
    try? FileManager.default.removeItem(at: pluginDir)
    exit(EXIT_FAILURE)
  }
  
  if FileManager.default.fileExists(atPath: pluginDir.path) {
    print("Directory \(pluginDir.path) already exists.")
    exit(EXIT_FAILURE)
  }
  
  // options
  
  print("")
  
  let hasGlobal = promptYesOrNo("Include a global entry?")
  let hasOverlay = promptYesOrNo("Create template for video overlay?")
  let hasSidebar = promptYesOrNo("Create template for a side bar view?")
  let hasWindow = promptYesOrNo("Create template for a standalone window?")
  var framework = "None"
  if hasOverlay || hasSidebar || hasWindow {
    framework = prompt("Use a frontend framework to build the user interface?",
                       chooseFrom: ["None", "React", "Vue"])
  }
  var useBundler = true
  if framework == "None" {
    useBundler = promptYesOrNo("Use a bundler (Parcel)?", defaultValue: false)
  } else {
    print("The Parcel bundler will be used.")
  }
  
  let templateData: [String: Any] = [
    "name": name,
    "hasGlobal": hasGlobal,
    "hasOverlay": hasOverlay,
    "hasSidebar": hasSidebar,
    "hasWindow": hasWindow,
    "useBundler": useBundler,
    "useVue": framework == "Vue",
    "useReact": framework == "React",
    "hasUI": (hasOverlay || hasSidebar || hasWindow) && useBundler
  ]
  
  print("\n----------\n")
  
  // Download the template. We uploaded the file
  // https://github.com/iina/iina-plugin-template/archive/refs/heads/master.zip
  // to iina.io to avoid GitHub access issues in China.
  let defaultTemplateURL = "https://dl.iina.io/plugin-template/master.zip"
  let templateURL = userTemplateURL ?? defaultTemplateURL
  
  // Use shell commands here for simplicity
  let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    .appendingPathComponent("iina-cli")
  do {
    try FileManager.default.createDirectory(at: tmpURL, withIntermediateDirectories: true)
  } catch {
    printErrorAndExit("Unable to create tmp directory. Error: \(error)")
  }
  print("Downloading to \(tmpURL.path)")
  
  let cmd = "curl -o template.zip \(templateURL) && unzip -oq template.zip -d template"
  var (process, stdout, stderr) = Process.run(["/bin/bash", "-c", cmd], at: tmpURL)
  
  guard process.terminationStatus == 0 else {
    let outText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "None"
    let errText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "None"
    printErrorAndExit("Unable to download the plugin template.\n\(outText)\n\(errText)")
  }
  (process, stdout, stderr) = Process.run(["/bin/bash", "-c", "ls template"], at: tmpURL)
  let outText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "None"
  let errText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "None"
  guard process.terminationStatus == 0 else {
    printErrorAndExit("Unable to download the plugin template.\n\(outText)\n\(errText)")
  }
  
  // if the previous command succeeded, stdout should be the folder name inside template/
  let templateDir = tmpURL.appendingPathComponent("template")
    .appendingPathComponent(outText.trimmingCharacters(in: .whitespacesAndNewlines))

  guard FileManager.default.fileExists(atPath: templateDir.path) else {
    printErrorAndExit("Unable to find the plugin template")
  }

  // create the plugin directory
  do {
    try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: false)
  } catch {
    printErrorAndExit("Unable to create the plugin folder at \(pluginDir.path).")
  }
  
  let fileListPath = url(".file-list", in: templateDir).path
  guard FileManager.default.fileExists(atPath: fileListPath) else {
    printErrorAndExit("The .file-list file doesnt exist in plugin template dir")
  }
  guard let fileList = try? Template(path: fileListPath).render(templateData) else {
    printErrorAndExit("Failed to render .file-list")
  }
  for file in linesByRemovingEmptyLines(fileList) {
    do {
      let src = url("\(file).template", in: templateDir)
      let dst = url(file, in: pluginDir)
      try createParentDirectory(dst)
      let dstContent = try Template(path: src.path).render(templateData)
      // Mustache will leave undesired empty lines in the rendering result.
      // Therefore, we simply remove all empty lines after rendering.
      // In the template, we use a line containing only "//" to indicate an intended empty line.
      var result = linesByRemovingEmptyLines(dstContent)
        .map { $0 == "//" ? "" : $0 }
        .joined(separator: "\n")
      // We need to remove trailing commas in json files.
      // This can happen after rendering the template.
      if dst.pathExtension == "json" {
        result = result.replacingOccurrences(of: ",([\\n\\s]*)\\}", with: "$1}", options: .regularExpression)
      }
      try result.write(to: dst, atomically: true, encoding: .utf8)
      print("...Copied \(file)")
    } catch {
      printErrorAndExit("Failed to create \(file), error: \(error)")
    }
  }
  
  print("Plugin directory created.")
  if useBundler {
    print("\n----------\n")
    print("Please run the following commands to install npm packages:")
    print("\n  cd \(name) && npm install\n")
    print("Use the following command to build the project:")
    print("\n  npm run build\n")
    print("Please read the plugin documentation at https://docs.iina.io and inspect the generated package.json for more info.")
  } else {
    print("Please read the plugin documentation at https://docs.iina.io.")
  }
  return true
}


func packPlugin(_ args: ArraySlice<String>) -> Bool {
  guard let path = args.first else {
    print("Please enter the plugin path.")
    return false
  }

  guard let pluginDir = resolvePluginDir(from: path) else {
    print("Plugin directory doesn't exist.")
    exit(EXIT_FAILURE)
  }
  
  let infoJsonPath = pluginDir.appendingPathComponent("Info.json").path
  guard FileManager.default.fileExists(atPath: infoJsonPath) else {
    print("Plugin directory doesn't contain Info.json.")
    exit(EXIT_FAILURE)
  }
  
  let plgzFileName = pluginDir.lastPathComponent.appending(".iinaplgz")
  let packagePath = currentDirURL.appendingPathComponent(plgzFileName).path
  if FileManager.default.fileExists(atPath: packagePath) {
    if !promptYesOrNo("File \(packagePath) already exists. Overwrite?") {
      exit(EXIT_SUCCESS)
    }
  }
  
  let cmd = "zip -ryq \(packagePath) . -x 'node_modules/*' -x '.*'"
  let (process, stdout, stderr) = Process.run(["/bin/bash", "-c", cmd], at: pluginDir)
  
  guard process.terminationStatus == 0 else {
    let outText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "None"
    let errText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "None"
    print("Unable to create the archive.\n\(outText)\n\(errText)")
    exit(EXIT_FAILURE)
  }
  
  print("Created archive \(packagePath)")
  return true
}


func linkPlugin(_ args: ArraySlice<String>) -> Bool {
  guard let path = args.first else {
    print("Please enter the plugin path.")
    return false
  }

  guard let pluginDir = resolvePluginDir(from: path) else {
    print("Plugin directory doesn't exist.")
    exit(EXIT_FAILURE)
  }

  let pluginDirName = pluginDir.lastPathComponent
  let dstName = "\(pluginDirName).iinaplugin-dev"
  do {
    try FileManager.default.createSymbolicLink(at: appSupportDir.appendingPathComponent(dstName),
                                               withDestinationURL: pluginDir)
  } catch {
    print("Unable to create the symlink, error: \(error)")
    exit(EXIT_FAILURE)
  }
  
  print("Created symlink \(dstName) under \(appSupportDir.path)")
  return true
}


func unlinkPlugin(_ args: ArraySlice<String>) -> Bool {
  guard let path = args.first else {
    print("Please enter the plugin path.")
    return false
  }

  guard let pluginDir = resolvePluginDir(from: path) else {
    print("Plugin directory doesn't exist.")
    exit(EXIT_FAILURE)
  }
  let pluginPath = pluginDir.path

  do {
    let res = try FileManager.default.contentsOfDirectory(at: appSupportDir,
                                                           includingPropertiesForKeys: [.isSymbolicLinkKey])
    let links = try res.filter {
      try $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink ?? false
    }
    for link in links {
      if try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == pluginPath {
        try FileManager.default.removeItem(at: link)
        print("Removed \(link.path)")
      }
    }
  } catch {
    print("Unable to remove the symlink, error: \(error)")
    exit(EXIT_FAILURE)
  }

  return true
}

// MARK: - Utilities

fileprivate var appSupportDir: URL {
  let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
  let bundleID = Bundle.main.bundleIdentifier ?? "com.colliderli.iina"
  return appSupportPath.first!.appendingPathComponent(bundleID).appendingPathComponent("plugins")
}

fileprivate func url(_ file: String, in dir: URL) -> URL {
  return dir.appendingPathComponent(file).standardized
}

fileprivate func createParentDirectory(_ path: URL) throws {
  let parent = path.deletingLastPathComponent()
  if FileManager.default.fileExists(atPath: parent.path) {
    return
  }
  try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
}

fileprivate func linesByRemovingEmptyLines(_ document: String) -> [String] {
  return document.split(separator: "\n")
    .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
    .filter { !$0.isEmpty }
}

fileprivate func resolvePluginDir(from path: String) -> URL? {
  let pluginDir: URL?
  if path.hasPrefix("/") {
    pluginDir = URL(string: path)?.standardized
  } else {
    pluginDir = URL(string: path, relativeTo: currentDirURL)?.standardized
  }
  return pluginDir
}

fileprivate extension Process {
  @discardableResult
  static func run(_ cmd: [String], at currentDir: URL? = nil) -> (process: Process, stdout: Pipe, stderr: Pipe) {
    guard cmd.count > 0 else {
      fatalError("Process.launch: the command should not be empty")
    }

    let (stdout, stderr) = (Pipe(), Pipe())
    let process = Process()
    process.executableURL = URL(fileURLWithPath: cmd[0])
    process.currentDirectoryURL = currentDir
    process.arguments = [String](cmd.dropFirst())
    process.standardOutput = stdout
    process.standardError = stderr
    process.launch()
    process.waitUntilExit()

    return (process, stdout, stderr)
  }
}

// MARK: - Command line helpers

func promptYesOrNo(_ message: String, defaultValue: Bool = false) -> Bool {
  print("\(message) (y/n, default: \(defaultValue ? "y" : "n")) ", terminator: "")
  guard let answer = readLine() else { return defaultValue }
  let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  if ["y", "yes"].contains(trimmedAnswer) {
    return true
  }
  if ["n", "no"].contains(trimmedAnswer) {
    return false
  }
  return defaultValue
}


func prompt(_ message: String, chooseFrom choices: [String]) -> String {
  assert(!choices.isEmpty)
  print(message)
  while true {
    for (i, choice) in choices.enumerated() {
      print("  \(i + 1): \(choice)")
    }
    print("Input a number (default: 1): ", terminator: "")
    if let answer = readLine(), !answer.isEmpty {
      if let idx = Int(answer), idx > 0, choices.count >= idx {
        return choices[idx - 1]
      }
    } else {
      return choices[0]
    }
  }
}

