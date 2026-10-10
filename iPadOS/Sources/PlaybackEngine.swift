// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import Foundation
import UIKit

enum PlaybackBackend: String {
    case native = "AVPlayer"
    case mpv = "mpv"
}

/// Both backends report the same state to the UI and media session.
/// mpv submits client commands to a dedicated worker.
protocol PlaybackEngine: AnyObject {
    func open(_ url: URL, start: Double, paused: Bool)
    func set(_ name: String, _ value: String)
    func command(_ arguments: [String])
    func setLoop(_ range: ClosedRange<Double>?)
    func captureFrame(completion: @escaping (Result<UIImage, Error>) -> Void)
    func requestShutdown(completion: @escaping () -> Void)
}

extension PlaybackEngine {
    func requestShutdown() { requestShutdown(completion: {}) }
    func setLoop(_ range: ClosedRange<Double>?) {
        set("ab-loop-a", range.map { String(max(0.000001, $0.lowerBound)) } ?? "no")
        set("ab-loop-b", range.map { String($0.upperBound) } ?? "no")
    }
}
