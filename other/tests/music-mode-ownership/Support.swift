import Cocoa

class WindowActionBase {
  func handleIINACommand(_ cmd: IINACommand) {}
}
extension Logger {
  static func log(_ message: String, level: Level, subsystem: String) {}
}
extension NSMenuItem { static var dummy: NSMenuItem { NSMenuItem() } }
extension Notification.Name { static let iinaMusicModeChanged = Self("music-mode-ownership.changed") }
extension Utility {
  static func quickConstraints(_ formats: [String], _ views: [String: NSView]) {
    for format in formats {
      NSLayoutConstraint.activate(NSLayoutConstraint.constraints(withVisualFormat: format, options: [], metrics: nil, views: views))
    }
  }
}
final class SidebarFixture {
  final class Playlist {
    let view = NSView()
    var downShift: CGFloat = 0
    var isInMiniPlayer = false
  }
  let playlistView = Playlist()
  var isAnyVisible = false
  func hideAllSideBars(animate: Bool) {}
}
final class EventFixture {
  enum Event { case musicModeChanged }
  var emitted: [Bool] = []
  func emit(_ event: Event, data: Bool) { emitted.append(data) }
}
final class MiniFixture {
  var loaded = true, isPlaylistVisible = false, pendingShow = false
  var window: NSWindow? = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                                   styleMask: .borderless, backing: .buffered, defer: false)
  let playlistWrapperView = NSView(), videoWrapperView = NSView()
  var videoView: NSView!
  var videoViewAspectConstraint: NSLayoutConstraint?
  func updateTitle() {}
  func refreshArtworkVisibility() {}
  func videoSizeForDisplayInMusicMode() -> (Int, Int) { (960, 540) }
  func updateVideoViewAspectConstraint(withAspect: CGFloat) {}
  func setToInitialWindowSize(display: Bool, animate: Bool) {}
  func toggleVideoView(_ sender: Any?) {}
  func togglePlaylist(_ sender: Any?) {}
  func setupUI() {}
}
