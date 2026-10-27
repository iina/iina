//
//  CommonWindow.swift
//  iina
//
//  Created by low-batt on 8/1/26.
//  Copyright © 2026 lhc. All rights reserved.
//

import Cocoa

/// Common base class for IINA windows.
class CommonWindow: NSWindow {

  /// Whether the window uses a [toolbar](https://developer.apple.com/documentation/appkit/nstoolbar) with the
  /// [unified](https://developer.apple.com/documentation/appkit/nswindow/toolbarstyle-swift.enum/unified)
  /// style.
  private let usesUnifiedToolbar: Bool

  /// The direction the window’s title bar lays text out, either left to right or right to left.
  ///
  /// As discussed in the
  /// [windowTitlebarLayoutDirection](https://developer.apple.com/documentation/appkit/nswindow/windowtitlebarlayoutdirection)
  /// documentation the value returned by the `NSWindow` implementation is based on the macOS primary system language. If in
  /// macOS settings IINA has been configured with a language with a different directionality than the primary system language then
  /// layout will be inconsistent and can cause objects to overlap. This implementation returns the layout direction of the view
  /// containing the window close button to make layout consistent. See issue
  /// [#6192](https://github.com/iina/iina/issues/6192).
  /// - Important: Apparently  the AppKit `NSWindow` implementation does not use the value of this property when laying out
  ///     the title bar if the window uses a [toolbar](https://developer.apple.com/documentation/appkit/nstoolbar)
  ///     with the
  ///     [unified](https://developer.apple.com/documentation/appkit/nswindow/toolbarstyle-swift.enum/unified)
  ///     style where the toolbar appears next to the window title. The layout provided by AppKit  in this case expects the standard
  ///     window buttons to be located based on the direction of the primary system language instead of this property. Unfortunately
  ///     this behavior means this workaround can not be used for such windows. This affects the `Inspector`, `Log Viewer`
  ///     and `Playback History` windows.
  override var windowTitlebarLayoutDirection: NSUserInterfaceLayoutDirection {
    guard !usesUnifiedToolbar, let button = standardWindowButton(.closeButton),
          let view = button.superview else {
      return super.windowTitlebarLayoutDirection
    }
    return view.userInterfaceLayoutDirection
  }

  /// Initializes the window with the specified values.
  ///
  /// This initializer ensures the
  /// [isReleasedWhenClosed](https://developer.apple.com/documentation/appkit/nswindow/isreleasedwhenclosed)
  /// property is set to `false` as the Apple documentation for the `NSWindow`
  /// [initializer](https://developer.apple.com/documentation/appkit/nswindow/init(contentrect:stylemask:backing:defer:))
  /// warns is required for Swift clients to avoid release the window too many times. This is done as a precaution as this property is
  /// ignored for windows owned by window controllers.
  /// - Parameters:
  ///   - contentRect: Origin and size of the window’s content area in screen coordinates. Note that the window server limits
  ///       window position coordinates to ±16,000 and sizes to 10,000.
  ///   - style: The window’s style. It can be `NSBorderlessWindowMask`, or it can contain any of the options described in
  ///       [NSWindow.StyleMask](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct)
  ///       combined using the C bitwise OR operator. Borderless windows display none of the usual peripheral elements and are
  ///       generally useful only for display or caching purposes; you should normally not need to create them. Also, note that a
  ///       window’s style mask should include `NSTitledWindowMask` if it includes any of the others.
  ///   - backingStoreType: Specifies how the drawing done in the window is buffered by the window device, and possible
  ///       values are described in
  ///       [NSWindow.BackingStoreType](https://developer.apple.com/documentation/appkit/nswindow/backingstoretype).
  ///   - flag: Specifies whether the window server creates a window device for the window immediately. When
  ///       [true](https://developer.apple.com/documentation/Swift/true), the window server defers creating the
  ///       window device until the window is moved onscreen. All display messages sent to the window or its views are postponed
  ///       until the window is created, just before it’s moved onscreen.
  /// - Important: If the window will use a
  ///     [toolbar](https://developer.apple.com/documentation/appkit/nstoolbar) with the
  ///     [unified](https://developer.apple.com/documentation/appkit/nswindow/toolbarstyle-swift.enum/unified)
  ///     style where the toolbar appears next to the window title then the other initializer **must be** used.
  override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
    usesUnifiedToolbar = false
    super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    isReleasedWhenClosed = false
  }
  
  /// Initializes the window with the specified values.
  ///
  /// This initializer ensures the
  /// [isReleasedWhenClosed](https://developer.apple.com/documentation/appkit/nswindow/isreleasedwhenclosed)
  /// property is set to `false` as the Apple documentation for the `NSWindow`
  /// [initializer](https://developer.apple.com/documentation/appkit/nswindow/init(contentrect:stylemask:backing:defer:))
  /// warns is required for Swift clients to avoid release the window too many times. This is done as a precaution as this property is
  /// ignored for windows owned by window controllers.
  /// - Parameters:
  ///   - contentRect: Origin and size of the window’s content area in screen coordinates. Note that the window server limits
  ///       window position coordinates to ±16,000 and sizes to 10,000.
  ///   - style: The window’s style. It can be `NSBorderlessWindowMask`, or it can contain any of the options described in
  ///       [NSWindow.StyleMask](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct)
  ///       combined using the C bitwise OR operator. Borderless windows display none of the usual peripheral elements and are
  ///       generally useful only for display or caching purposes; you should normally not need to create them. Also, note that a
  ///       window’s style mask should include `NSTitledWindowMask` if it includes any of the others.
  ///   - backingStoreType: Specifies how the drawing done in the window is buffered by the window device, and possible
  ///       values are described in
  ///       [NSWindow.BackingStoreType](https://developer.apple.com/documentation/appkit/nswindow/backingstoretype).
  ///   - flag: Specifies whether the window server creates a window device for the window immediately. When
  ///       [true](https://developer.apple.com/documentation/Swift/true), the window server defers creating the
  ///       window device until the window is moved onscreen. All display messages sent to the window or its views are postponed
  ///       until the window is created, just before it’s moved onscreen.
  ///   - usesUnifiedToolbar: Specifies whether the window will use a
  ///       [toolbar](https://developer.apple.com/documentation/appkit/nstoolbar) with the
  ///       [unified](https://developer.apple.com/documentation/appkit/nswindow/toolbarstyle-swift.enum/unified)
  ///       style where the toolbar appears next to the window title.
  /// - Important: Windows that will use a
  ///     [toolbar](https://developer.apple.com/documentation/appkit/nstoolbar) with the
  ///     [unified](https://developer.apple.com/documentation/appkit/nswindow/toolbarstyle-swift.enum/unified)
  ///     style where the toolbar appears next to the window title **must** use this initializer and pass `true` for the
  ///     `usesUnifiedToolbar` parameter. For more discussion see the `windowTitlebarLayoutDirection` property.
  init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
       backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool,
       usesUnifiedToolbar: Bool) {
    self.usesUnifiedToolbar = usesUnifiedToolbar
    super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    isReleasedWhenClosed = false
  }
}
