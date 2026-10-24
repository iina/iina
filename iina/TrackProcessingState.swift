import Foundation

enum TrackSettingsGroup: String, CaseIterable {
  case audioDelay, audioEQ, videoGeometry, videoColor
  var isAudio: Bool { self == .audioDelay || self == .audioEQ }
  var titleKey: String {
    switch self {
    case .audioDelay: return "sidebar.delay"
    case .audioEQ: return "sidebar.eq"
    case .videoGeometry: return "track_settings.geometry"
    case .videoColor: return "track_settings.color"
    }
  }
}

/// One editing context per media type, independent of playback membership.
struct TrackProcessingState: Codable, Equatable {
  private(set) var audioTarget = 0
  private(set) var videoTarget = 0
  var audio: [Int: AudioTrackProcessing] = [:]
  var video: [Int: VideoTrackProcessing] = [:]
  func target(_ group: TrackSettingsGroup) -> Int { group.isAudio ? audioTarget : videoTarget }
  mutating func setTarget(_ id: Int, for group: TrackSettingsGroup) {
    if group.isAudio { audioTarget = id } else { videoTarget = id }
  }
  mutating func reset(_ group: TrackSettingsGroup, trackID: Int? = nil) {
    if group.isAudio {
      for id in Array(audio.keys) where trackID == nil || id == trackID {
        if group == .audioDelay { audio[id]?.delay = 0 }
        else { audio[id]?.gains = Array(repeating: 0, count: 10) }
        if audio[id]?.isNeutral == true { audio.removeValue(forKey: id) }
      }
    } else {
      for id in Array(video.keys) where trackID == nil || id == trackID {
        if group == .videoGeometry {
          video[id]?.aspect = "Default"; video[id]?.crop = nil
          video[id]?.cropDescription = "None"; video[id]?.rotation = 0
        } else {
          video[id]?.brightness = 0; video[id]?.contrast = 0
          video[id]?.saturation = 0; video[id]?.gamma = 0; video[id]?.hue = 0
          video[id]?.lutPath = nil
        }
        if video[id]?.isNeutral == true { video.removeValue(forKey: id) }
      }
    }
  }
}

extension Notification.Name {
  static let iinaTrackSettingsChanged = Notification.Name("IINATrackSettingsChanged")
}
