#!/usr/bin/xcrun swift

import Cocoa

extension String {
  var escaped: String {
    return self.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")
  }
}

struct StandardErrorOutputStream: TextOutputStream {
  let stderr = FileHandle.standardError

  func write(_ string: String) {
    if let data = string.data(using: .utf8) {
      stderr.write(data)
    }
  }
}

var stderr = StandardErrorOutputStream()

func error(_ message: String) -> Never {
  print(message, to: &stderr)
  exit(1)
}

func append(_ text: String, to fileURL: URL) {
  guard let fileHandle = try? FileHandle(forWritingTo: fileURL) else {
    error("Cannot open file \(fileURL).")
  }
  fileHandle.seekToEndOfFile()
  fileHandle.write(text.data(using: .utf8)!)
  fileHandle.closeFile()
}

let fm = FileManager.default

let callPath = CommandLine.arguments[0]
let selfURL: URL

if callPath.hasPrefix("/") {
  selfURL = URL(fileURLWithPath: callPath)
} else {
  selfURL = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(callPath)
}

let projRootURL = selfURL.deletingLastPathComponent()
  .deletingLastPathComponent()
  .appendingPathComponent("iina", isDirectory: true)

// base Localizable.strings file
let baseFileURL = projRootURL.appendingPathComponent("Base.lproj/Localizable.strings")

// lproj folders
guard let lProjURLs = try? fm
  .contentsOfDirectory(at: projRootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
  .filter { $0.hasDirectoryPath && $0.lastPathComponent.hasSuffix(".lproj") && $0.lastPathComponent != "Base.lproj" }, lProjURLs.count > 1 else {
    error("Cannot find localization directories.")
}

print("Checking Localizable.strings for \(lProjURLs.count) localizations……")

// Localizable.strings files
let stringFileURLs = lProjURLs.map { $0.appendingPathComponent("Localizable.strings") }

// make sure all files exist
stringFileURLs.forEach { url in
  guard fm.fileExists(atPath: url.path) else {
    error("Localizable.strings doesn't exist: \(url.path)")
  }
}

// read base file
guard let baseDict = NSDictionary(contentsOf: baseFileURL) as? [String: String] else {
  error("Base Localizable.strings doesn't exist.")
}

let baseKeys = baseDict.keys

var missingKeys: [(String, URL)] = []

// check l10n files
for stringFileURL in stringFileURLs {
  // read l10n file
  guard let l10nDict = NSDictionary(contentsOf: stringFileURL) as? [String: String] else {
    error("File \(stringFileURL.path) doesn't exist.")
  }
  for baseKey in baseKeys {
    if l10nDict[baseKey] == nil {
      missingKeys.append((baseKey, stringFileURL))
    }
  }
}

if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "--fix" {
  // fix
  print("Fixing errors……")
  for (key, file) in missingKeys {
    append("""

    /* FIXME: Using English localization instead */
    "\(key)" = "\(baseDict[key]!.escaped)";

    """, to: file)
    print("Fixed \(key) in \(file.path)")
  }
} else {
  // output error
  guard missingKeys.isEmpty else {
    error(missingKeys.map { "Missing key \"\($0.0)\" in \($0.1.path)." }.joined(separator: "\n"))
  }
}

print("Checking Finished.")
