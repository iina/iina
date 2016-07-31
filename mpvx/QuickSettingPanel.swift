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
  
  var playerController: PlayerController!
  
  @IBOutlet weak var audioTableView: NSTableView!
  @IBOutlet weak var subTableView: NSTableView!
  
  override func windowDidLoad() {
    withAllTableViews { (view, _) in
      view.delegate = self
      view.dataSource = self
//      view!.selectionHighlightStyle = .none
      view.focusRingType = .none
    }
    
  }
  
  // MARK: NSTableView delegate
  
  func numberOfRows(in tableView: NSTableView) -> Int {
    if tableView == audioTableView {
      return playerController.info.audioTracks.count
    } else if tableView == subTableView {
      return playerController.info.subTracks.count
    } else {
      return 0
    }
  }
  
  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
    // get track according to tableview
    let track: MPVTrack
    let activeId: Int
    if tableView == audioTableView {
      track = playerController.info.audioTracks[row]
      activeId = playerController.info.aid!
    } else if tableView == subTableView {
      track = playerController.info.subTracks[row]
      activeId = playerController.info.sid!
    } else {
      return nil
    }
    // return track data
    let columnName = tableColumn?.identifier
    if columnName == "IsChosen" {
      return track.id == activeId ? "●" : ""
    } else { // if columnName == "TrackName" {
      return track.readableTitle
    }
  }
  
  func tableViewSelectionDidChange(_ notification: Notification) {
    withAllTableViews { (view, type) in
      if view.numberOfSelectedRows > 0 {
        // note that track ids start from 1
        self.playerController.setTrack(view.selectedRow + 1, forType: type)
        view.deselectAll(self)
        view.reloadData()
      }
    }
  }
  
  private func withAllTableViews (_ block: (NSTableView, MPVTrack.TrackType) -> Void) {
    block(audioTableView, .audio)
    block(subTableView, .sub)
  }
  
}
