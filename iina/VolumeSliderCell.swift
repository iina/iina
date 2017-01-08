//
//  VolumeSliderCell.swift
//  iina
//
//  Created by lhc on 26/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class VolumeSliderCell: NSSliderCell {

  override func awakeFromNib() {
    minValue = 0
    maxValue = 100
  }

}
