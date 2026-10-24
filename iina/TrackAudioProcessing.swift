//
// TrackAudioProcessing.swift
// IINA
//

import Foundation

/// Per-source processing precedes mixing; mpv's audio-delay and af stay master controls.
struct AudioTrackProcessing: Equatable {
  var delay: Double = 0
  var gains: [Double] = Array(repeating: 0, count: 10)

  var isNeutral: Bool { delay == 0 && gains.allSatisfy { $0 == 0 } }
}

enum ProcessedAudioGraph {
  static let frequencies = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

  static func equalizerTarget(trackID: Int, band: Int) -> String {
    "equalizer@iina_audio_eq_\(trackID)_\(band)"
  }

  /// If processing is needed, muted connected inputs also need named bands for runtime EQ updates.
  static func make(_ ids: Set<Int>, inputs: Set<Int>?,
                   settings: [Int: AudioTrackProcessing], sampleRate: Int) -> String? {
    let connected = inputs ?? ids
    guard !connected.isEmpty, connected.allSatisfy({ $0 > 0 }),
          ids.isSubset(of: connected) else { return nil }
    let profiles = connected.map { settings[$0] ?? AudioTrackProcessing() }
    guard profiles.contains(where: { !$0.isNeutral }) else {
      return AudioTrackMixGraph.make(ids, inputs: inputs)
    }
    guard sampleRate > 0, profiles.allSatisfy({
      $0.delay.isFinite && $0.gains.count == frequencies.count && $0.gains.allSatisfy(\.isFinite)
    }) else { return nil }

    // adelay cannot advance audio; add a common delay, then trim that priming offset on graph reset.
    let advance = max(0, -(profiles.map(\.delay).min() ?? 0))
    guard advance * Double(sampleRate) < Double(Int.max) else { return nil }
    let primingSamples = Int((advance * Double(sampleRate)).rounded())
    let hasDelay = profiles.contains { $0.delay != 0 }
    let ordered = connected.sorted()
    var parts: [String] = []
    for id in ordered {
      let profile = settings[id] ?? AudioTrackProcessing()
      if hasDelay {
        // adelay priming has unknown PTS; retain an untreated clock branch to preserve timeline and duration.
        parts.append("[aid\(id)]asplit=2[iina_audio_clock_\(id)][iina_audio_source_\(id)]")
      }
      var filters = ["aresample=\(sampleRate)"]
      if hasDelay {
        let samples = (profile.delay + advance) * Double(sampleRate)
        guard samples >= 0, samples < Double(Int.max) else { return nil }
        filters.append("adelay=delays=\(Int(samples.rounded()))S:all=1")
      }
      for (band, frequency) in frequencies.enumerated() {
        // Clamp unreachable EQ bands below Nyquist without changing the stored UI gain.
        let center = min(Double(frequency), Double(sampleRate) * 0.499)
        filters.append("\(equalizerTarget(trackID: id, band: band))=" +
                       "f=\(number(center)):t=h:width=\(number(center / 1.224744871)):g=\(number(profile.gains[band]))")
      }
      let source = hasDelay ? "iina_audio_source_\(id)" : "aid\(id)"
      parts.append("[\(source)]" + filters.joined(separator: ",") + "[iina_audio_\(id)]")
    }
    if hasDelay {
      let clocks = ordered.map { "[iina_audio_clock_\($0)]" }.joined()
      let silence = ordered.map { _ in "0" }.joined(separator: " ")
      parts.append(clocks + "amix=inputs=\(ordered.count):duration=longest:normalize=0:" +
                   "dropout_transition=0:weights='\(silence)',aresample=\(sampleRate)," +
                   "apad=pad_len=\(primingSamples)[iina_audio_clock]")
    }
    let gains = AudioTrackMixGraph.weights(ids, inputs: connected)
    let branches = ordered.map { "[iina_audio_\($0)]" }.joined()
    var mixer = branches + "\(AudioTrackMixGraph.target)=inputs=\(ordered.count):" +
                "normalize=0:dropout_transition=0:weights='\(gains)'"
    if hasDelay {
      mixer += "[iina_audio_processed];[iina_audio_clock][iina_audio_processed]" +
               "amix=inputs=2:duration=first:normalize=0:dropout_transition=0:weights='0 1'," +
               "aresample=\(sampleRate),atrim=start_sample=\(primingSamples)," +
               "asetpts=PTS-\(number(advance))/TB"
    }
    mixer += ",alimiter=level=false:latency=true[ao]"
    parts.append(mixer)
    return parts.joined(separator: ";")
  }

  private static func number(_ value: Double) -> String {
    String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), value)
  }
}
