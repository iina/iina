//
//  LRCParser.swift
//  iina
//
//  Created by Erik Molina on 12/21/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Foundation

struct LRCParser {

    static func parse(_ content: String) -> [LyricsLine] {
        var result: [LyricsLine] = []

        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            guard let parsed = parseLine(line) else {
                continue
            }
            result.append(contentsOf: parsed)
        }

        return result.sorted { $0.time < $1.time }
    }

    private static func parseLine(_ line: String) -> [LyricsLine]? {
        // Match patterns like [mm:ss.xx]
        let pattern = #"\[(\d+):(\d+(?:\.\d+)?)\]"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let matches = regex.matches(
            in: line,
            range: NSRange(line.startIndex..., in: line)
        )

        guard !matches.isEmpty else {
            return nil
        }

        let text = regex.stringByReplacingMatches(
            in: line,
            range: NSRange(line.startIndex..., in: line),
            withTemplate: ""
        ).trimmingCharacters(in: .whitespaces)

        var result: [LyricsLine] = []

        for match in matches {
            guard
                let minRange = Range(match.range(at: 1), in: line),
                let secRange = Range(match.range(at: 2), in: line),
                let minutes = Double(line[minRange]),
                let seconds = Double(line[secRange])
            else {
                continue
            }

            let time = minutes * 60 + seconds
            result.append(LyricsLine(time: time, text: text))
        }

        return result
    }
}
