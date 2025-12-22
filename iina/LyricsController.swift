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
    var onOverlayUpdate: ((LyricsOverlayState) -> Void)?

    init(player: PlayerCore) {
        self.player = player
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
    }

    // MARK: - Time sync (called from PlayerCore)
    func syncTime(_ time: TimeInterval) {
        guard let engine else { return }

        let state = engine.overlayState(at: time)

        guard state.current?.time != currentLine?.time else { return }

        currentLine = state.current
      
        onOverlayUpdate?(state)

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
}
