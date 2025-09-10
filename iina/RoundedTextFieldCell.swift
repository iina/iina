//
//  RoundedTextFieldCell.swift
//  iina
//
//  Created by lhc on 12/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class RoundedTextFieldCell: NSTextFieldCell {

  let paddingH: CGFloat = 4
  let paddingV: CGFloat = 2

  override func awakeFromNib() {
    bezelStyle = .roundedBezel
  }

  override func drawingRect(forBounds rect: NSRect) -> NSRect {
    if #available(macOS 26, *) {
      return super.drawingRect(forBounds: rect)
    } else {
      return rect.insetBy(dx: paddingH, dy: paddingV)
    }
  }

}
