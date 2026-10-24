//
// TrackSelectionState.swift
// IINA
//
import Foundation

extension Notification.Name {
  static let iinaTrackOrderChanged = Notification.Name("IINATrackOrderChanged")
}

/// Range anchors use source IDs so playback changes and row indexes cannot move them.
struct TrackSelectionState {
  enum Action { case solo, toggle, range }
  private(set) var order: [Int] = []
  private(set) var anchor: Int?

  mutating func synchronize(_ ids: [Int]) {
    let available = Set(ids)
    order = ids
    if let anchor, !available.contains(anchor) { self.anchor = nil }
  }

  mutating func select(_ id: Int, action: Action, active: Set<Int>) -> Set<Int> {
    guard id != 0 else { anchor = nil; return [] }
    guard order.contains(id) else { return active }
    switch action {
    case .solo:
      anchor = nil
      return [id]
    case .toggle:
      anchor = nil
      if active == [id] { return active }
      var selected = active
      if !selected.insert(id).inserted { selected.remove(id) }
      return selected
    case .range:
      // First Shift-click only anchors the range; the second adds it to playback.
      guard let start = anchor else {
        anchor = id
        return active
      }
      guard let a = order.firstIndex(of: start), let b = order.firstIndex(of: id) else { return active }
      return active.union(order[min(a, b)...max(a, b)])
    }
  }

  static func selectionAfterRemoving(_ id: Int, order: [Int], active: Set<Int>) -> Set<Int> {
    let remaining = order.filter { $0 != id }
    let selected = active.intersection(remaining)
    guard selected.isEmpty, active.contains(id), !remaining.isEmpty,
          let index = order.firstIndex(of: id) else { return selected }
    return [remaining[min(index, remaining.count - 1)]]
  }


}

/// Keep input levels stable when adding tracks; limit only peaks in the sum.
enum AudioTrackMixGraph {
  static let target = "amix@iina_audio_mix"

  static func weights(_ ids: Set<Int>, inputs: Set<Int>) -> String {
    inputs.sorted().map { ids.contains($0) ? "1" : "0" }.joined(separator: " ")
  }

  static func make(_ ids: Set<Int>, inputs: Set<Int>? = nil) -> String? {
    let connected = inputs ?? ids
    guard !connected.isEmpty, connected.allSatisfy({ $0 > 0 }), ids.isSubset(of: connected),
          inputs != nil || ids.count > 1 else { return nil }
    let filter = inputs == nil ? "amix" : target
    let gains = inputs == nil ? "" : ":weights='\(weights(ids, inputs: connected))'"
    return connected.sorted().map { "[aid\($0)]" }.joined() +
      "\(filter)=inputs=\(connected.count):normalize=0:dropout_transition=0\(gains)," +
      "alimiter=level=false:latency=true[ao]"
  }
}

/// IDs run front-to-back; the bottom source defines the canvas. Preserve alpha until final composition.
enum VideoTrackLayerGraph {
  static func make(_ ids: [Int], width: Int, height: Int) -> String? {
    guard ids.count > 1, ids.allSatisfy({ $0 > 0 }), Set(ids).count == ids.count,
          width > 0, height > 0 else { return nil }
    var parts = ["[vid\(ids.last!)]format=rgba[vi0]"]
    for (offset, id) in ids.dropLast().reversed().enumerated() {
      parts.append("[vid\(id)]scale=w=\(width):h=\(height):force_original_aspect_ratio=decrease," +
                   "format=rgba[vl\(offset)]")
      let output = offset == ids.count - 2 ? "vo" : "vi\(offset + 1)"
      parts.append("[vi\(offset)][vl\(offset)]overlay=x=(main_w-overlay_w)/2:y=(main_h-overlay_h)/2:" +
                   "format=auto:alpha=straight:eof_action=pass[\(output)]")
    }
    return parts.joined(separator: ";")
  }
}
