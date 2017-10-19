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
   Open a list of urls. If there are more than one urls, add the remaining ones to
   playlist and disable auto loading.

   - Returns: `nil` if no futher action is needed, like opened a BD Folder; otherwise the
     count of playable files.
   */
  func openURLs(_ urls: [URL]) -> Int? {
    guard !urls.isEmpty else { return 0 }

    // handle BD folders and m3u / m3u8 files first
    if urls.count == 1 && (isBDFolder(urls[0]) || ["cue", "m3u", "m3u8"].contains(urls[0].absoluteString.lowercasedPathExtension)) {
      info.shouldAutoLoadFiles = false
      openURL(urls[0])
      return nil
    }

    let playableFiles = getPlayableFiles(in: urls)
    let count = playableFiles.count

    // check playable files count
    if count == 0 {
      return 0
    } else if count == 1 {
      info.shouldAutoLoadFiles = true
    } else {
      info.shouldAutoLoadFiles = false
    }

    // open the first file
    openURL(playableFiles[0])
    // add the remaining to playlist
    for i in 1..<count {
      addToPlaylist(playableFiles[i].path)
    }

    // refresh playlist
    NotificationCenter.default.post(Notification(name: Constants.Noti.playlistChanged))
    // send OSD
    if count > 1 {
      sendOSD(.addToPlaylist(count))
    }
    return count
  }

  /**
   Checks whether the path list contains playable file and performs early return if so.
   
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
          // check extension
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
   Returns playable files contained in a URL list.

   - Parameters:
     - urls: The list as an array of `URL`.
   - Returns: URLs of all playable files as an array of `URL`.
   */
  func getPlayableFiles(in urls: [URL]) -> [URL] {
    var playableFiles: [URL] = []
    for url in urls {
      if url.representsDirectory {
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
    return playableFiles
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
   Checks whether a URL is BD folder by checking the existance of "MovieObject.bdmv" and "index.bdmv".

   - Parameters:
     - url: The URL.
   - Returns: Whether the URL is a BD folder.
   */
  func isBDFolder(_ url: URL) -> Bool {
    let bdmvFolder = url.appendingPathComponent("BDMV")
    guard bdmvFolder.isExistingDirectory else { return false }
    if let files = try? FileManager.default.contentsOfDirectory(atPath: bdmvFolder.path) {
      return files.contains("MovieObject.bdmv") && files.contains("index.bdmv")
    } else {
      return false
    }
  }

  /**
   Get called for all drag-and-drop enabled window/views in their `draggingEntered(_:)`.

   - Parameters:
     - sender: The `NSDraggingInfo` object received in `draggingEntered(_:)`.
   - Returns: The `NSDragOperation`.
   */
  func acceptFromPasteboard(_ sender: NSDraggingInfo) -> NSDragOperation {
    // ignore events from this window
    // must check `mainWindow.isWindowLoaded` otherwise window will be lazy-loaded unexpectedly
    if mainWindow.isWindowLoaded && (sender.draggingSource() as? NSView)?.window === mainWindow.window {
      return []
    }

    // get info
    let pb = sender.draggingPasteboard()
    guard let types = pb.types else { return [] }

    if types.contains(.nsFilenames) {
      // filenames
      guard let paths = pb.propertyList(forType: .nsFilenames) as? [String] else { return [] }
      let theOnlyPathIsBDFolder = paths.count == 1 && isBDFolder(URL(fileURLWithPath: paths[0]))
      return theOnlyPathIsBDFolder ||
        hasPlayableFiles(in: paths) ||
        hasSubtitleFile(in: paths) ? .copy : []
    } else if types.contains(.nsURL) {
      // url
      return .copy
    } else if types.contains(.string) {
      // string
      guard let droppedString = pb.string(forType: .string) else {
        return []
      }
      return Regex.urlDetect.matches(droppedString) ? .copy : []
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
    let pb = sender.draggingPasteboard()
    guard let types = pb.types else { return false }

    if types.contains(.nsFilenames) {
      // filenames
      guard let paths = pb.propertyList(forType: .nsFilenames) as? [String] else { return false }
      let urls = paths.map{ URL(fileURLWithPath: $0) }
      // try open files
      guard let loadedFileCount = openURLs(urls) else { return true }
      if loadedFileCount == 0 {
        // if no playable files, try add subtitle files
        var loadedSubtitle = false
        for url in urls {
          if !url.representsDirectory && Utility.supportedFileExt[.sub]!.contains(url.pathExtension.lowercased()) {
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
      // url
      guard let url = pb.propertyList(forType: .nsURL) as? [String] else { return false }
      openURLString(url[0])
      return true
    } else if types.contains(.string) {
      // string
      guard let droppedString = pb.string(forType: .string) else {
        return false
      }
      if Regex.urlDetect.matches(droppedString) {
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
