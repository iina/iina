//
//  TimeLabelOverflowedView.swift
//  iina
//
//  Created by lhc on 4/4/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class TimeLabelOverflowedView: NSView {

  /// Initializes and returns a newly allocated `TimeLabelOverflowedView` object from data in the specified coder object.
  /// - Parameter coder: The coder object that contains the view’s configuration details.
  /// - Important: As per Apple's [Internationalization and Localization Guide](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPInternational/SupportingRight-To-LeftLanguages/SupportingRight-To-LeftLanguages.html)
  ///     video controllers and timeline indicators should not flip in a right-to-left language. This can not be set in the XIB.
  required init?(coder: NSCoder) {
    super.init(coder: coder)
    userInterfaceLayoutDirection = .leftToRight
  }

  override var alignmentRectInsets: NSEdgeInsets {
    return NSEdgeInsets(top: 6, left: 0, bottom: 0, right: 0)
  }

}
