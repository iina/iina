// Copyright © 2026 IINA contributors. Licensed under GPLv3.

import Foundation

protocol SharePlayPlayer: AnyObject {
  var sharePlaySnapshot: SharePlaySnapshot { get }
  func sharePlaySetPaused(_ paused: Bool)
  func sharePlaySetSpeed(_ speed: Double)
  func sharePlaySeek(to time: Double, completion: @escaping (Bool) -> Void)
}

protocol SharePlayCoordinating: AnyObject {
  func coordinate(rate: Double)
  func coordinate(seek: Double)
  func suspend(_ reason: SharePlaySuspension)
  func resume(_ reason: SharePlaySuspension)
  func resynchronize()
  func expectedPosition(at hostTime: Double) -> Double?
}

/// Owned and driven on the main thread, like PlayerCore's playback state.
final class SharePlayPlayback {
  enum Command {
    case play(item: UUID, time: Double, hostTime: Double, rate: Double)
    case pause(item: UUID, buffering: Bool)
    case seek(item: UUID, time: Double)
    case buffer(item: UUID)

    var item: UUID {
      switch self {
      case .play(let item, _, _, _), .pause(let item, _), .seek(let item, _), .buffer(let item): return item
      }
    }
  }

  let media: SharePlayMedia
  private(set) var active = true
  private(set) var suspensions = Set<SharePlaySuspension>()
  var onChange: (() -> Void)?
  var onFailure: ((String) -> Void)?
  private let player: SharePlayPlayer
  private let coordinator: SharePlayCoordinating
  private let clock: () -> Double
  private let url: URL?
  private var operation: UUID?
  private var completion: (() -> Void)?
  private var deadline = 0.0
  private var startAt: Double?
  private var startRate = 1.0
  private var seeking = false
  private var expectedPaused = true
  private var expectedSpeed = 1.0
  private var settleUntil = 0.0
  private var driftSamples = 0
  private var lastCorrection = -Double.infinity

  init(media: SharePlayMedia, player: SharePlayPlayer, coordinator: SharePlayCoordinating,
       clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
    self.media = media
    self.player = player
    self.coordinator = coordinator
    self.clock = clock
    url = player.sharePlaySnapshot.url
    expectedSpeed = player.sharePlaySnapshot.speed
  }

  func request(_ control: SharePlayControl) {
    guard active else { return }
    guard suspensions.isEmpty else {
      onFailure?("shareplay.suspended")
      return
    }
    let state = player.sharePlaySnapshot
    switch control {
    case .pause(let paused): coordinator.coordinate(rate: paused ? 0 : expectedSpeed)
    case .speed(let speed):
      guard speed.isFinite, speed > 0, speed <= 100 else { onFailure?("shareplay.unsupported"); return }
      expectedSpeed = speed
      if state.paused {
        player.sharePlaySetSpeed(speed)
        settleUntil = clock() + 0.5
      } else { coordinator.coordinate(rate: speed) }
    case .seek(let time):
      guard time.isFinite, state.seekable else { onFailure?("shareplay.unsupported"); return }
      coordinator.coordinate(seek: min(max(0, time), max(0, state.duration - 0.001)))
    case .blocked, .chapter: onFailure?("shareplay.unsupported")
    case .suspend: suspend(.automation); onFailure?("shareplay.automation")
    case .passthrough: break
    }
  }

  func receive(_ command: Command, maximumWait: Double = 8, completion: @escaping () -> Void) {
    guard active, command.item == media.id, suspensions.isEmpty else { completion(); return }
    finishPending()
    let ticket = UUID()
    operation = ticket
    self.completion = completion
    deadline = clock() + max(0, min(8, maximumWait))
    settleUntil = deadline
    setPaused(true)
    switch command {
    case .pause(_, let buffering):
      _ = buffering
      tick()
    case .buffer:
      tick()
    case .seek(_, let time):
      guard time.isFinite, time >= 0, time <= player.sharePlaySnapshot.duration else { fail(); return }
      seek(to: time, ticket: ticket)
    case .play(_, let time, let hostTime, let rate):
      let now = clock()
      // Buffer and seek ahead of a local start deadline, then unpause using the host clock.
      let start = max(now + 0.15, hostTime)
      guard let target = SharePlayTiming.position(itemTime: time, hostTime: hostTime, rate: rate,
                                                now: start, duration: player.sharePlaySnapshot.duration) else { fail(); return }
      startAt = start
      startRate = rate
      expectedSpeed = rate
      player.sharePlaySetSpeed(rate)
      if abs(target - player.sharePlaySnapshot.position) > 0.05 { seek(to: target, ticket: ticket) }
      else { tick() }
    }
  }

  private func seek(to time: Double, ticket: UUID) {
    seeking = true
    player.sharePlaySeek(to: time) { [weak self] success in
      guard let self, self.active, self.operation == ticket else { return }
      self.seeking = false
      if success { self.tick() }
      else { self.fail() }
    }
  }

  func tick() {
    guard active else { return }
    let now = clock()
    let state = player.sharePlaySnapshot
    guard state.url == url, state.loaded else {
      suspend(.automation)
      onFailure?("shareplay.media_changed")
      return
    }
    if operation != nil {
      if now >= deadline { fail(); return }
      guard !seeking, !state.buffering else { return }
      if let start = startAt {
        guard now >= start else { return }
        expectedSpeed = startRate
        player.sharePlaySetSpeed(startRate)
        setPaused(false)
      }
      finishPending()
      return
    }
    if state.buffering, !suspensions.contains(.buffering) { suspend(.buffering) }
    else if !state.buffering, suspensions.contains(.buffering) { resume(.buffering) }
    guard suspensions.isEmpty, now >= settleUntil else { return }
    if state.paused != expectedPaused || abs(state.speed - expectedSpeed) > 0.001 {
      suspend(.automation)
      onFailure?("shareplay.automation")
      return
    }
    guard !state.paused, let expected = coordinator.expectedPosition(at: now), expected.isFinite else { return }
    driftSamples = abs(expected - state.position) > 0.25 ? driftSamples + 1 : 0
    if driftSamples >= 3, now - lastCorrection >= 5 {
      driftSamples = 0
      lastCorrection = now
      coordinator.resynchronize()
    }
  }

  func suspend(_ reason: SharePlaySuspension) {
    guard active, suspensions.insert(reason).inserted else { return }
    coordinator.suspend(reason)
    finishPending()
    setPaused(true)
    onChange?()
  }

  func resume(_ reason: SharePlaySuspension) {
    guard active, suspensions.remove(reason) != nil else { return }
    settleUntil = clock() + 0.5
    coordinator.resume(reason)
    onChange?()
  }

  func rejoin() {
    for reason in suspensions { resume(reason) }
    coordinator.resynchronize()
  }

  func stop() {
    guard active else { return }
    active = false
    finishPending()
    setPaused(true)
    onChange?()
  }

  private func setPaused(_ paused: Bool) {
    expectedPaused = paused
    player.sharePlaySetPaused(paused)
  }

  private func fail() {
    suspend(.automation)
    onFailure?("shareplay.not_ready")
  }

  private func finishPending() {
    operation = nil
    startAt = nil
    seeking = false
    settleUntil = clock() + 0.5
    let callback = completion
    completion = nil
    callback?()
  }
}
