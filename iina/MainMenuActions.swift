//
//  MainWindowMenuActions.swift
//  iina
//
//  Created by lhc on 25/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa


class MainMenuActionHandler: NSResponder {

  unowned var player: PlayerCore

  init(playerCore: PlayerCore) {
    self.player = playerCore
    super.init()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc func menuShowInspector(_ sender: AnyObject) {
    let inspector = (NSApp.delegate as! AppDelegate).inspector
    inspector.showWindow(self)
    inspector.updateInfo()
  }

  @objc func menuSavePlaylist(_ sender: NSMenuItem) {
    Utility.quickSavePanel(title: "Save to playlist", types: ["m3u8"]) { (url) in
      if url.isFileURL {
        var playlist = ""
        for item in self.player.info.playlist {
          playlist.append((item.filename + "\n"))
        }

        do {
          try playlist.write(to: url, atomically: true, encoding: String.Encoding.utf8)
        } catch let error as NSError {
          Utility.showAlert("error_saving_file", arguments: ["subtitle",
                                                            error.localizedDescription])
        }
      }
    }
  }

  @objc func menuDeleteCurrentFile(_ sender: NSMenuItem) {
    guard let url = player.info.currentURL else { return }
    do {
      let index = player.mpv.getInt(MPVProperty.playlistPos)
      player.playlistRemove(index)
      try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    } catch let error {
      Utility.showAlert("playlist.error_deleting", arguments: [error.localizedDescription])
    }
  }

  // currently only being used for key command
  @objc func menuDeleteCurrentFileHard(_ sender: NSMenuItem) {
    guard let url = player.info.currentURL else { return }
    do {
      let index = player.mpv.getInt(MPVProperty.playlistPos)
      player.playlistRemove(index)
      try FileManager.default.removeItem(at: url)
    } catch let error {
      Utility.showAlert("playlist.error_deleting", arguments: [error.localizedDescription])
    }
  }

}

// MARK: - Control

extension MainMenuActionHandler {
  @objc func menuTogglePause(_ sender: NSMenuItem) {
    player.togglePause()
    // set speed to 0 if is fastforwarding
    if player.mainWindow.isFastforwarding {
      player.setSpeed(1)
      player.mainWindow.isFastforwarding = false
    }
  }

  @objc func menuStop(_ sender: NSMenuItem) {
    // FIXME: handle stop
    player.stop()
    player.sendOSD(.stop)
  }

  @objc func menuStep(_ sender: NSMenuItem) {
    let seconds = Double(abs((sender.representedObject as? Int) ?? 5))
    if sender.tag == 0 { // -> 5s
      player.seek(relativeSecond: seconds, option: .relative)
    } else if sender.tag == 1 { // <- 5s
      player.seek(relativeSecond: -seconds, option: .relative)
    }
  }

  @objc func menuStepFrame(_ sender: NSMenuItem) {
    if player.info.isPlaying {
      player.pause()
    }
    if sender.tag == 0 { // -> 1f
      player.frameStep(backwards: false)
    } else if sender.tag == 1 { // <- 1f
      player.frameStep(backwards: true)
    }
  }

  @objc func menuChangeSpeed(_ sender: NSMenuItem) {
    if sender.tag == 5 {
      player.setSpeed(1)
      return
    }
    if let multiplier = sender.representedObject as? Double {
      player.setSpeed(player.info.playSpeed * multiplier)
    }
  }

  @objc func menuJumpToBegin(_ sender: NSMenuItem) {
    player.seek(absoluteSecond: 0)
  }

  @objc func menuJumpTo(_ sender: NSMenuItem) {
    Utility.quickPromptPanel("jump_to") { input in
      if let vt = VideoTime(input) {
        self.player.seek(absoluteSecond: Double(vt.second))
      }
    }
  }

  @objc func menuSnapshot(_ sender: NSMenuItem) {
    player.screenshot()
  }

  @objc func menuABLoop(_ sender: NSMenuItem) {
    player.abLoop()
  }

  @objc func menuFileLoop(_ sender: NSMenuItem) {
    player.toggleFileLoop()
  }

  @objc func menuPlaylistLoop(_ sender: NSMenuItem) {
    player.togglePlaylistLoop()
  }

  @objc func menuPlaylistItem(_ sender: NSMenuItem) {
    let index = sender.tag
    player.playFileInPlaylist(index)
  }

  @objc func menuChapterSwitch(_ sender: NSMenuItem) {
    let index = sender.tag
    player.playChapter(index)
    let chapter = player.info.chapters[index]
    player.sendOSD(.chapter(chapter.title))
  }

  @objc func menuChangeTrack(_ sender: NSMenuItem) {
    if let trackObj = sender.representedObject as? (MPVTrack, MPVTrack.TrackType) {
      player.setTrack(trackObj.0.id, forType: trackObj.1)
    } else if let trackObj = sender.representedObject as? MPVTrack {
      player.setTrack(trackObj.id, forType: trackObj.type)
    }
  }

  @objc func menuNextMedia(_ sender: NSMenuItem) {
    player.navigateInPlaylist(nextMedia: true)
  }

  @objc func menuPreviousMedia(_ sender: NSMenuItem) {
    player.navigateInPlaylist(nextMedia: false)
  }

  @objc func menuNextChapter(_ sender: NSMenuItem) {
    player.mpv.command(.add, args: ["chapter", "1"], checkError: false)
  }

  @objc func menuPreviousChapter(_ sender: NSMenuItem) {
    player.mpv.command(.add, args: ["chapter", "-1"], checkError: false)
  }
}

// MARK: - Video

extension MainMenuActionHandler {
  @objc func menuChangeAspect(_ sender: NSMenuItem) {
    if let aspectStr = sender.representedObject as? String {
      player.setVideoAspect(aspectStr)
      player.sendOSD(.aspect(aspectStr))
    } else {
      Logger.log("Unknown aspect in menuChangeAspect(): \(sender.representedObject.debugDescription)", level: .error)
    }
  }

  @objc func menuChangeCrop(_ sender: NSMenuItem) {
    if let cropStr = sender.representedObject as? String {
      if cropStr == "Custom" {
        player.mainWindow.hideSideBar {
          self.player.mainWindow.enterInteractiveMode(.crop, selectWholeVideoByDefault: true)
        }
        return
      }
      player.setCrop(fromString: cropStr)
    } else {
      Logger.log("sender.representedObject is not a string in menuChangeCrop()", level: .error)
    }
  }

  @objc func menuChangeRotation(_ sender: NSMenuItem) {
    if let rotationInt = sender.representedObject as? Int {
      player.setVideoRotate(rotationInt)
    }
  }

  @objc func menuToggleFlip(_ sender: NSMenuItem) {
    if player.info.flipFilter == nil {
      player.setFlip(true)
    } else {
      player.setFlip(false)
    }
  }

  @objc func menuToggleMirror(_ sender: NSMenuItem) {
    if player.info.mirrorFilter == nil {
      player.setMirror(true)
    } else {
      player.setMirror(false)
    }
  }

  @objc func menuToggleDeinterlace(_ sender: NSMenuItem) {
    player.toggleDeinterlace(sender.state != .on)
  }
}

// MARK: - Audio

extension MainMenuActionHandler {
  @objc func menuChangeVolume(_ sender: NSMenuItem) {
    if let volumeDelta = sender.representedObject as? Int {
      let newVolume = Double(volumeDelta) + player.info.volume
      player.setVolume(newVolume)
    } else {
      Logger.log("sender.representedObject is not int in menuChangeVolume()", level: .error)
    }
  }

  @objc func menuToggleMute(_ sender: NSMenuItem) {
    player.toggleMute()
  }

  @objc func menuChangeAudioDelay(_ sender: NSMenuItem) {
    if let delayDelta = sender.representedObject as? Double {
      let newDelay = player.info.audioDelay + delayDelta
      player.setAudioDelay(newDelay)
    } else {
      Logger.log("sender.representedObject is not Double in menuChangeAudioDelay()", level: .error)
    }
  }

  @objc func menuResetAudioDelay(_ sender: NSMenuItem) {
    player.setAudioDelay(0)
  }
}

// MARK: - Sub

extension MainMenuActionHandler {
  @objc func menuLoadExternalSub(_ sender: NSMenuItem) {
    Utility.quickOpenPanel(title: "Load external subtitle file", chooseDir: false) { url in
      self.player.loadExternalSubFile(url, delay: true)
    }
  }

  @objc func menuChangeSubDelay(_ sender: NSMenuItem) {
    if let delayDelta = sender.representedObject as? Double {
      let newDelay = player.info.subDelay + delayDelta
      player.setSubDelay(newDelay)
    } else {
      Logger.log("sender.representedObject is not Double in menuChangeSubDelay()", level: .error)
    }
  }

  @objc func menuChangeSubScale(_ sender: NSMenuItem) {
    if sender.tag == 0 {
      player.setSubScale(1)
      return
    }
    // FIXME: better refactor this part
    let amount = sender.tag > 0 ? 0.1 : -0.1
    let currentScale = player.mpv.getDouble(MPVOption.Subtitles.subScale)
    let displayValue = currentScale >= 1 ? currentScale : -1/currentScale
    let truncated = round(displayValue * 100) / 100
    var newTruncated = truncated + amount
    // range for this value should be (~, -1), (1, ~)
    if newTruncated > 0 && newTruncated < 1 || newTruncated > -1 && newTruncated < 0 {
      newTruncated = -truncated + amount
    }
    player.setSubScale(abs(newTruncated > 0 ? newTruncated : 1 / newTruncated))
  }

  @objc func menuResetSubDelay(_ sender: NSMenuItem) {
    player.setSubDelay(0)
  }

  @objc func menuSetSubEncoding(_ sender: NSMenuItem) {
    player.setSubEncoding((sender.representedObject as? String) ?? "auto")
    player.reloadAllSubs()
  }

  @objc func menuSubFont(_ sender: NSMenuItem) {
    Utility.quickFontPickerWindow() {
      self.player.setSubFont($0 ?? "")
    }
  }

  @objc func menuFindOnlineSub(_ sender: NSMenuItem) {
    // return if last search is not finished
    guard let url = player.info.currentURL, !player.isSearchingOnlineSubtitle else { return }

    player.isSearchingOnlineSubtitle = true
    OnlineSubtitle.search(forFile: url, player: player, providerID: sender.representedObject as? String) { urls in
      if urls.isEmpty {
        self.player.sendOSD(.foundSub(0))
      } else {
        for url in urls {
          Logger.log("Saved subtitle to \(url.path)")
          self.player.loadExternalSubFile(url)
        }
        self.player.sendOSD(.downloadedSub(
          urls.map({ $0.lastPathComponent }).joined(separator: "\n")
        ))
        self.player.info.haveDownloadedSub = true
      }
      self.player.isSearchingOnlineSubtitle = false
    }
  }

  @objc func saveDownloadedSub(_ sender: NSMenuItem) {
    let selected = player.info.subTracks.filter { $0.id == player.info.sid }
    guard let currURL = player.info.currentURL else { return }
    guard selected.count > 0 else {
      Utility.showAlert("sub.no_selected")

      return
    }
    let sub = selected[0]
    // make sure it's a downloaded sub
    guard let path = sub.externalFilename, path.contains("/var/") else {
      Utility.showAlert("sub.no_selected")
      return
    }
    let subURL = URL(fileURLWithPath: path)
    let subFileName = subURL.lastPathComponent
    let destURL = currURL.deletingLastPathComponent().appendingPathComponent(subFileName, isDirectory: false)
    do {
      try FileManager.default.copyItem(at: subURL, to: destURL)
      player.sendOSD(.savedSub)
    } catch let error as NSError {
      Utility.showAlert("error_saving_file", arguments: ["subtitle",
                                                         error.localizedDescription])
    }
  }

  @objc func menuCycleTrack(_ sender: NSMenuItem) {
    switch sender.tag {
    case 0: player.mpv.command(.cycle, args: ["video"])
    case 1: player.mpv.command(.cycle, args: ["audio"])
    case 2: player.mpv.command(.cycle, args: ["sub"])
    default: break
    }
  }
}
