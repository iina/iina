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

        #if DEBUG
        print("🎵 Loaded lyrics: \(lines.count) lines")
        #endif
    }

    func clear() {
        engine = nil
        currentLine = nil
        
        // Explicitly clear overlay
        emitOverlayUpdate(
            LyricsOverlayState(previous: nil, current: nil, next: nil)
        )
    }

    private func emitOverlayUpdate(_ state: LyricsOverlayState) {
        NotificationCenter.default.post(
            name: .iinaLyricsOverlayUpdated,
            object: self,
            userInfo: ["state": state]
        )
    }

    // MARK: - Time sync (called from PlayerCore)
    func syncTime(_ time: TimeInterval) {
        guard let engine else { return }

        let state = engine.overlayState(at: time)

        guard state.current?.time != currentLine?.time else { return }

        currentLine = state.current
      
        emitOverlayUpdate(state)

        #if DEBUG
        if let line = state.current {
            print("🎵 \(line.text)")
        }
        #endif
    }


    // MARK: - Overlay state (next step)
    func overlayState(at time: TimeInterval) -> LyricsOverlayState {
        guard let engine else {
            return LyricsOverlayState(previous: nil, current: nil, next: nil)
        }

        return LyricsOverlayState(
            previous: engine.previousLine(at: time),
            current: engine.currentLine(at: time),
            next: engine.nextLine(at: time)
        )
    }
    
    @objc private func lyricsVisibilityChanged() {
        if !player.info.isLyricsVisible {
          // Hide Lyrics
            emitOverlayUpdate(
                LyricsOverlayState(previous: nil, current: nil, next: nil)
            )
        }
    }

}
    
