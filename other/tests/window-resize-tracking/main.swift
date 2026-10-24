var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  precondition(value(), message)
  checks += 1
}
func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.00001 }

for ratio in [NSSize(width: 16, height: 9), NSSize(width: 9, height: 16), NSSize(width: 1, height: 1)] {
  let aspect = ratio.width / ratio.height
  // Offset and negative coordinates cover screens to either side of the main display.
  for origin in [NSPoint(x: 300, y: 200), NSPoint(x: -1800, y: -500)] {
    let frame = NSRect(origin: origin, size: NSSize(width: 800, height: 800 / aspect))
    for right in [true, false] {
      for top in [true, false] {
        let start = NSPoint(x: right ? frame.maxX - 2 : frame.minX + 2,
                            y: top ? frame.maxY - 2 : frame.minY + 2)
        let session = WindowResizeSession(frame: frame, mouse: start, aspectRatio: ratio)!
        for dx: CGFloat in [-150, -100, -50, 0, 50, 100, 150, 0] {
          for dy: CGFloat in [-200, -100, 0, 100, 200] {
            let size = session.size(at: NSPoint(x: start.x + dx, y: start.y + dy))
            check(near(size.width, frame.width + (right ? dx : -dx)), "Corner width must follow horizontal pointer displacement exactly")
            check(near(size.width / size.height, aspect), "Lock Window Aspect Ratio must remain exact")
          }
        }
        check(session.size(at: NSPoint(x: start.x, y: start.y - 300)) == frame.size,
              "Moving a grabbed corner straight down must not shrink the window")
        check(session.size(at: start) == frame.size, "Returning the pointer must restore the initial size without accumulated drift")
      }
    }
    for top in [true, false] {
      let start = NSPoint(x: frame.midX, y: top ? frame.maxY : frame.minY)
      let session = WindowResizeSession(frame: frame, mouse: start, aspectRatio: ratio)!
      for dy: CGFloat in [-100, 0, 100] {
        let size = session.size(at: NSPoint(x: start.x + 100, y: start.y + dy))
        check(near(size.height, frame.height + (top ? dy : -dy)), "Top/bottom edge follows vertical displacement")
        check(near(size.width / size.height, aspect), "Vertical edge resizing keeps the aspect ratio")
      }
    }
    check(WindowResizeSession(frame: frame, mouse: NSPoint(x: frame.midX, y: frame.midY), aspectRatio: ratio) == nil,
          "Moving window contents must not start a resize session")
    check(WindowResizeSession(frame: frame, mouse: NSPoint(x: frame.maxX + 100, y: frame.maxY), aspectRatio: ratio) == nil,
          "Accessibility/programmatic resize without a pointer at the border keeps its native behavior")
  }
}
for ratio in [NSSize.zero, NSSize(width: -1, height: 1), NSSize(width: CGFloat.infinity, height: 1)] {
  check(WindowResizeSession(frame: NSRect(x: 0, y: 0, width: 800, height: 450), mouse: .zero, aspectRatio: ratio) == nil,
        "Unlocked or invalid aspect ratios must not create a proportional resize session")
}
print("Window resize tracking: \(checks) checks passed")

// Minimum padding must not become the next gesture's preferred aspect.
for ratio in [NSSize(width: 5, height: 4), NSSize(width: 4, height: 1)] {
  let initial = NSRect(x: -500, y: 100, width: ratio.width == 5 ? 400 : 800, height: 225)
  for horizontal in [true, false] {
    let start = NSPoint(x: horizontal ? initial.maxX : initial.midX,
                        y: horizontal ? initial.midY : initial.maxY)
    let session = WindowResizeSession(frame: initial, mouse: start, aspectRatio: ratio)!
    check(session.size(at: start) == initial.size, "A padded window cannot jump on mouse-down")
    var previous = initial.size
    for distance: CGFloat in stride(from: 0, through: 600, by: 1) {
      let pointer = NSPoint(x: start.x + (horizontal ? distance : 0),
                            y: start.y + (horizontal ? 0 : distance))
      let result = session.size(at: pointer)
      check(near(horizontal ? result.width : result.height,
                 (horizontal ? initial.width : initial.height) + distance),
            "The grabbed axis follows the pointer while padding recovers")
      check(result.width >= previous.width && result.height >= previous.height,
            "Enlarging a padded window cannot shrink either dimension")
      check(abs(result.width - previous.width) < 12 && abs(result.height - previous.height) < 12,
            "Aspect recovery has no discontinuous size step")
      previous = result
    }
    check(near(previous.width / previous.height, ratio.width / ratio.height),
          "Enlargement recovers the video aspect instead of scaling its black fields")
    check(session.size(at: start) == initial.size, "Reversing the drag restores its exact initial padding")
  }
}

print("Adaptive window resize tracking: \(checks) checks passed")
