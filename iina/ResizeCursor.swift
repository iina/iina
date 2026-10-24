//
//  ResizeCursor.swift
//  iina
//

import Cocoa

enum ResizeCursor {
  static let rising = diagonalCursor(rising: true)
  static let falling = diagonalCursor(rising: false)
  static let horizontal = axisCursor(horizontal: true)
  static let vertical = axisCursor(horizontal: false)

  private static func axisCursor(horizontal: Bool) -> NSCursor {
    if #available(macOS 15.0, *) {
      return .frameResize(position: horizontal ? .left : .top, directions: .all)
    }
    return outlinedCursor { path in
      func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        horizontal ? NSPoint(x: x, y: y) : NSPoint(x: y, y: x)
      }
      path.move(to: point(3, 12))
      path.line(to: point(21, 12))
      for (x, delta) in [(CGFloat(3), CGFloat(6)), (21, -6)] {
        path.move(to: point(x + delta, 8))
        path.line(to: point(x, 12))
        path.line(to: point(x + delta, 16))
      }
    }
  }

  private static func diagonalCursor(rising: Bool) -> NSCursor {
    if #available(macOS 15.0, *) {
      return .frameResize(position: rising ? .topRight : .bottomRight, directions: .all)
    }
    return outlinedCursor { path in
      func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: x, y: rising ? y : 24 - y)
      }
      path.move(to: point(5, 5))
      path.line(to: point(19, 19))
      for (x, y, delta) in [(CGFloat(5), CGFloat(5), CGFloat(6)), (19, 19, -6)] {
        path.move(to: point(x, y + delta))
        path.line(to: point(x, y))
        path.line(to: point(x + delta, y))
      }
    }
  }

  private static func outlinedCursor(draw: @escaping (NSBezierPath) -> Void) -> NSCursor {
    let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
      let path = NSBezierPath()
      draw(path)
      path.lineCapStyle = .round
      path.lineJoinStyle = .round
      NSColor.white.setStroke()
      path.lineWidth = 4
      path.stroke()
      NSColor.black.setStroke()
      path.lineWidth = 2
      path.stroke()
      return true
    }
    return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
  }
}
