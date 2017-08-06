//
//  DraggingDetect.swift
//  iina
//
//  Created by Yuze Jiang on 05/08/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

extension PlayerCore {

  func openURLs(_ urls: [URL]) -> Int {
    let paths = urls.map{ $0.path }
    let (_, playableFiles) = checkPlayableFiles(paths, returnPaths: true)

    let count = playableFiles.count
    if count == 0 {
      return 0
    } else if count == 1 {
      info.shouldAutoLoadFiles = true
    } else {
      info.shouldAutoLoadFiles = false
    }
    openURL(URL(fileURLWithPath: playableFiles[0], isDirectory: false))
    for i in 1..<count {
      addToPlaylist(playableFiles[i])
    }
    if count != 0 {
      NotificationCenter.default.post(Notification(name: Constants.Noti.playlistChanged))
    }
    if count > 1 {
      sendOSD(.addToPlaylist(count))
    }
    return count
  }

  func checkPlayableFiles(_ paths: [String], returnPaths: Bool = false) -> (Bool, [String]) {
    var playableFiles: [String] = []
    for path in paths {
      if !ObjcUtils.isDirectory(path) {
        if Utility.playableFileExt.contains((path as NSString).pathExtension.lowercased()) {
          if returnPaths {
            playableFiles.append(path)
          } else {
            return (true, [])
          }
        }
      } else {
        let dirEnumerator = FileManager.default.enumerator(atPath: path)
        while let fileName = dirEnumerator?.nextObject() as? NSString {
          if Utility.playableFileExt.contains(fileName.pathExtension.lowercased()) {
            if returnPaths {
              playableFiles.append(path + "/" + (fileName as String))
            } else {
              return (true, [])
            }
          }
        }
      }
    }
    return (!playableFiles.isEmpty, playableFiles)
  }

  func checkSubtitleFile(_ paths: [String]) -> Bool {
    for path in paths {
      if !ObjcUtils.isDirectory(path) {
        if Utility.supportedFileExt[.sub]!.contains((path as NSString).pathExtension.lowercased()) {
          return true
        }
      }
    }
    return false
  }

  func acceptFromPasteboard(_ sender: NSDraggingInfo) -> NSDragOperation {
    if sender.draggingSource() != nil { return [] }
    let pb = sender.draggingPasteboard()
    guard let types = pb.types else { return [] }
    if types.contains(NSFilenamesPboardType) {
      guard let paths = pb.propertyList(forType: NSFilenamesPboardType) as? [String] else { return [] }
      if checkPlayableFiles(paths).0 {
        return .copy
      } else if checkSubtitleFile(paths) {
        return .copy
      } else {
        return []
      }
    } else if types.contains(NSURLPboardType) {
      return .copy
    } else if types.contains(NSPasteboardTypeString) {
      guard let droppedString = pb.pasteboardItems![0].string(forType: "public.utf8-plain-text") else {
        return []
      }
      if Regex.urlDetect.matches(droppedString) {
        return .copy
      } else {
        return []
      }
    }
    return []
  }

  func openFromPasteboard(_ sender: NSDraggingInfo) -> Bool {
    let pb = sender.draggingPasteboard()
    guard let types = pb.types else { return false }
    if types.contains(NSFilenamesPboardType) {
      guard let paths = pb.propertyList(forType: NSFilenamesPboardType) as? [String] else { return false }
      let urls = paths.map{ URL.init(fileURLWithPath: $0) }
      let loadedFile = openURLs(urls)
      if loadedFile == 0 {
        var loadedSubtitle = 0
        for path in paths {
          if !ObjcUtils.isDirectory(path) {
            if Utility.supportedFileExt[.sub]!.contains((path as NSString).pathExtension.lowercased()) {
              loadExternalSubFile(URL.init(fileURLWithPath: path))
              loadedSubtitle += 1
            }
          }
        }
        if loadedSubtitle != 0 {
          return true
        } else {
          return false
        }
      } else if loadedFile == 1 {
        info.shouldAutoLoadFiles = true
        return true
      } else {
        sendOSD(.addToPlaylist(loadedFile))
        return true
      }
    } else if types.contains(NSURLPboardType) {
      guard let url = pb.propertyList(forType: NSURLPboardType) as? [String] else { return false }
      openURLString(url[0])
      return true
    } else if types.contains(NSPasteboardTypeString) {
      guard let droppedString = pb.pasteboardItems![0].string(forType: "public.utf8-plain-text") else {
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
