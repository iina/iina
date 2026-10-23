import Cocoa

extension Preference {
  static var floatingOSCDefaultPosition: FloatingOSCPosition {
    if let data = dictionary(for: .controlBarDefaultPlacement), let position = FloatingOSCPosition(dictionary: data) {
      return position
    }
    if isFloatingOSCDefaultPositionCustomized {
      return .percentages(CGFloat(float(for: .controlBarDefaultPositionHorizontal)) / 100,
                          CGFloat(float(for: .controlBarDefaultPositionVertical)) / 100)
    }
    return .initial
  }

  static func saveFloatingOSCDefaultPosition(_ position: FloatingOSCPosition) {
    set(position.dictionary, for: .controlBarDefaultPlacement)
  }
}
