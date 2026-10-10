// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import Foundation

enum SubtitleTarget: String, CaseIterable, Identifiable {
    case primary = "Primary", secondary = "Secondary"
    var id: String { rawValue }
}

struct SubtitleStyle: Codable, Equatable {
    var font = "Helvetica"
    var size = 55.0
    var color = "#FFFFFFFF"
    var borderColor = "#FF000000"
    var borderSize = 3.0
    var primaryPosition = 100.0
    var secondaryPosition = 0.0
    var overrideASS = false
    var encoding = "auto"

    static let encodings: [(String, String)] = [
        ("auto", "Automatic"), ("utf-8", "UTF-8"), ("utf-16", "UTF-16"),
        ("cp1252", "Western (Windows-1252)"), ("GB18030", "Simplified Chinese (GB18030)"),
        ("BIG5", "Traditional Chinese (Big5)"), ("SHIFT_JIS", "Japanese (Shift JIS)"),
        ("EUC-KR", "Korean (EUC-KR)"), ("cp1251", "Cyrillic (Windows-1251)")
    ]

    /// mpv sizes are relative to a 720-point reference frame, rather than device pixels.
    var properties: [(String, String)] {
        [("sub-font", font), ("sub-font-size", String(size)),
         ("sub-color", color), ("sub-border-color", borderColor),
         ("sub-border-size", String(borderSize)), ("sub-pos", String(primaryPosition)),
         ("secondary-sub-pos", String(secondaryPosition)),
         ("sub-ass-override", overrideASS ? "force" : "no"),
         ("secondary-sub-ass-override", overrideASS ? "force" : "strip"),
         ("sub-codepage", encoding)]
    }

    static func load(from defaults: UserDefaults = .standard) throws -> SubtitleStyle {
        guard let data = defaults.data(forKey: "subtitleStyle") else { return SubtitleStyle() }
        return try JSONDecoder().decode(SubtitleStyle.self, from: data)
    }

    func save(to defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(self), forKey: "subtitleStyle")
    }
}
