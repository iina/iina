//
//  LyricsController.swift
//  iina
//
//  Created by Erik Molina on 12/21/25.
//

import Foundation

final class LyricsController {
  
  private unowned let player: PlayerCore
  
  private var engine: LyricsEngine?
  private var currentLine: LyricsLine?
  private var lastSyncedTime: TimeInterval?
  
  // Injected from UI layer to avoid circular dependency between controller and view.
  // Falls back to engine's default if not set.
  var visibleLineCountProvider: (() -> Int)?
  
  init(player: PlayerCore) {
    self.player = player
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(lyricsVisibilityChanged),
      name: .iinaLyricsVisibilityChanged,
      object: nil
    )
  }
  
  // MARK: - Loading
  
  func loadLyrics(_ lines: [LyricsLine]) {
    engine = LyricsEngine(lines: lines)
    currentLine = nil
  }
  
  /// Clears all lyrics state (used when unloading or switching tracks).
  func clear() {
    engine = nil
    currentLine = nil
    lastSyncedTime = nil
    
    // Emit empty overlay to clear UI immediately rather than waiting for next playback sync.
    emitOverlayUpdate(
      LyricsOverlayState(previous: nil, current: nil, next: nil, allLines: [], currentIndex: -1)
    )
  }
  
  /// Clears only the overlay/UI state while preserving the engine,
  /// allowing lyrics to be re-shown without reloading.
  private func clearOverlay() {
    currentLine = nil
    
    emitOverlayUpdate(
      LyricsOverlayState(previous: nil, current: nil, next: nil, allLines: [], currentIndex: -1)
    )
  }
  
  // MARK: - Notifications
  
  // Single outbound notification point for lyrics overlay UI updates.
  private func emitOverlayUpdate(_ state: LyricsOverlayState) {
    NotificationCenter.default.post(
      name: .iinaLyricsOverlayUpdated,
      object: self,
      userInfo: ["state": state]
    )
  }
  
  // MARK: - Time sync (called from PlayerCore)
  
  func syncTime(_ time: TimeInterval) {
    syncTime(time, force: false)
  }

  func refreshCurrentOverlay() {
    guard let lastSyncedTime else { return }
    syncTime(lastSyncedTime, force: true)
  }

  private func syncTime(_ time: TimeInterval, force: Bool) {
    lastSyncedTime = time
    guard let engine else { return }

    let defaultVisibleLineCount = 7
    let visibleLineCount = visibleLineCountProvider?() ?? defaultVisibleLineCount
    let state = engine.overlayState(at: time, visibleLinesCount: visibleLineCount)

    guard force || state.current?.time != currentLine?.time else { return }

    currentLine = state.current
    emitOverlayUpdate(state)
  }
  
  // MARK: - Visibility
  
  // Responds to user toggling lyrics visibility.
  @objc private func lyricsVisibilityChanged() {
    if !player.info.isLyricsVisible {
      // Hide overlay but keep engine so lyrics can be restored.
      clearOverlay()
    }
  }
  
}
