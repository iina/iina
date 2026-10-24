// Test fixture: production capture and scale methods are injected by run.sh.
// This checks AppKit constraints and switching without constructing a full player.

import Cocoa
struct Preference {
  static var unlockWindowAspectRatio = false
  enum OSCPosition { case floating, top, bottom }
  enum ToolBarButton: Int { case pip = 1, plugins = 2, settings = 3 }
}
final class TestVolumeButton: NSView { let imageView = NSImageView() }
class NativeScaleHarness {
  var isApplyingVideoTransformWindowFrame = false
  var isFullscreenTransitionInProgress = false
  var oscPosition: Preference.OSCPosition = .floating
  var muteButton: TestVolumeButton! = TestVolumeButton()
  var volumeSlider: NSSlider! = NSSlider()
  var playButton: NSButton! = NSButton()
  var leftArrowButton: NSButton! = NSButton()
  var rightArrowButton: NSButton! = NSButton()
  var oscSpeedLabelLeftContainer: NSView! = NSView()
  var oscSpeedLabelRightContainer: NSView! = NSView()
  var oscToolbarView: NSStackView! = NSStackView()
  var oscVolumeView: NSView! = NSView()
  var leftLabel: NSTextField! = NSTextField(labelWithString: "")
  var rightLabel: NSTextField! = NSTextField(labelWithString: "")
  var oscSpeedLabelLeft: NSTextField! = NSTextField(labelWithString: "")
  var oscSpeedLabelRight: NSTextField! = NSTextField(labelWithString: "")
  var oscPlayControlMiddleView: NSStackView! = NSStackView()
  var oscPlayControlView: NSStackView! = NSStackView()
// PRODUCTION_PROPERTIES

  init() {
    for view in [muteButton!, playButton!, leftArrowButton!, rightArrowButton!] {
      view.translatesAutoresizingMaskIntoConstraints = false
      view.widthAnchor.constraint(equalToConstant: 24).isActive = true
      view.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }
    muteButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
    volumeSlider.translatesAutoresizingMaskIntoConstraints = false
    volumeSlider.widthAnchor.constraint(equalToConstant: 70).isActive = true
    volumeSlider.widthAnchor.constraint(equalToConstant: 70).isActive = true
    oscToolbarView.heightAnchor.constraint(equalToConstant: 24).isActive = true
// PRODUCTION_CAPTURE

  }
// PRODUCTION_METHODS

  // Toolbar preferences can rebuild these controls while the panel is compact.
  func rebuildToolbar(buttonCount: Int = 1) {
    oscToolbarView.views.forEach { oscToolbarView.removeView($0) }
    for _ in 0..<buttonCount {
      let button = NSButton()
      button.tag = Preference.ToolBarButton.plugins.rawValue
      button.translatesAutoresizingMaskIntoConstraints = false
      button.widthAnchor.constraint(equalToConstant: 24).isActive = true
      button.heightAnchor.constraint(equalToConstant: 24).isActive = true
      oscToolbarView.addView(button, in: .trailing)
    }
// PRODUCTION_TOOLBAR_CAPTURE
  }

  func verify() {
    let originalDistributions = [oscPlayControlView!.distribution, oscPlayControlMiddleView!.distribution, oscToolbarView!.distribution]
    updateFloatingOSCScale(scale: 0.8)
    precondition([oscPlayControlView!, oscPlayControlMiddleView!, oscToolbarView!].allSatisfy { $0.distribution == .fill })
    precondition(muteButton.constraints.filter { $0.firstAttribute == .width }.allSatisfy { abs($0.constant - 19.2) < 0.001 })
    precondition(volumeSlider.constraints.filter { $0.firstAttribute == .width }.allSatisfy { abs($0.constant - 56) < 0.001 })
    precondition(leftLabel.font!.pointSize == 10)
    precondition(abs(oscPlayControlMiddleView.spacing - 19.2) < 0.001)
    precondition(muteButton.imageView.symbolConfiguration != nil)
    rebuildToolbar()
    let toolbarButton = oscToolbarView.views[0] as! NSButton
    precondition(toolbarButton.constraints.allSatisfy { abs($0.constant - 19.2) < 0.001 })
    precondition(toolbarButton.symbolConfiguration != nil)
    for position: Preference.OSCPosition in [.top, .bottom] {
      oscPosition = position
      applyFloatingOSCControlScale()
      precondition([oscPlayControlView!.distribution, oscPlayControlMiddleView!.distribution, oscToolbarView!.distribution] == originalDistributions, "Docked stack distributions were not restored")
      precondition(muteButton.constraints.filter { $0.firstAttribute == .width }.allSatisfy { $0.constant == 24 })
      precondition(volumeSlider.constraints.filter { $0.firstAttribute == .width }.allSatisfy { $0.constant == 70 })
      precondition(leftLabel.font!.pointSize == 11)
      precondition(oscPlayControlMiddleView.spacing == 16)
      precondition(muteButton.imageView.symbolConfiguration == nil)
      precondition(toolbarButton.constraints.allSatisfy { $0.constant == 24 })
      precondition(toolbarButton.symbolConfiguration == nil)
    }
    oscPosition = .floating
    applyFloatingOSCControlScale()
    precondition(abs(oscPlayControlMiddleView.spacing - 19.2) < 0.001)
    precondition(abs(toolbarButton.constraints[0].constant - 19.2) < 0.001)
    rebuildToolbar()
    precondition(oscToolbarView.views[0].constraints.allSatisfy { abs($0.constant - 19.2) < 0.001 })
    updateFloatingOSCScale(scale: 2)
    precondition(floatingOSCScale == 1)
    updateFloatingOSCScale(scale: 0)
    precondition(floatingOSCScale == 0.8)
    print("PASS: native production scaling methods typecheck, duplicate dimensions scale, time remains readable, docked layouts restore, floating re-entry restores scale, bounds enforced")
  }
}
NativeScaleHarness().verify()
