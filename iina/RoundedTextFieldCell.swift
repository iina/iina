//
//  RoundedTextFieldCell.swift
//  iina
//
//  Created by lhc on 12/8/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class RoundedTextFieldCell: NSTextFieldCell {

  let paddingH: CGFloat = 4
  let paddingV: CGFloat = 2

  override func awakeFromNib() {
    bezelStyle = .roundedBezel
  }

  override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
    super.draw(withFrame: cellFrame, in: controlView)
  }

  override func drawingRect(forBounds rect: NSRect) -> NSRect {
    return rect.insetBy(dx: paddingH, dy: paddingV)
  }

}
