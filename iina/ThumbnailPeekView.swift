//
//  ThumbnailPeekView.swift
//  iina
//
//  Created by lhc on 12/6/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class ThumbnailPeekView: NSView {

  var imageView: NSImageView!

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setup()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private func setup() {
    wantsLayer = true
    layer?.cornerRadius = 4
    layer?.masksToBounds = true
    layer?.borderWidth = 1
    layer?.borderColor = CGColor(gray: 0.6, alpha: 0.5)

    let s = NSShadow()
    s.shadowBlurRadius = 2
    s.shadowColor = .black
    shadow = s

    imageView = NSImageView()
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.wantsLayer = true
    imageView.layer?.cornerRadius = 4
    imageView.layer?.masksToBounds = true
    imageView.imageScaling = .scaleAxesIndependently
    addSubview(imageView)
    imageView.padding(.all(0))
  }

}
