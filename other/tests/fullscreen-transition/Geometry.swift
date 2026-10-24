import Cocoa
enum PIP { case notInPIP, inPIP }
enum OSC { case floating, bottom }
class State { var active = true }
class Info { let state = State() }
class Player { let info = Info(); var videoSizeForDisplay = (3840, 1646) }
class Layer {
  var began = 0; var ended = 0; var cancelled = false; var updates = 0
  func beginFullscreenTransition() { began += 1 }
  func endFullscreenTransition(cancelled: Bool = false) { ended += 1; self.cancelled = cancelled }
  func update(force: Bool) { updates += 1 }
}
class Video: NSView { let videoLayer = Layer() }
class Editor { var isActive = false }
class Panel { func updatePosition() {} }
class Controller {
  let player = Player()
  let interactiveMode = Editor()
  var pipStatus = PIP.notInPIP
  var isCropTransitionInProgress = false
  var fullscreenVideoConstraints: [NSLayoutConstraint] = []
  var videoViewConstraints: [NSLayoutConstraint.Attribute: NSLayoutConstraint] = [:]
  var window: NSWindow?
  var videoViewContainer = NSView()
  let videoView = Video()
  var loaded = true
  var oscPosition = OSC.floating
  let oscFloatingView = Panel()
  var invalidations = 0
  func invalidateFloatingOSCLayout() { invalidations += 1 }
  // PRODUCTION_GEOMETRY
}
let app = NSApplication.shared
let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 450),
                      styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
let fixture = Controller()
fixture.window = window
let container = fixture.videoViewContainer, video = fixture.videoView
window.contentView!.addSubview(container)
container.translatesAutoresizingMaskIntoConstraints = false
let viewportWidth = container.widthAnchor.constraint(equalToConstant: 800)
let viewportHeight = container.heightAnchor.constraint(equalToConstant: 450)
NSLayoutConstraint.activate([viewportWidth, viewportHeight,
                            container.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
                            container.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor)])
container.addSubview(video); video.translatesAutoresizingMaskIntoConstraints = false
fixture.videoViewConstraints = [
  .leading: video.leadingAnchor.constraint(equalTo: container.leadingAnchor),
  .trailing: container.trailingAnchor.constraint(equalTo: video.trailingAnchor),
  .top: video.topAnchor.constraint(equalTo: container.topAnchor),
  .bottom: container.bottomAnchor.constraint(equalTo: video.bottomAnchor)
]
NSLayoutConstraint.activate(Array(fixture.videoViewConstraints.values))
var checks = 0
func check(_ value: Bool, _ message: String) { if !value { print("FAILED: " + message); exit(1) }; checks += 1 }
for size in [(3840,1646), (900,1600), (1920,1080)] {
  fixture.player.videoSizeForDisplay = size
  fixture.beginFullscreenVideoTransition()
  check(video.videoLayer.began > 0, "fullscreen begins a surface transition")
  for bounds in [NSSize(width: 800,height: 450), NSSize(width: 1200,height: 800),
                 NSSize(width: 1800,height: 1090), NSSize(width: 800,height: 225)] {
    viewportWidth.constant = bounds.width; viewportHeight.constant = bounds.height
    window.contentView!.layoutSubtreeIfNeeded()
    let frame = video.frame, ratio = CGFloat(size.0) / CGFloat(size.1)
    check(abs(frame.width - frame.height * ratio) <= max(ratio, 1) * 0.6,
          "image aspect is stable through window resize, allowing AppKit pixel alignment")
    check(abs(frame.midX - container.bounds.midX) < 0.6 && abs(frame.midY - container.bounds.midY) < 0.6,
          "image stays centered")
    check(frame.width <= bounds.width + 0.6 && frame.height <= bounds.height + 0.6,
          "image remains fully visible")
    check(abs(frame.width - bounds.width) < 0.6 || abs(frame.height - bounds.height) < 0.6,
          "image fills one limiting axis")
  }
  fixture.finishFullscreenVideoTransition()
  check(fixture.fullscreenVideoConstraints.isEmpty, "temporary constraints released")
  check(fixture.videoViewConstraints.values.allSatisfy(\.isActive), "original geometry constraints restored")
  check(video.frame == container.bounds, "normal rendering regains full viewport")
}
fixture.beginFullscreenVideoTransition(); fixture.finishFullscreenVideoTransition(cancelled: true)
check(video.videoLayer.cancelled, "close cancels surface work")
fixture.pipStatus = .inPIP; let began = video.videoLayer.began
fixture.beginFullscreenVideoTransition()
check(video.videoLayer.began == began, "PiP retains its native surface owner")
fixture.pipStatus = .notInPIP; fixture.interactiveMode.isActive = true
fixture.beginFullscreenVideoTransition()
check(video.videoLayer.began == began, "crop editor retains its geometry owner")
print("Passed \(checks) fullscreen image geometry checks")
