//
//  SettingsListCellView.swift
//  iina
//
//  Created by lhc on 24/10/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class SettingsListCellView: NSView {

  override func awakeFromNib() {
    self.wantsLayer = true
  }

  override var wantsUpdateLayer: Bool {
    return true
  }

  override func updateLayer() {
    self.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
  }

}
