//
//  LyricsEngine.swift
//  iina
//
//  Created by Erik Molina on 12/21/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Foundation

struct LyricsEngine {

    private let lines: [LyricsLine]

    init(lines: [LyricsLine]) {
        self.lines = lines.sorted { $0.time < $1.time }
    }

    // MARK: - Current line

    func currentLine(at time: TimeInterval) -> LyricsLine? {
        guard !lines.isEmpty else { return nil }

        // Before first line
        if time < lines[0].time {
            return nil
        }

        // Binary search for last line whose time <= current time
        var low = 0
        var high = lines.count - 1

        while low <= high {
            let mid = (low + high) / 2
            let midTime = lines[mid].time

            if midTime == time {
                return lines[mid]
            } else if midTime < time {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return lines[max(0, high)]
    }

    // MARK: - Neighbors

    func previousLine(at time: TimeInterval) -> LyricsLine? {
        guard
            let current = currentLine(at: time),
            let index = lines.firstIndex(of: current),
            index > 0
        else {
            return nil
        }
        return lines[index - 1]
    }

    func nextLine(at time: TimeInterval) -> LyricsLine? {
        guard
            let current = currentLine(at: time),
            let index = lines.firstIndex(of: current),
            index < lines.count - 1
        else {
            return nil
        }
        return lines[index + 1]
    }
  
    func overlayState(at time: TimeInterval) -> LyricsOverlayState {
        guard let current = currentLine(at: time) else {
            return LyricsOverlayState(previous: nil, current: nil, next: nil)
        }

        guard let index = lines.firstIndex(where: { $0.time == current.time }) else {
            return LyricsOverlayState(previous: nil, current: current, next: nil)
        }

        let prev = index > 0 ? lines[index - 1] : nil
        let next = index + 1 < lines.count ? lines[index + 1] : nil

        return LyricsOverlayState(previous: prev, current: current, next: next)
    }

}

#if DEBUG
func _lyricsDebugSanityCheck() {
    let sample = """
    [00:13.23]My mama was raised in the era when
    [00:16.04]Clean water was only served to the fairer skin
    [00:19.47]Doin' clothes, you woulda thought I had help
    [00:21.76]But they wasn't satisfied unless I picked the cotton myself
    [00:24.85]
    [00:24.97]You see it's broke racism, that's that, don't touch anything in the store
    """

    let parsed = LRCParser.parse(sample)
    let engine = LyricsEngine(lines: parsed)

    print("=== Lyrics Debug Sanity Check ===")
    for t in stride(from: 10.0, through: 30.0, by: 2.5) {
        let line = engine.currentLine(at: t)
        print(String(format: "t=%.2f → %@", t, line?.text ?? "nil"))
    }
    print("================================")
}
#endif
