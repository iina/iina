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

    func currentLine(at time: TimeInterval) -> LyricsLine? {
        guard !lines.isEmpty else {
            return nil
        }

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
}
