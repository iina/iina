//
//  QuickSettingPanel.swift
//  mpvx
//
//  Created by lhc on 31/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class QuickSettingPanel: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

  override var windowNibName: String {
    return "QuickSettingPanel"
  }
  
  weak var playerController: PlayerController!
  weak var mainWindow: MainWindow!
  
  @IBOutlet weak var videoTableView: NSTableView!
  @IBOutlet weak var audioTableView: NSTableView!
  @IBOutlet weak var subTableView: NSTableView!
  @IBOutlet weak var secSubTableView: NSTableView!
  @IBOutlet weak var rotateSegment: NSSegmentedControl!
  @IBOutlet weak var aspectSegment: NSSegmentedControl!
  @IBOutlet weak var customAspectTextField: NSTextField!
  @IBOutlet weak var speedSlider: NSSlider!
  @IBOutlet weak var customSpeedTextField: NSTextField!
  
  override func windowDidLoad() {
    withAllTableViews { (view, _) in
      view.delegate = self
      view.dataSource = self
      view.focusRingType = .none
    }
  }
  
  func showWindowAt(_ origin: NSPoint, sender: AnyObject?) {
    showWindow(sender)
    window!.setFrameOrigin(origin)
  }
  
  // MARK: NSTableView delegate
  
  func numberOfRows(in tableView: NSTableView) -> Int {
    if tableView == videoTableView {
      return playerController.info.videoTracks.count + 1
    } else if tableView == audioTableView {
      return playerController.info.audioTracks.count + 1
    } else if tableView == subTableView || tableView == secSubTableView {
      return playerController.info.subTracks.count + 1
    } else {
      return 0
    }
  }
  
  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
    // get track according to tableview
    // row=0: <None> row=1~: tracks[row-1]
    let track: MPVTrack?
    let activeId: Int
    let columnName = tableColumn?.identifier
    if tableView == videoTableView {
      track = row == 0 ? nil : playerController.info.videoTracks[row-1]
      activeId = playerController.info.vid!
    } else if tableView == audioTableView {
      track = row == 0 ? nil : playerController.info.audioTracks[row-1]
      activeId = playerController.info.aid!
    } else if tableView == subTableView {
      track = row == 0 ? nil : playerController.info.subTracks[row-1]
      activeId = playerController.info.sid!
    } else if tableView == secSubTableView {
      track = row == 0 ? nil : playerController.info.subTracks[row-1]
      activeId = playerController.info.secondSid!
    } else {
      return nil
    }
    // return track data
    if columnName == "IsChosen" {
      let isChosen = track == nil ? (activeId == 0) : (track!.id == activeId)
      return isChosen ? "●" : ""
    } else { // if columnName == "TrackName" {
      return track?.readableTitle ?? "<None>"
    }
  }
  
  func tableViewSelectionDidChange(_ notification: Notification) {
    withAllTableViews { (view, type) in
      if view.numberOfSelectedRows > 0 {
        // note that track ids start from 1
        self.playerController.setTrack(view.selectedRow, forType: type)
        view.deselectAll(self)
        view.reloadData()
      }
    }
  }
  
  private func withAllTableViews (_ block: (NSTableView, MPVTrack.TrackType) -> Void) {
    block(audioTableView, .audio)
    block(subTableView, .sub)
    block(secSubTableView, .secondSub)
    block(videoTableView, .video)
  }
  
  // MARK: Actions
  
  @IBAction func aspectChangedAction(_ sender: NSSegmentedControl) {
    if let value = sender.label(forSegment: sender.selectedSegment) {
      playerController.setVideoAspect(value)
      mainWindow.displayOSD(OSDMessage.aspect(value))
    }
  }
  
  @IBAction func rotationChangedAction(_ sender: NSSegmentedControl) {
    let value = [0, 90, 180, 270][sender.selectedSegment]
    playerController.setVideoRotate(value)
    mainWindow.displayOSD(OSDMessage.rotate(value))
  }
  
  @IBAction func customAspectBtnAction(_ sender: NSButton) {
    let value = customAspectTextField.stringValue
    if value != "" {
      aspectSegment.setSelected(false, forSegment: aspectSegment.selectedSegment)
      playerController.setVideoAspect(value)
      mainWindow.displayOSD(OSDMessage.aspect(value))
    }
  }
  
  @IBAction func speedChangedAction(_ sender: NSSlider) {
    let value = sender.doubleValue
    playerController.setSpeed(value)
    mainWindow.displayOSD(OSDMessage.speed(value))
  }
  
  @IBAction func customSpeedBtnAction(_ sender: NSButton) {
    let value = customSpeedTextField.doubleValue
    Swift.print(value)
    playerController.setSpeed(value)
    mainWindow.displayOSD(OSDMessage.speed(value))
  }
  
  
}
