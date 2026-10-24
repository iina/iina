# Generate a native fixture around the production shared-control construction,
# anchored setup, material wrappers and immediate proposed resize methods.
from pathlib import Path
import sys
repo, tests, output = map(Path, sys.argv[1:]); src=(repo/'iina/MainWindowController.swift').read_text(); osc=(repo/'iina/OSCFloatingView.swift').read_text()
def extract(text, marker):
    start=text.index(marker); opening=text.index('{',start); end=opening+1; balance=1
    while balance:
        if text[end]=='{': balance+=1
        if text[end]=='}': balance-=1
        end+=1
    return text[start:end]
def section(text,start,end): return text[text.index(start):text.index(end,text.index(start))]
base=(tests/'NativeHarness.swift').read_text()
base=base[:base.index('  func verify() {')]
base='import Cocoa\n' + base
base=base.replace('class NativeScaleHarness {','class NativeScaleHarness {\n  var oscSliderView: NSView!\n  var loaded = true\n  var interactiveMode = LayoutInteractiveMode()\n  var minimumWindowSize: NSSize { AppData.floatingOSCWindowMinSize }\n  var currentWindowAspectRatio: NSSize { nativeWindow.aspectRatio }\n  func windowFrameConstrainedToScreen(_ frame: NSRect, screenFrame: NSRect?) -> NSRect { frame }\n  var window: NSWindow? { nativeWindow }\n  let player = LayoutPlayerStub()\n  let liveText = LayoutLiveTextStub()\n  let videoView = LayoutVideoViewStub()\n  var mpvUpdateCalls = 0\n  func updateWindowParametersForMPV() { mpvUpdateCalls += 1 }\n  var playSlider: NSSlider! = NSSlider()\n  @objc func leftButtonAction() {}\n  @objc func rightButtonAction() {}\n  var currentControlBar: NSView?\n  var oscFloatingView = TestPanel()\n  let nativeWindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 506), styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)\n')
base=base.replace('  var loaded = true', '  var loaded = true\n  var windowResizeSession: WindowResizeSession?\n  var isCropTransitionInProgress = false\n  func setWindowAspectRatio(_ size: NSSize) { nativeWindow.aspectRatio = size }\n  func rememberVideoTransformWindowResize() {}')
start=base.index('  init() {'); end=base.index('// PRODUCTION_METHODS')
setup=section(src,'    volumeSlider.size(width: 70)','    // osd\n')
base=base[:start]+'  init() {\n    [muteButton!, volumeSlider!, playSlider!, leftLabel!, rightLabel!].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }\n    volumeSlider.controlSize = .mini\n    playSlider.controlSize = .small\n    muteButton.size(width: 24, height: 24)\n'+setup+'\n    buildNativeGroups()\n  }\n'+base[end:]
base=base.replace('// PRODUCTION_PROPERTIES',section(src,'  private(set) var floatingOSCScale','  var osdView:'))
base=base.replace('// PRODUCTION_METHODS',section(src,'  func updateFloatingOSCScale(scale:','  // MARK: - Mouse / Trackpad events'))
base=base.replace('// PRODUCTION_TOOLBAR_CAPTURE',section(src,'    floatingOSCToolbarConstraints =','//    let menuButton'))
base += extract(src, '  func windowWillResize(') + '\n' + extract(src, '  private func invalidateFloatingOSCLayout()') + '\n' + extract(src, '  func windowDidEndLiveResize(') + '\n' + (tests/'LayoutChecks.swift').read_text()
base=base.replace('// GROUP_SETUP',section(src,'      currentControlBar = oscFloatingView','    case .top:'))
panel='''
let isMacOS11 = false
struct LayoutValue {
  let value: CGFloat
  init(_ value: CGFloat, _ compact: CGFloat? = nil) { self.value = value }
  func get() -> CGFloat { value }
  func use(_ block: (CGFloat) -> Void) { block(value) }
}
extension NSImage {
  static var speedl: NSImage { NSImage(size: NSSize(width: 24, height: 24)) }
  static var speed: NSImage { NSImage(size: NSSize(width: 24, height: 24)) }
}
enum Utility {
// QUICK_CONSTRAINTS
}
class TestPanel: TranslucentView {
  private let width: CGFloat = 460
  var preferredWidthConstraint: NSLayoutConstraint!
  var paddingConstraints: [(constraint: NSLayoutConstraint, regular: CGFloat, compact: CGFloat)] = []
  var oscTopView: NSStackView!
  var oscBottomView: TimeLabelOverflowedStackView!
  init() {
    super.init(liquidGlassCornerRadius: 12, vevCornerRadius: 6, padding: (0,0))
    translatesAutoresizingMaskIntoConstraints = false
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false
// PANEL_SETUP
  }
  required init?(coder: NSCoder) { fatalError() }
  var positionUpdateCount = 0
  func initPosition() {}
  func updatePosition() { positionUpdateCount += 1 }
  func applyScale(_ scale: CGFloat, compact: Bool = false) {
    preferredWidthConstraint.constant = width * scale
    for item in paddingConstraints { item.constraint.constant = (compact ? item.compact : item.regular) * scale }
  }
}
'''
panel=panel.replace('// QUICK_CONSTRAINTS',section((repo/'iina/Utility.swift').read_text(),'  static func quickConstraints(','  /// Calculates and returns a MD5'))
panel=panel.replace('// PANEL_SETUP',section(osc,'    self.oscTopView = NSStackView()','    prefObserver.add(.useLiquidGlassOSC'))
panel += '\nenum AppData {\n' + '\n'.join(line for line in (repo/'iina/AppData.swift').read_text().splitlines() if 'static let floatingOSCWindowMinSize =' in line) + '\n}\n'
panel += '\nextension NSSize {\n' + extract((repo/'iina/Extensions.swift').read_text(), '  var aspect: CGFloat {') + '\n' + extract((repo/'iina/Extensions.swift').read_text(), '  func grow(toSize size:') + '\n}\n'
files=['iina/TranslucentView.swift','iina/ConstraintsSugar.swift','iina/TimeLabelOverflowedStackView.swift','iina/TimeLabelOverflowedView.swift']
(output/'main.swift').write_text(base[:base.index('struct Preference')]+(tests/'LayoutSupport.swift').read_text()+panel+'\n'+ '\n'.join((repo/f).read_text() for f in files)+'\n'+base[base.index('struct Preference'):])

# Proportional resize sessions belong to the geometry part, not this extraction.
text=(output/'main.swift').read_text().replace('  var windowResizeSession: WindowResizeSession?\n', '')
(output/'main.swift').write_text(text)
