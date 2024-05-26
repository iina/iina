//
//  DraggingDetect.swift
//  iina
//
//  Created by Yuze Jiang on 05/08/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

extension PlayerCore {

  /**
   Checks whether the path list contains playable file and performs early return if so. Don't use this method for a non-file URL.

   - Parameters:
     - paths: The list as an array of `String`.
   - Returns: Whether the path list contains playable file.
   */
  func hasPlayableFiles(in paths: [String]) -> Bool {
    for path in paths {
      if path.isDirectoryAsPath {
        // is directory, enumerate its content
        guard let dirEnumerator = FileManager.default.enumerator(atPath: path) else { return false }
        while let fileName = dirEnumerator.nextObject() as? String {
          // ignore hidden files
          guard !fileName.hasPrefix(".") else { continue }
          if Utility.playableFileExt.contains(fileName.lowercasedPathExtension) {
            return true
          }
        }
      } else {
        // is file, check extension
        if !Utility.blacklistExt.contains(path.lowercasedPathExtension) {
          return true
        }
      }
    }
    return false
  }

  /**
   Returns playable files contained in a URL list. Any non-file URL will be counted directly without further checking.

   - Parameters:
     - urls: The list as an array of `URL`.
   - Returns: URLs of all playable files as an array of `URL`.
   */
  func getPlayableFiles(in urls: [URL]) -> [URL] {
    var playableFiles: [URL] = []
    for url in urls {
      if !url.isFileURL {
        playableFiles.append(url)
        continue
      }
      if url.hasDirectoryPath {
        // is directory
        // `enumerator(at:includingPropertiesForKeys:)` doesn't work :(
        guard let dirEnumerator = FileManager.default.enumerator(atPath: url.path) else { return [] }
        while let fileName = dirEnumerator.nextObject() as? String {
          guard !fileName.hasPrefix(".") else { continue }
          if Utility.playableFileExt.contains(fileName.lowercasedPathExtension) {
            playableFiles.append(url.appendingPathComponent(fileName))
          }
        }
      } else {
        // is file
        if !Utility.blacklistExt.contains(url.pathExtension.lowercased()) {
          playableFiles.append(url)
        }
      }
    }
    return Array(Set(playableFiles)).sorted { url1, url2 in
      let folder1 = url1.deletingLastPathComponent(), folder2 = url2.deletingLastPathComponent()
      if folder1.absoluteString == folder2.absoluteString {
        return url1.lastPathComponent.localizedStandardCompare(url2.lastPathComponent) == .orderedAscending
      } else {
        return folder1.absoluteString < folder2.absoluteString
      }
    }
  }

  /**
   Checks whether a path list contains path to subtitle file.

   - Parameters:
     - paths: The list as an array of `String`.
   - Returns: Whether the path list contains path to subtitle file.
   */
  func hasSubtitleFile(in paths: [String]) -> Bool {
    return paths.contains {
      !$0.isDirectoryAsPath && Utility.supportedFileExt[.sub]!.contains($0.lowercasedPathExtension)
    }
  }

  /**
   Checks whether a URL is BD folder by checking the existence of "MovieObject.bdmv" and "index.bdmv".

   - Parameters:
     - url: The URL.
   - Returns: Whether the URL is a BD folder.
   */
  func isBDFolder(_ url: URL) -> Bool {
  
    func isBDMVFolder(_ url: URL) -> Bool {
      if let files = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
        return files.contains("MovieObject.bdmv") && files.contains("index.bdmv")
      }
      return false
    }
    
    if isBDMVFolder(url) {
      return true
    }
    
    let bdmvFolder = url.appendingPathComponent("BDMV")
    guard bdmvFolder.isExistingDirectory else { return false }
    return isBDMVFolder(bdmvFolder)
  }

  /**
   Get called for all drag-and-drop enabled window/views in their `draggingEntered(_:)`.

   - Parameters:
     - sender: The `NSDraggingInfo` object received in `draggingEntered(_:)`.
     - isPlaylist: True when the caller is `PlaylistViewController`
   - Returns: The `NSDragOperation`.
   */
  func acceptFromPasteboard(_ sender: NSDraggingInfo, isPlaylist: Bool = false) -> NSDragOperation {
    // ignore events from this window
    // must check `mainWindow.loaded` otherwise window will be lazy-loaded unexpectedly
    if mainWindow.loaded && (sender.draggingSource as? NSView)?.window === mainWindow.window {
      return []
    }

    // get info
    let pb = sender.draggingPasteboard
    guard let types = pb.types else { return [] }

    if types.contains(.nsFilenames) {
      guard var paths = pb.propertyList(forType: .nsFilenames) as? [String] else { return [] }
      paths = Utility.resolvePaths(paths)
      // check 3d lut files
      if paths.count == 1 && Utility.lut3dExt.contains(paths[0].lowercasedPathExtension) {
        return .copy
      }

      if isPlaylist {
        return hasPlayableFiles(in: paths) ? .copy : []
      } else {
        let theOnlyPathIsBDFolder = paths.count == 1 && isBDFolder(URL(fileURLWithPath: paths[0]))
        return theOnlyPathIsBDFolder ||
          hasPlayableFiles(in: paths) ||
          hasSubtitleFile(in: paths) ? .copy : []
      }
    } else if types.contains(.nsURL) {
      return .copy
    } else if let droppedString = pb.string(forType: .string) {
      return Regex.url.matches(droppedString) || Regex.filePath.matches(droppedString) ? .copy : []
    }
    return []
  }

  /**
   Get called for all drag-and-drop enabled window/views in their `performDragOperation(_:)`.

   - Parameters:
     - sender: The `NSDraggingInfo` object received in `performDragOperation(_:)`.
   - Returns: The result for `performDragOperation(_:)`.
   */
  func openFromPasteboard(_ sender: NSDraggingInfo) -> Bool {
    // get info
    let pb = sender.draggingPasteboard
    guard let types = pb.types else { return false }

    if types.contains(.nsFilenames) {
      guard var paths = pb.propertyList(forType: .nsFilenames) as? [String] else { return false }
      paths = Utility.resolvePaths(paths)
      // check 3d lut files
      if paths.count == 1 && Utility.lut3dExt.contains(paths[0].lowercasedPathExtension) {
        let result = addVideoFilter(MPVFilter(lavfiName: "lut3d", label: "iina_quickl3d", paramDict: [
          "file": paths[0],
          "interp": "nearest"
          ]))
        if result {
          sendOSD(.addFilter("3D LUT"))
        }
        return result
      }

      let urls = paths.map{ URL(fileURLWithPath: $0) }
      // try open files
      guard let loadedFileCount = openURLs(urls) else { return true }
      if loadedFileCount == 0 {
        // if no playable files, try add subtitle files
        var loadedSubtitle = false
        for url in urls {
          if !url.hasDirectoryPath && Utility.supportedFileExt[.sub]!.contains(url.pathExtension.lowercased()) {
            loadExternalSubFile(url)
            loadedSubtitle = true
          }
        }
        return loadedSubtitle
      } else if loadedFileCount == 1 {
        // loaded one file
        info.shouldAutoLoadFiles = true
        return true
      } else {
        // add multiple files to playlist
        sendOSD(.addToPlaylist(loadedFileCount))
        return true
      }
    } else if types.contains(.nsURL) {
      guard let url = pb.propertyList(forType: .nsURL) as? [String] else { return false }
      openURLString(url[0])
      return true
    } else if let droppedString = pb.string(forType: .string) {
      if Regex.url.matches(droppedString) || Regex.filePath.matches(droppedString) {
        openURLString(droppedString)
        return true
      } else {
        Utility.showAlert("unsupported_url")
        return false
      }
    }
    return false
  }

}
