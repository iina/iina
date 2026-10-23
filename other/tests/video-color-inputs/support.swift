import Cocoa
struct LayoutValue {
  let value: CGFloat
  func get() -> CGFloat { value }
  func use(_ body: @escaping (CGFloat) -> Void, applyNow: Bool = true) { if applyNow { body(value) } }
  static let sidebarItemSpacing = Self(value: 8)
}
extension NSImage.SymbolConfiguration { static let sidebarIconConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular) }
extension Notification.Name {
  static let iinaTrackSettingsChanged = Self("track-settings")
  static let iinaVideoEqualizerChanged = Self("video-eq")
}
enum TrackSettingsGroup { case videoColor }
struct ColorSettings {
  var brightness = 12, contrast = -8, saturation = 5, gamma = -2, hue = 17
}
final class PlayerCore {
  @discardableResult func performSidebarChange<T>(_ action: () -> T) -> T { action() }
  enum VideoEqualizerType { case brightness, contrast, saturation, gamma, hue }
  struct Window { struct Mode { var isActive = false }; var interactiveMode = Mode() }
  struct Targets { var id = 0; func target(_ group: TrackSettingsGroup) -> Int { id } }
  var mainWindow = Window(), scopedTrackSettings = Targets()
  var profiles = [0: ColorSettings(), 1: ColorSettings(brightness: -31, contrast: 20, saturation: 0, gamma: 0, hue: 0)]
  var observers: [Notification.Name: [(Notification) -> Void]] = [:]
  var rejectNextWrite = false
  var writes: [(target: Int, value: Int)] = []
  func scopedVideoSettings(_ group: TrackSettingsGroup) -> ColorSettings { profiles[scopedTrackSettings.id]! }
  func observe(_ name: Notification.Name, _ action: @escaping (Notification) -> Void) { observers[name, default: []].append(action) }
  func post(_ name: Notification.Name) { observers[name]?.forEach { $0(Notification(name: name)) } }
  func setScopedVideoEqualizer(_ type: VideoEqualizerType, value: Int) {
    writes.append((scopedTrackSettings.id, value))
    if rejectNextWrite { rejectNextWrite = false; post(.iinaTrackSettingsChanged); return }
    switch type {
    case .brightness: profiles[scopedTrackSettings.id]!.brightness = value
    case .contrast: profiles[scopedTrackSettings.id]!.contrast = value
    case .saturation: profiles[scopedTrackSettings.id]!.saturation = value
    case .gamma: profiles[scopedTrackSettings.id]!.gamma = value
    case .hue: profiles[scopedTrackSettings.id]!.hue = value
    }
    post(.iinaVideoEqualizerChanged)
  }
}
final class VideoLUTPopUp: NSPopUpButton {
  init(player: PlayerCore) { super.init(frame: .zero, pullsDown: false); addItem(withTitle: "None") }
  required init?(coder: NSCoder) { fatalError() }
}
extension UIHelper {
  func image(_ name: String, size: CGFloat, config: NSImage.SymbolConfiguration) -> NSImageView {
    image(NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config), size: size, scaleUp: false)
  }
  func vStack(spacing: LayoutValue, _ views: NSView...) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing.get()
    return stack
  }
}
