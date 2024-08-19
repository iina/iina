//
//  EventController.swift
//  iina
//
//  Created by Collider LI on 17/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation

protocol EventCallable {
  func call(withArguments args: [Any])
}

class EventController {

  struct Name: RawRepresentable, Hashable {
    typealias RawValue = String
    var rawValue: String

    var hashValue: Int {
      return rawValue.hashValue
    }

    init(_ string: String) { self.rawValue = string }
    init?(rawValue: RawValue) { self.rawValue = rawValue }

    // IINA events
    
    // Window related
    static let windowLoaded = Name("iina.window-loaded")
    static let windowSizeAdjusted = Name("iina.window-size-adjusted")
    static let windowMoved = Name("iina.window-moved")
    static let windowResized = Name("iina.window-resized")
    static let windowFullscreenChanged = Name("iina.window-fs.changed")
    static let windowScreenChanged = Name("iina.window-screen.changed")
    static let windowMiniaturized = Name("iina.window-miniaturized")
    static let windowDeminiaturized = Name("iina.window-deminiaturized")
    
    static let windowMainStatusChanged = Name("iina.window-main.changed")
    static let windowWillClose = Name("iina.window-will-close")

    static let musicModeChanged = Name("iina.music-mode.changed")
    static let pipChanged = Name("iina.pip.changed")

    static let fileLoaded = Name("iina.file-loaded")
    static let fileStarted = Name("iina.file-started")
    
    static let mpvInitialized = Name("iina.mpv-inititalized")
    static let thumbnailsReady = Name("iina.thumbnails-ready")
    static let pluginOverlayLoaded = Name("iina.plugin-overlay-loaded")
  }

  var listeners: [Name: [String: EventCallable]] = [:]

  func hasListener(for name: Name) -> Bool {
    return listeners[name] != nil
  }

  func addListener(_ listener: EventCallable, for name: Name) -> String {
    let uuid = UUID().uuidString
    listeners[name, default: [:]][uuid] = listener
    return uuid
  }

  @discardableResult
  func removeListener(_ id: String, for name: Name) -> Bool {
    guard let t = listeners[name], let _ = t[id] else { return false }
    listeners[name]![id] = nil
    return true
  }

  func emit(_ eventName: Name, data: Any...) {
    guard let listeners = listeners[eventName] else { return }
    for listener in listeners.values {
      listener.call(withArguments: data)
    }
  }
}
