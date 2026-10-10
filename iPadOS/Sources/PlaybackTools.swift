// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import AVFoundation
import UIKit

enum RepeatMode: String, CaseIterable, Codable {
    case off = "Off", one = "One file", all = "Playlist"
}

struct PlaybackDiagnostics {
    var bufferedSeconds: Double?
    var cacheBytes: Double?
    var droppedFrames: Double?
    var decoderDroppedFrames: Double?
    var observedBitrate: Double?
    var stalls: Double?
    var renderingMilliseconds: Double?
    var renderedFrames: Int?
    var rendererDroppedFrames: Int?
    var renderedSize: CGSize?
    var waitingReason = ""
}

struct CapturedFrame: Identifiable {
    let id = UUID()
    let image: UIImage
    let time: Double
    let title: String
}

enum PlaybackToolError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let message): return message }
    }
}

enum PlaybackTimestamp {
    static func parse(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var result = 0.0
        for (index, part) in parts.enumerated() {
            guard !part.isEmpty, let value = Double(part), value.isFinite, value >= 0,
                  index == 0 || value < 60,
                  index == parts.count - 1 || value.rounded(.down) == value else { return nil }
            result = result * 60 + value
        }
        return result.isFinite ? result : nil
    }
}

enum PlayerShortcut: String, CaseIterable, Codable {
    case space = "Space", left = "←", right = "→", up = "↑", down = "↓"
    case j = "J", k = "K", l = "L", a = "A", b = "B", r = "R"
    case comma = ",", period = ".", commandS = "⌘S", commandJ = "⌘J"
}

enum PlayerControlAction: String, CaseIterable, Codable, Identifiable {
    case pause = "Play / Pause", backward = "Seek backward", forward = "Seek forward"
    case frameBackward = "Previous frame", frameForward = "Next frame"
    case screenshot = "Capture frame", jump = "Jump to time"
    var id: String { rawValue }
    var defaultShortcut: PlayerShortcut {
        switch self {
        case .pause: return .space
        case .backward: return .left
        case .forward: return .right
        case .frameBackward: return .comma
        case .frameForward: return .period
        case .screenshot: return .commandS
        case .jump: return .commandJ
        }
    }
}

struct ControlPreferences: Codable, Equatable {
    var seekSeconds = 10.0
    var holdSpeed = 2.0
    var holdEnabled = true
    var swipeEnabled = true
    var keepControlsVisible = false
    var dockControls = false
    var dockSidebar = true
    var sidebarWidth = 390.0
    var allowRemotePreviews = false
    var shortcuts: [String: PlayerShortcut] = [:]

    func shortcut(for action: PlayerControlAction) -> PlayerShortcut {
        shortcuts[action.rawValue] ?? action.defaultShortcut
    }

    var isValid: Bool {
        (1...120).contains(seekSeconds) && (0.5...8).contains(holdSpeed) &&
        (280...520).contains(sidebarWidth) &&
        Set(PlayerControlAction.allCases.map { shortcut(for: $0) }).count == PlayerControlAction.allCases.count
    }

    static func load() throws -> Self {
        guard let data = UserDefaults.standard.data(forKey: "IINA.ControlPreferences.v1") else { return Self() }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.isValid else { throw PlaybackToolError.unavailable("Saved control settings are invalid.") }
        return value
    }

    func save() throws {
        guard isValid else { throw PlaybackToolError.unavailable("Control settings are outside the supported range or contain duplicate shortcuts.") }
        UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: "IINA.ControlPreferences.v1")
    }
}
