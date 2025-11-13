//
//  PlaybackSpeedStep.swift
//  IINA
//
//  Discrete 0.25x stepping logic used when the user holds a modifier
//  while scrolling to change playback speed. Kept pure for unit testing.
//

import Foundation

enum PlaybackSpeedStep {

  private static let eps: Double = 1e-6

  /// Build a 0.25x grid between 0.25 and `max`, inclusive.
  /// - Parameter max: upper bound (e.g., 4.0). Must be >= 0.25.
  private static func grid(max: Double) -> [Double] {
    let upper = max < 0.25 ? 0.25 : max
    let steps = Int((upper / 0.25).rounded(.down))
    return (1...steps).map { Double($0) * 0.25 }
  }

  /// Clamp a value to the 0.25-grid range [0.25, max].
  static func clampToGridRange(_ value: Double, max: Double) -> Double {
    if value < 0.25 { return 0.25 }
    if value > max { return max }
    return value
  }

  /// Return the next allowed value strictly greater than `current` within [0.25, max].
  private static func nextUp(from current: Double, max: Double) -> Double {
    let c = current
    for v in grid(max: max) {
      if v - c > eps { return v }
    }
    return max
  }

  /// Return the next allowed value strictly less than `current` within [0.25, max].
  private static func nextDown(from current: Double, max: Double) -> Double {
    let c = current
    for v in grid(max: max).reversed() {
      if c - v > eps { return v }
    }
    return 0.25
  }

  /// Snap to the nearest 0.25 multiple within [0.25, max].
  static func snap(_ value: Double, max: Double) -> Double {
    let clamped = clampToGridRange(value, max: max)
    let quantized = (clamped / 0.25).rounded() * 0.25
    return clampToGridRange(quantized, max: max)
  }

  /// Step from `current` by one grid unit (0.25) up (+1) or down (-1), within [0.25, max].
  /// Out-of-range handling:
  ///  - Above `max`: up → max; down → max - 0.25
  ///  - Below 0.25: up/down → 0.25 (lowest allowed when Option is held)
  static func step(from current: Double, direction: Int, max: Double) -> Double {
    let dir = direction == 0 ? 0 : (direction > 0 ? 1 : -1)
    guard dir != 0 else { return snap(current, max: max) }

    if current > max { return dir > 0 ? max : max - 0.25 }
    if current < 0.25 { return 0.25 }

    return dir > 0 ? nextUp(from: current, max: max) : nextDown(from: current, max: max)
  }
}
