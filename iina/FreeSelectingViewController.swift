//
//  FreeSelectingViewController.swift
//  iina
//
//  Created by lhc on 5/9/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

/** Currently only for adding delogo filters. */
class FreeSelectingViewController: CropBoxViewController {

  @IBAction func doneBtnAction(_ sender: AnyObject) {
    let player = mainWindow.player

    mainWindow.exitInteractiveMode {
      let filter = MPVFilter.init(lavfiName: "delogo", label: Constants.FilterName.delogo, paramDict: [
        "x": String(self.cropx),
        "y": String(self.cropy),
        "w": String(self.cropw),
        "h": String(self.croph)
        ])
      if let existingFilter = player.info.delogoFiter {
        let _ = player.removeVideoFilter(existingFilter)
      }
      if !player.addVideoFilter(filter) {
        Utility.showAlert("filter.incorrect")
        return
      }
      player.info.delogoFiter = filter
    }
  }

  @IBAction func cancelBtnAction(_ sender: AnyObject) {
    mainWindow.exitInteractiveMode()
  }

}
