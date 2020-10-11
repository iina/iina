//
//  JavascriptAPICore.swift
//  iina
//
//  Created by Collider LI on 11/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

// MARK: Core API

@objc protocol JavascriptAPICoreExportable: JSExport {
  func open(_ url: String)
  func osd(_ message: String)
  func pause()
  func resume()
  func stop()
  func setSpeed(_ speed: Double)
  func getChapters() -> [[String: Any]]
  func playChapter(index: Int)
  func getHistory() -> Any
  func getRecentDocuments() -> Any
  func getVersion() -> Any
}

class JavascriptAPICore: JavascriptAPI, JavascriptAPICoreExportable {
  private lazy var _window = { WindowAPI(context: context, pluginInstance: pluginInstance) }()
  private lazy var _status = { StatusAPI(context: context, pluginInstance: pluginInstance) }()
  private lazy var _audio = { AudioAPI(context: context, pluginInstance: pluginInstance) }()
  private lazy var _subtitle = { SubtitleAPI(context: context, pluginInstance: pluginInstance) }()
  private lazy var _video = { VideoAPI(context: context, pluginInstance: pluginInstance) }()

  override func extraSetup() {
    (
      [(_window, "window"), (_status, "status"), (_audio, "audio"), (_subtitle, "subtitle"), (_video, "video")] as [(JavascriptAPI, String)]
    ).forEach { (api, name) in
      context.setObject(api, forKeyedSubscript: "__api_\(name)" as NSString)
      context.evaluateScript("""
      iina.core.\(name) = new Proxy(__api_\(name), {
        get(obj, prop) { return prop === "loadTrack" ? obj[prop].bind(obj) : prop.startsWith("__") ? null : obj.__proxyGet(prop) },
        set(obj, prop, value) { obj.__proxySet(prop, value) },
      });
      delete __api_\(name);
      """)
    }
  }

  @objc func open(_ url: String) {
    self.player.openURLString(url)
  }

  @objc func osd(_ message: String) {
    whenPermitted(to: .showOSD) {
      self.player.sendOSD(.customWithDetail(message, "From plugin \(pluginInstance.plugin.name)"),
                          autoHide: true, accessoryView: nil, external: true)
    }
  }

  @objc func pause() {
    player.pause()
  }

  @objc func resume() {
    player.resume()
  }

  @objc func stop() {
    player.stop()
  }

  @objc func setSpeed(_ speed: Double) {
    player.setSpeed(speed)
  }

  @objc func getChapters() -> [[String: Any]] {
    player.getChapters()
    return player.info.chapters.map{
      ["title": $0.title, "start": $0.time.second]
    }
  }

  @objc func playChapter(index: Int) {
    player.playChapter(index)
  }

  func getHistory() -> Any {
    return HistoryController.shared.history.map {
      [
        "name": $0.name,
        "url": $0.url.absoluteString,
        "date": $0.addedDate,
        "progress": $0.mpvProgress?.second ?? NSNull(),
        "duration": $0.duration.second
      ]
    }
  }

  func getRecentDocuments() -> Any {
    return NSDocumentController.shared.recentDocumentURLs.map {
      [
        "name": $0.lastPathComponent,
        "url": $0.absoluteString
      ]
    }
  }

  func getVersion() -> Any {
    let (iinaVersion, build) = Utility.iinaVersion()
    return [
      "iina": iinaVersion,
      "build": build,
      "mpv": PlayerCore.first.mpv.mpvVersion
    ]
  }
}

// MARK: Sub API

fileprivate func serialize(track: MPVTrack) -> [String: Any] {
  return [
    "id": track.id,
    "title": track.title ?? NSNull(),
    "formattedTitie": track.readableTitle,
    "lang": track.lang ?? NSNull(),
    "codec": track.codec ?? NSNull(),
    "isDefault": track.isDefault,
    "isForced": track.isForced,
    "isSelected": track.isSelected,
    "isExternal": track.isExternal,
    "demuxW": track.demuxW ?? NSNull(),
    "demuxH": track.demuxH ?? NSNull(),
    "demuxChannelCount": track.demuxChannelCount ?? NSNull(),
    "demuxChannels": track.demuxChannels ?? NSNull(),
    "demuxSamplerate": track.demuxSamplerate ?? NSNull(),
    "demuxFPS": track.demuxFps ?? NSNull(),
  ]
}

@objc fileprivate protocol CoreSubAPIExportable: JSExport {
  func __proxyGet(_ prop: String) -> Any?
  func __proxySet(_ prop: String, _ value: Any)
}

@objc fileprivate protocol TrackAPIExportable: JSExport {
  func loadTrack(_ track: Any)
}

fileprivate class TrackAPI: JavascriptAPI, TrackAPIExportable {
  var tag: String { "" }
  var type: MPVTrack.TrackType { .video }

  func getCurrentTrack(forType type: MPVTrack.TrackType? = nil) -> Any {
    guard let track = player.info.currentTrack(type ?? self.type) else { return NSNull() }
    return serialize(track: track)
  }

  func getTracks() -> Any {
    return player.info.trackList(type).map(serialize(track:))
  }

  func setTrack(_ value: Any, forType type: MPVTrack.TrackType? = nil) {
    guard let val = value as? Int else {
      log("\(tag).id: Should be a number", level: .error)
      return
    }
    player.setTrack(val, forType: type ?? self.type)
  }

  func setDelay(_ value: Any) {
    guard let val = value as? Double else {
      log("core.audio.delay: Should be a number", level: .error)
      return
    }
    switch type {
    case .audio: player.setAudioDelay(val)
    case .sub, .secondSub: player.setSubDelay(val)
    default: return
    }
  }

  func loadTrack(_ track: Any) {
    guard let urlString = track as? String else {
      log("loadTrack: the url must be a string", level: .error)
      return
    }
    let url = URL(fileURLWithPath: urlString)
    switch type {
    case .audio: player.loadExternalAudioFile(url)
    case .sub, .secondSub: player.loadExternalSubFile(url)
    case .video: player.loadExternalVideoFile(url)
    }
  }
}

// MARK: Window

fileprivate class WindowAPI: JavascriptAPI, CoreSubAPIExportable {
  func __proxyGet(_ prop: String) -> Any? {
    if prop == "loaded" {
      return player.mainWindow.loaded
    }

    guard let window = player.mainWindow, window.loaded else { return NSNull() }

    // props that requires a loaded window
    switch prop {
    case "frame":
      return JSValue(rect: window.window!.frame, in: context)
    case "fullscreen":
      return window.fsState.isFullscreen
    case "pip":
      return window.pipStatus == .inPIP
    case "ontop":
      return window.isOntop
    case "visible":
      return window.window!.occlusionState == .visible
    case "sidebar":
      return window.sideBarStatus == .settings ? window.quickSettingView.currentTab.name : NSNull()
    case "screens":
      let current = window.window!.screen!
      let main = NSScreen.main
      let screens = NSScreen.screens.map { screen in
        [ "frame": screen.frame, "main": screen == main, "current": screen == current ]
      }
      return screens
    default:
      return nil
    }
  }

  func __proxySet(_ prop: String, _ value: Any) {
    guard let window = player.mainWindow, window.loaded else { return }

    switch prop {
    case "frame":
      guard let val = value as? [String: Double],
        let x = val["x"], let y = val["y"], let w = val["width"], let h = val["height"],
        w > 0, h > 0
      else {
        log("core.window.frame: Invalid frame", level: .error)
        return
      }
      window.window?.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    case "fullscreen":
      guard let val = value as? Bool, val != window.fsState.isFullscreen else { return }
      window.toggleWindowFullScreen()
    case "pip":
      if #available(OSX 10.12, *) {
        guard let val = value as? Bool else { return }
        if val {
          window.enterPIP()
        } else {
          window.exitPIP()
        }
      }
    case "ontop":
      guard let val = value as? Bool else { return }
      window.setWindowFloatingOnTop(val)
    case "sidebar":
      if let name = value as? String {
        if let tabType = QuickSettingViewController.TabViewType(name: name) {
          window.showSettingsSidebar(tab: tabType, force: true, hideIfAlreadyShown: false)
        } else if let tabType = PlaylistViewController.TabViewType(name: name) {
          window.showPlaylistSidebar(tab: tabType, force: true, hideIfAlreadyShown: false)
        } else {
          log("core.window.sidebar: Unknown sidebar name \"\(name)\"", level: .error)
        }
      } else {
        window.hideSideBar(animate: true)
      }
    default:
      log("core.window: \(prop) is not accessible", level: .warning)
    }
  }
}

// MARK: Status

fileprivate class StatusAPI: JavascriptAPI, CoreSubAPIExportable {
  func __proxyGet(_ prop: String) -> Any? {
    switch prop {
    case "paused":
      return !player.info.isPlaying
    case "idle":
      return player.info.isIdle
    case "position":
      return player.info.videoPosition?.second ?? NSNull()
    case "duration":
      return player.info.videoDuration?.second ?? NSNull()
    case "speed":
      return player.info.playSpeed
    case "videoWidth":
      guard let vw = player.info.videoWidth else { return NSNull() }
      return Int32(vw)
    case "videoHeight":
      guard let vh = player.info.videoHeight else { return NSNull() }
      return Int32(vh)
    case "isNetworkResource":
      return player.info.isNetworkResource
    case "url":
      return player.info.currentURL?.absoluteString.removingPercentEncoding ?? NSNull()
    default:
      return nil
    }
  }

  func __proxySet(_ prop: String, _ value: Any) {
    log("core.status: \(prop) is not accessible", level: .warning)
  }
}

// MARK: Tracks

fileprivate class AudioAPI: TrackAPI, CoreSubAPIExportable {
  override var tag: String { "audio" }
  override var type: MPVTrack.TrackType { .audio }

  func __proxyGet(_ prop: String) -> Any? {
    switch prop {
    case "id":
      return player.info.aid ?? NSNull()
    case "delay":
      return player.info.audioDelay
    case "tracks":
      return getTracks()
    case "currentTrack":
      return getCurrentTrack()
    case "volume":
      return player.info.volume
    case "muted":
      return player.info.isMuted
    default:
      return nil
    }
  }

  func __proxySet(_ prop: String, _ value: Any) {
    switch prop {
    case "id":
      setTrack(value, forType: .audio)
    case "delay":
      setDelay(value)
    case "volume":
      guard let val = value as? Double else {
        log("core.audio.volume: Should be a number", level: .error)
        return
      }
      player.setVolume(val)
    case "muted":
      guard let val = value as? Bool else {
        log("core.audio.muted: Should be a boolean value", level: .error)
        return
      }
      return player.toggleMute(val)
    default:
      return
    }
  }

//  func loadTrack(_ track: Any) {
//    _loadTrack(track)
//  }
}


fileprivate class SubtitleAPI: TrackAPI, CoreSubAPIExportable {
  override var tag: String { "subtitle" }
  override var type: MPVTrack.TrackType { .sub }

  func __proxyGet(_ prop: String) -> Any? {
    switch prop {
    case "id":
      return player.info.sid ?? NSNull()
    case "secondID":
      return player.info.secondSid ?? NSNull()
    case "delay":
      return player.info.subDelay
    case "tracks":
      return getTracks()
    case "currentTrack":
      return getCurrentTrack()
    default:
      return nil
    }
  }

  func __proxySet(_ prop: String, _ value: Any) {
    switch prop {
    case "id":
      setTrack(value)
    case "secondID":
      setTrack(value, forType: .secondSub)
    case "delay":
      setDelay(value)
    default:
      return
    }
  }
}

fileprivate class VideoAPI: TrackAPI, CoreSubAPIExportable {
  override var tag: String { "video" }
  override var type: MPVTrack.TrackType { .video }

  func __proxyGet(_ prop: String) -> Any? {
    switch prop {
    case "id":
      return player.info.vid ?? NSNull()
    case "tracks":
      return getTracks()
    case "currentTrack":
      return getCurrentTrack()
    default:
      return nil
    }
  }

  func __proxySet(_ prop: String, _ value: Any) {
    switch prop {
     case "id":
       setTrack(value)
     default:
       return
     }
  }
}
