//
//  ThumbnailPeekView.swift
//  iina
//
//  Created by lhc on 12/6/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class ThumbnailPeekView: NSView {

  @IBOutlet var imageView: NSImageView!

  override func awakeFromNib() {
    self.wantsLayer = true
    self.layer?.cornerRadius = 4
    self.layer?.masksToBounds = true
    // shadow is set in xib
    self.layer?.shadowRadius = 2
    self.layer?.borderWidth = 1
    self.layer?.borderColor = CGColor(gray: 0.6, alpha: 0.5)
    self.imageView.wantsLayer = true
    self.imageView.layer?.cornerRadius = 4
    self.imageView.layer?.masksToBounds = true
    self.imageView.imageScaling = .scaleAxesIndependently
  }

}
