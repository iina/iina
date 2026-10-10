// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import Foundation
import CoreGraphics

enum VideoAspect: String, CaseIterable {
    case original = "Default"
    case fourThree = "4:3", sixteenNine = "16:9", sixteenTen = "16:10"
    case twentyOneNine = "21:9", fiveFour = "5:4", square = "1:1"

    var ratio: Double? {
        let parts = rawValue.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] / parts[1]
    }
}

enum VideoAdjustment: String, CaseIterable {
    case brightness = "Brightness", contrast = "Contrast", saturation = "Saturation"
    case gamma = "Gamma", hue = "Hue"
}

enum PlaybackRates {
    static let presets = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 4.0, 8.0, 16.0]
    static let quick = [0.5, 1.0, 2.0, 4.0, 8.0]
    static let range = 0.25...16.0
}

/// Session settings shared by the panel and the compatibility renderer.
/// Filters run before mpv overlays subtitles, including in PiP.
struct VideoSettings: Equatable {
    var aspect = VideoAspect.original
    var crop = VideoAspect.original
    var rotation = 0
    var hardwareDecoding = true
    var brightness = 0.0
    var contrast = 0.0
    var saturation = 0.0
    var gamma = 0.0
    var hue = 0.0

    subscript(_ adjustment: VideoAdjustment) -> Double {
        get {
            switch adjustment {
            case .brightness: return brightness
            case .contrast: return contrast
            case .saturation: return saturation
            case .gamma: return gamma
            case .hue: return hue
            }
        }
        set {
            switch adjustment {
            case .brightness: brightness = newValue
            case .contrast: contrast = newValue
            case .saturation: saturation = newValue
            case .gamma: gamma = newValue
            case .hue: hue = newValue
            }
        }
    }

    var isValid: Bool {
        [0, 90, 180, 270].contains(rotation) &&
        VideoAdjustment.allCases.allSatisfy { self[$0].isFinite && (-100...100).contains(self[$0]) }
    }

    var requiresMPV: Bool { self != VideoSettings() }

    var hasColorAdjustments: Bool { VideoAdjustment.allCases.contains { self[$0] != 0 } }

    func cropRectangle(in size: CGSize) -> String {
        guard let cropRatio = crop.ratio, size.width >= 2, size.height >= 2 else { return "" }
        let ratio = rotation == 90 || rotation == 270 ? 1 / cropRatio : cropRatio
        let width = max(2, Int(min(size.width, size.height * ratio) / 2) * 2)
        let height = max(2, Int(min(size.height, size.width / ratio) / 2) * 2)
        let x = max(0, Int((size.width - Double(width)) / 4) * 2)
        let y = max(0, Int((size.height - Double(height)) / 4) * 2)
        return "\(width)x\(height)+\(x)+\(y)"
    }

    var aspectValue: String { aspect == .original ? "no" : orientedRatio(aspect) }

    private func orientedRatio(_ value: VideoAspect) -> String {
        if rotation == 90 || rotation == 270 { return value.rawValue.split(separator: ":").reversed().joined(separator: ":") }
        return value.rawValue
    }

    func renderSize(from filtered: CGSize) -> CGSize {
        var size = filtered
        if let cropRatio = crop.ratio {
            let ratio = rotation == 90 || rotation == 270 ? 1 / cropRatio : cropRatio
            size.width = min(size.width, size.height * ratio)
            size.height = min(size.height, size.width / ratio)
        }
        if let aspectRatio = aspect.ratio {
            let ratio = rotation == 90 || rotation == 270 ? 1 / aspectRatio : aspectRatio
            size.width = size.height * ratio
        }
        return size
    }

    func filterGraph(colorLUT: URL?) -> String {
        var filters: [String] = []
        switch rotation {
        case 90: filters.append("transpose=clock")
        case 180: filters.append(contentsOf: ["hflip", "vflip"])
        case 270: filters.append("transpose=cclock")
        default: break
        }
        if let colorLUT {
            let path = colorLUT.path.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "'\\''").replacingOccurrences(of: ":", with: "\\:")
            filters.append("lut3d=file='\(path)':interp=tetrahedral")
        }
        return filters.isEmpty ? "" : "lavfi=[\(filters.joined(separator: ","))]"
    }

    /// A small 3D cube supplies the full set of color controls supported by the
    /// pinned library. It is generated on mpv's worker, before subtitle overlays.
    func colorLookupTable() -> String {
        let count = 17
        var cube = "TITLE \"IINA Video Adjustments\"\nLUT_3D_SIZE \(count)\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 1 1 1\n"
        for blue in 0..<count {
            for green in 0..<count {
                for red in 0..<count {
                    var rgb = SIMD3<Double>(Double(red), Double(green), Double(blue)) / Double(count - 1)
                    if hue != 0 || saturation != 0 {
                        let high = max(rgb.x, max(rgb.y, rgb.z))
                        let low = min(rgb.x, min(rgb.y, rgb.z))
                        let delta = high - low
                        var angle = 0.0
                        if delta > 0 {
                            if high == rgb.x { angle = (rgb.y - rgb.z) / delta }
                            else if high == rgb.y { angle = (rgb.z - rgb.x) / delta + 2 }
                            else { angle = (rgb.x - rgb.y) / delta + 4 }
                        }
                        angle = (angle * 60 + hue * 1.8).truncatingRemainder(dividingBy: 360)
                        if angle < 0 { angle += 360 }
                        let chroma = high * min(1, max(0, (high > 0 ? delta / high : 0) * (1 + saturation / 100)))
                        let secondary = chroma * (1 - abs((angle / 60).truncatingRemainder(dividingBy: 2) - 1))
                        switch Int(angle / 60) {
                        case 0: rgb = SIMD3(chroma, secondary, 0)
                        case 1: rgb = SIMD3(secondary, chroma, 0)
                        case 2: rgb = SIMD3(0, chroma, secondary)
                        case 3: rgb = SIMD3(0, secondary, chroma)
                        case 4: rgb = SIMD3(secondary, 0, chroma)
                        default: rgb = SIMD3(chroma, 0, secondary)
                        }
                        rgb += SIMD3(repeating: high - chroma)
                    }
                    for index in 0..<3 {
                        let value = min(1, max(0, (rgb[index] - 0.5) * (1 + contrast / 100) + 0.5 + brightness / 100))
                        rgb[index] = pow(value, 1 / pow(2, gamma / 50))
                    }
                    cube += "\(rgb.x) \(rgb.y) \(rgb.z)\n"
                }
            }
        }
        return cube
    }
}
